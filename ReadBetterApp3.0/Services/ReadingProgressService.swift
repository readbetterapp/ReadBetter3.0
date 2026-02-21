//
//  ReadingProgressService.swift
//  ReadBetterApp3.0
//
//  Hybrid local+cloud reading progress service.
//  - Saves instantly to UserDefaults for immediate feedback
//  - Syncs to Firestore in background (debounced)
//  - Merges local + cloud data on launch
//

import Foundation
import Combine
import FirebaseFirestore

@MainActor
final class ReadingProgressService: ObservableObject {
    static let shared = ReadingProgressService()
    
    // MARK: - Published State
    
    @Published private(set) var progressByBookId: [String: ReadingProgress] = [:]
    @Published private(set) var mostRecentProgress: ReadingProgress?
    @Published private(set) var isLoaded: Bool = false
    
    // MARK: - Private Properties
    
    private let db = Firestore.firestore()
    private let localStorageKey = "reading-progress-local"
    private let userDefaults = UserDefaults.standard
    
    private var uid: String?
    private var firestoreListener: ListenerRegistration?
    private var syncTimer: Timer?
    private var pendingSyncBookIds: Set<String> = []
    private let syncDebounceInterval: TimeInterval = 30 // Sync every 30 seconds
    
    // MARK: - Initialization
    
    private init() {
        loadFromLocal()
    }
    
    // MARK: - User Binding
    
    /// Set the current user - only syncs to cloud for real accounts (not anonymous/guests)
    func setUser(uid: String?, isAnonymous: Bool = false) {
        if self.uid == uid { return }
        
        // Stop existing listener
        firestoreListener?.remove()
        firestoreListener = nil
        syncTimer?.invalidate()
        syncTimer = nil
        
        self.uid = uid
        
        // Only sync to cloud for real users (not anonymous/guests)
        if let uid = uid, !isAnonymous {
            // Start listening to Firestore
            startFirestoreListener(uid: uid)
            // Start sync timer
            startSyncTimer()
            // Initial merge
            Task {
                await mergeWithCloud()
            }
            print("✅ ReadingProgressService: Started cloud sync for user \(uid)")
        } else {
            // Guest/anonymous - only use local storage
            print("ℹ️ ReadingProgressService: Using local-only mode (guest/anonymous)")
        }
        
        updateMostRecent()
    }
    
    // MARK: - Public Methods
    
    /// Save progress - instant local save, queued for cloud sync
    func saveProgress(_ progress: ReadingProgress) {
        var updatedProgress = progress
        updatedProgress.updatedAt = Date()
        updatedProgress.lastReadAt = Date()
        
        // Instant local save
        progressByBookId[progress.bookId] = updatedProgress
        saveToLocal()
        updateMostRecent()
        
        // Queue for cloud sync
        pendingSyncBookIds.insert(progress.bookId)
    }
    
    /// Get progress for a specific book
    func getProgress(for bookId: String) -> ReadingProgress? {
        return progressByBookId[bookId]
    }
    
    /// Check if user has started reading a book
    func hasStartedReading(bookId: String) -> Bool {
        return progressByBookId[bookId] != nil
    }
    
    /// Get all progress entries sorted by last read
    func getAllProgress() -> [ReadingProgress] {
        return progressByBookId.values.sorted { $0.lastReadAt > $1.lastReadAt }
    }
    
    /// Clear progress for a book
    func clearProgress(for bookId: String) {
        progressByBookId.removeValue(forKey: bookId)
        saveToLocal()
        updateMostRecent()
        
        // Also delete from Firestore
        guard let uid = uid else { return }
        Task {
            try? await progressRef(uid: uid).document(bookId).delete()
        }
    }
    
    /// Force sync to cloud (call on app close)
    func forceSyncToCloud() {
        guard let uid = uid, !pendingSyncBookIds.isEmpty else { return }
        
        Task {
            await syncPendingToFirestore(uid: uid)
        }
    }
    
    /// Mark a chapter as complete
    func markChapterComplete(bookId: String, chapterId: String) {
        guard var progress = progressByBookId[bookId] else { return }
        progress.markChapterComplete(chapterId)
        saveProgress(progress)
    }
    
    // MARK: - Local Storage
    
    private func loadFromLocal() {
        guard let data = userDefaults.data(forKey: localStorageKey),
              let decoded = try? JSONDecoder().decode([String: ReadingProgress].self, from: data) else {
            isLoaded = true
            return
        }
        
        progressByBookId = decoded
        updateMostRecent()
        isLoaded = true
    }
    
    private func saveToLocal() {
        guard let data = try? JSONEncoder().encode(progressByBookId) else { return }
        userDefaults.set(data, forKey: localStorageKey)
    }
    
    // MARK: - Firestore Sync
    
    private func startFirestoreListener(uid: String) {
        firestoreListener = progressRef(uid: uid)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self = self else { return }
                
                if let error = error {
                    print("❌ ReadingProgressService: Firestore listener error: \(error)")
                    return
                }
                
                guard let documents = snapshot?.documents else { return }
                
                // Merge cloud data with local (cloud wins if newer)
                for doc in documents {
                    if let cloudProgress = ReadingProgress(id: doc.documentID, data: doc.data()) {
                        if let localProgress = self.progressByBookId[cloudProgress.bookId] {
                            // Keep whichever is newer
                            if cloudProgress.updatedAt > localProgress.updatedAt {
                                self.progressByBookId[cloudProgress.bookId] = cloudProgress
                            }
                        } else {
                            // No local version, use cloud
                            self.progressByBookId[cloudProgress.bookId] = cloudProgress
                        }
                    }
                }
                
                self.saveToLocal()
                self.updateMostRecent()
            }
    }
    
    private func startSyncTimer() {
        syncTimer = Timer.scheduledTimer(withTimeInterval: syncDebounceInterval, repeats: true) { [weak self] _ in
            guard let self = self, let uid = self.uid else { return }
            Task { @MainActor in
                await self.syncPendingToFirestore(uid: uid)
            }
        }
    }
    
    private func syncPendingToFirestore(uid: String) async {
        guard !pendingSyncBookIds.isEmpty else { return }
        
        let bookIdsToSync = pendingSyncBookIds
        pendingSyncBookIds.removeAll()
        
        for bookId in bookIdsToSync {
            guard let progress = progressByBookId[bookId] else { continue }
            
            do {
                try await progressRef(uid: uid).document(bookId).setData(progress.asFirestoreData(), merge: true)
                print("✅ ReadingProgressService: Synced progress for \(bookId)")
            } catch {
                print("❌ ReadingProgressService: Failed to sync \(bookId): \(error)")
                // Re-queue for next sync
                pendingSyncBookIds.insert(bookId)
            }
        }
    }
    
    private func mergeWithCloud() async {
        guard let uid = uid else { return }
        
        do {
            let snapshot = try await progressRef(uid: uid).getDocuments()
            
            for doc in snapshot.documents {
                if let cloudProgress = ReadingProgress(id: doc.documentID, data: doc.data()) {
                    if let localProgress = progressByBookId[cloudProgress.bookId] {
                        // Keep whichever is newer
                        if cloudProgress.updatedAt > localProgress.updatedAt {
                            progressByBookId[cloudProgress.bookId] = cloudProgress
                        } else if localProgress.updatedAt > cloudProgress.updatedAt {
                            // Local is newer, queue for sync
                            pendingSyncBookIds.insert(localProgress.bookId)
                        }
                    } else {
                        // No local version, use cloud
                        progressByBookId[cloudProgress.bookId] = cloudProgress
                    }
                }
            }
            
            saveToLocal()
            updateMostRecent()
            
            // Sync any local-only progress to cloud
            for (bookId, _) in progressByBookId {
                let existsInCloud = snapshot.documents.contains { $0.documentID == bookId }
                if !existsInCloud {
                    pendingSyncBookIds.insert(bookId)
                }
            }
            
            if !pendingSyncBookIds.isEmpty {
                await syncPendingToFirestore(uid: uid)
            }
            
        } catch {
            print("❌ ReadingProgressService: Failed to merge with cloud: \(error)")
        }
    }
    
    // MARK: - Helpers
    
    private func progressRef(uid: String) -> CollectionReference {
        db.collection("users").document(uid).collection("readingProgress")
    }
    
    private func updateMostRecent() {
        mostRecentProgress = progressByBookId.values
            .sorted { $0.lastReadAt > $1.lastReadAt }
            .first
    }
}




