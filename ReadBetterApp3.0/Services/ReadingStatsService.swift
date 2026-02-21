//
//  ReadingStatsService.swift
//  ReadBetterApp3.0
//
//  Service for tracking daily reading sessions and calculating stats.
//  - Tracks listening time, chapters completed, and books read per day
//  - Calculates reading streaks and weekly aggregates
//  - Syncs to Firestore for persistence and future analytics
//

import Foundation
import Combine
import FirebaseFirestore

@MainActor
final class ReadingStatsService: ObservableObject {
    static let shared = ReadingStatsService()
    
    // MARK: - Published Stats
    
    @Published private(set) var currentStreak: Int = 0
    @Published private(set) var weeklyListenedSeconds: Double = 0
    @Published private(set) var weeklyChaptersCompleted: Int = 0
    @Published private(set) var todaySession: ReadingSession?
    @Published private(set) var isLoaded: Bool = false
    
    // MARK: - Private Properties
    
    private let db = Firestore.firestore()
    private let localStorageKey = "reading-sessions-local"
    private let userDefaults = UserDefaults.standard
    
    private var uid: String?
    private var isAnonymous: Bool = true
    private var sessions: [String: ReadingSession] = [:] // date -> session
    private var pendingSync: Bool = false
    private var syncTimer: Timer?
    private let syncDebounceInterval: TimeInterval = 30
    
    // Streak minimum requirement (5 minutes = 300 seconds)
    private let streakMinimumSeconds: Double = 300
    
    // MARK: - Initialization
    
    private init() {
        loadFromLocal()
    }
    
    // MARK: - User Binding
    
    func setUser(uid: String?, isAnonymous: Bool = false) {
        if self.uid == uid { return }
        
        syncTimer?.invalidate()
        syncTimer = nil
        
        self.uid = uid
        self.isAnonymous = isAnonymous
        
        if let uid = uid, !isAnonymous {
            // Start sync timer for real users
            startSyncTimer()
            // Fetch from cloud and merge
            Task {
                await fetchFromCloud(uid: uid)
            }
            print("✅ ReadingStatsService: Started cloud sync for user \(uid)")
        } else {
            print("ℹ️ ReadingStatsService: Using local-only mode (guest/anonymous)")
        }
        
        recalculateStats()
    }
    
    // MARK: - Public Methods
    
    /// Log listening time for the current day
    func logListeningTime(seconds: Double, bookId: String) {
        let today = ReadingSession.dateString(for: Date())
        
        var session = sessions[today] ?? ReadingSession(date: today)
        session.addListeningTime(seconds, bookId: bookId)
        sessions[today] = session
        todaySession = session
        
        saveToLocal()
        pendingSync = true
        recalculateStats()
    }
    
    /// Log a chapter completion for the current day
    func logChapterComplete(bookId: String) {
        let today = ReadingSession.dateString(for: Date())
        
        var session = sessions[today] ?? ReadingSession(date: today)
        session.addChapterCompleted(bookId: bookId)
        sessions[today] = session
        todaySession = session
        
        saveToLocal()
        pendingSync = true
        recalculateStats()
    }
    
    /// Force sync to cloud (call on app close)
    func forceSyncToCloud() {
        guard let uid = uid, !isAnonymous, pendingSync else { return }
        
        Task {
            await syncToFirestore(uid: uid)
        }
    }
    
    /// Get session for a specific date
    func getSession(for date: Date) -> ReadingSession? {
        let dateString = ReadingSession.dateString(for: date)
        return sessions[dateString]
    }
    
    /// Get all sessions sorted by date (newest first)
    func getAllSessions() -> [ReadingSession] {
        sessions.values.sorted { $0.date > $1.date }
    }
    
    // MARK: - Stats Calculation
    
    private func recalculateStats() {
        calculateStreak()
        calculateWeeklyStats()
        
        // Update today session reference
        let today = ReadingSession.dateString(for: Date())
        todaySession = sessions[today]
        
        isLoaded = true
    }
    
    private func calculateStreak() {
        var streak = 0
        var checkDate = Date()
        let calendar = Calendar.current
        
        // Check if today counts - if not, start from yesterday
        let todayString = ReadingSession.dateString(for: checkDate)
        if let todaySession = sessions[todayString], todaySession.countsTowardStreak {
            streak = 1
            checkDate = calendar.date(byAdding: .day, value: -1, to: checkDate) ?? checkDate
        } else {
            // Today doesn't count yet, check if yesterday counted
            checkDate = calendar.date(byAdding: .day, value: -1, to: checkDate) ?? checkDate
        }
        
        // Count consecutive days going backward
        for _ in 0..<365 { // Max 1 year of streak checking
            let dateString = ReadingSession.dateString(for: checkDate)
            
            if let session = sessions[dateString], session.countsTowardStreak {
                streak += 1
                checkDate = calendar.date(byAdding: .day, value: -1, to: checkDate) ?? checkDate
            } else {
                break
            }
        }
        
        currentStreak = streak
    }
    
    private func calculateWeeklyStats() {
        let calendar = Calendar.current
        let today = Date()
        
        var totalSeconds: Double = 0
        var totalChapters: Int = 0
        
        // Sum last 7 days
        for dayOffset in 0..<7 {
            guard let date = calendar.date(byAdding: .day, value: -dayOffset, to: today) else { continue }
            let dateString = ReadingSession.dateString(for: date)
            
            if let session = sessions[dateString] {
                totalSeconds += session.listenedSeconds
                totalChapters += session.chaptersCompleted
            }
        }
        
        weeklyListenedSeconds = totalSeconds
        weeklyChaptersCompleted = totalChapters
    }
    
    // MARK: - Local Storage
    
    private func loadFromLocal() {
        guard let data = userDefaults.data(forKey: localStorageKey),
              let decoded = try? JSONDecoder().decode([String: ReadingSession].self, from: data) else {
            isLoaded = true
            return
        }
        
        sessions = decoded
        recalculateStats()
    }
    
    private func saveToLocal() {
        guard let data = try? JSONEncoder().encode(sessions) else { return }
        userDefaults.set(data, forKey: localStorageKey)
    }
    
    // MARK: - Firestore Sync
    
    private func startSyncTimer() {
        syncTimer = Timer.scheduledTimer(withTimeInterval: syncDebounceInterval, repeats: true) { [weak self] _ in
            guard let self = self, let uid = self.uid, self.pendingSync else { return }
            Task { @MainActor in
                await self.syncToFirestore(uid: uid)
            }
        }
    }
    
    private func fetchFromCloud(uid: String) async {
        do {
            // Fetch last 30 days of sessions for streak calculation
            let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
            let startDateString = ReadingSession.dateString(for: thirtyDaysAgo)
            
            let snapshot = try await sessionsRef(uid: uid)
                .whereField(FieldPath.documentID(), isGreaterThanOrEqualTo: startDateString)
                .getDocuments()
            
            for doc in snapshot.documents {
                if let cloudSession = ReadingSession(id: doc.documentID, data: doc.data()) {
                    // Merge: keep whichever has more data
                    if let localSession = sessions[cloudSession.date] {
                        if cloudSession.listenedSeconds > localSession.listenedSeconds {
                            sessions[cloudSession.date] = cloudSession
                        }
                    } else {
                        sessions[cloudSession.date] = cloudSession
                    }
                }
            }
            
            saveToLocal()
            recalculateStats()
            print("✅ ReadingStatsService: Fetched \(snapshot.documents.count) sessions from cloud")
            
        } catch {
            print("❌ ReadingStatsService: Failed to fetch from cloud: \(error)")
        }
    }
    
    private func syncToFirestore(uid: String) async {
        guard pendingSync else { return }
        pendingSync = false
        
        // Only sync today's session (most common case)
        let today = ReadingSession.dateString(for: Date())
        guard let session = sessions[today] else { return }
        
        do {
            try await sessionsRef(uid: uid).document(today).setData(session.asFirestoreData(), merge: true)
            print("✅ ReadingStatsService: Synced session for \(today)")
        } catch {
            print("❌ ReadingStatsService: Failed to sync: \(error)")
            pendingSync = true // Re-queue for next sync
        }
    }
    
    // MARK: - Helpers
    
    private func sessionsRef(uid: String) -> CollectionReference {
        db.collection("users").document(uid).collection("readingSessions")
    }
}

// MARK: - Formatted Stats (for UI)

extension ReadingStatsService {
    /// Weekly listening time formatted (e.g., "3.5h" or "45m")
    var weeklyTimeFormatted: String {
        let hours = weeklyListenedSeconds / 3600
        let minutes = Int(weeklyListenedSeconds) % 3600 / 60
        
        if hours >= 1 {
            if hours == Double(Int(hours)) {
                return "\(Int(hours))h"
            } else {
                return String(format: "%.1fh", hours)
            }
        } else if minutes > 0 {
            return "\(minutes)m"
        } else {
            return "0m"
        }
    }
    
    /// Whether the user has read today (counts toward streak)
    var hasReadToday: Bool {
        todaySession?.countsTowardStreak ?? false
    }
    
    /// Whether the streak is currently active (read today or yesterday)
    var isStreakActive: Bool {
        if hasReadToday { return true }
        
        // Check if yesterday counted
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date()
        let yesterdayString = ReadingSession.dateString(for: yesterday)
        return sessions[yesterdayString]?.countsTowardStreak ?? false
    }
}
