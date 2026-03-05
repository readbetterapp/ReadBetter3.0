//
//  BookmarkService.swift
//  ReadBetterApp3.0
//
//  Firestore-backed bookmarking service.
//  Data is stored per-user under:
//  - users/{uid}/folders/{folderId}
//  - users/{uid}/bookmarks/{bookmarkId}
//

import Foundation
import Combine
import FirebaseFirestore

@MainActor
final class BookmarkService: ObservableObject {
    @Published private(set) var folders: [BookmarkFolder] = []
    @Published private(set) var foldersById: [String: BookmarkFolder] = [:]
    @Published private(set) var bookmarks: [Bookmark] = []
    @Published private(set) var bookmarksById: [String: Bookmark] = [:]
    @Published var lastErrorMessage: String? = nil
    
    private let db = Firestore.firestore()
    private var foldersListener: ListenerRegistration?
    private var bookmarksListener: ListenerRegistration?
    
    private(set) var uid: String?
    
    // MARK: - Lifecycle
    
    func setUser(uid: String?) {
        if self.uid == uid { return }
        self.uid = uid
        
        stopListeners()
        folders = []
        foldersById = [:]
        bookmarks = []
        bookmarksById = [:]
        lastErrorMessage = nil
        
        guard let uid else { return }
        startListeners(uid: uid)
    }
    
    private func startListeners(uid: String) {
        // Folders
        foldersListener = foldersRef(uid: uid)
            .order(by: "updatedAt", descending: true)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self else { return }
                if let error {
                    self.lastErrorMessage = "Folder sync failed: \(error.localizedDescription)"
                    return
                }
                let docs = snapshot?.documents ?? []
                let items = docs.map { BookmarkFolder(id: $0.documentID, data: $0.data()) }
                self.folders = items.sorted(by: self.folderSort)
                self.foldersById = Dictionary(uniqueKeysWithValues: self.folders.map { ($0.id, $0) })
            }
        
        // Bookmarks
        bookmarksListener = bookmarksRef(uid: uid)
            .order(by: "updatedAt", descending: true)
            .limit(to: 500)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self else { return }
                if let error {
                    self.lastErrorMessage = "Bookmark sync failed: \(error.localizedDescription)"
                    return
                }
                let docs = snapshot?.documents ?? []
                let items = docs.map { Bookmark(id: $0.documentID, data: $0.data()) }
                self.bookmarks = items.sorted(by: self.bookmarkSort)
                self.bookmarksById = Dictionary(uniqueKeysWithValues: self.bookmarks.map { ($0.id, $0) })
            }
    }
    
    private func stopListeners() {
        foldersListener?.remove()
        foldersListener = nil
        bookmarksListener?.remove()
        bookmarksListener = nil
    }
    
    // MARK: - Public helpers
    
    func isBookmarked(bookmarkId: String) -> Bool {
        bookmarksById[bookmarkId] != nil
    }
    
    func bookmarkForId(_ bookmarkId: String) -> Bookmark? {
        bookmarksById[bookmarkId]
    }
    
    func recentBookmarks(limit: Int = 10) -> [Bookmark] {
        Array(bookmarks.prefix(limit))
    }
    
    func bookmarks(inFolder folderId: String) -> [Bookmark] {
        bookmarks.filter { $0.folderIds.contains(folderId) }
            .sorted(by: bookmarkSort)
    }
    
    func unsortedBookmarks() -> [Bookmark] {
        bookmarks.filter { $0.folderIds.isEmpty }
            .sorted(by: bookmarkSort)
    }
    
    // MARK: - CRUD
    
    @discardableResult
    func toggleBookmark(bookId: String,
                        chapterId: String,
                        chapterNumber: Int?,
                        isDescription: Bool,
                        sentenceIndex: Int,
                        startTime: Double,
                        text: String) async throws -> Bool {
        guard let uid else {
            throw NSError(domain: "BookmarkService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing user id"])
        }
        
        let id = Bookmark.makeId(bookId: bookId, chapterId: chapterId, sentenceIndex: sentenceIndex)
        let docRef = bookmarksRef(uid: uid).document(id)
        
        if isBookmarked(bookmarkId: id) {
            // Fire-and-forget: don't await server ack so the UI never blocks offline.
            // Firestore persistence queues the delete locally and syncs when back online.
            Task { try? await docRef.delete() }
            return false
        } else {
            let b = Bookmark(
                id: id,
                bookId: bookId,
                chapterId: chapterId,
                chapterNumber: chapterNumber,
                isDescription: isDescription,
                sentenceIndex: sentenceIndex,
                startTime: startTime,
                text: text,
                folderIds: [],
                starred: false
            )
            // Fire-and-forget: returns immediately regardless of network state.
            // Firestore persistence queues the write locally and syncs when back online.
            Task { try? await docRef.setData(b.asFirestoreData(creating: true), merge: true) }
            return true
        }
    }
    
    /// Ensures the bookmark exists (used for long-press folder assignment).
    func ensureBookmark(bookId: String,
                        chapterId: String,
                        chapterNumber: Int?,
                        isDescription: Bool,
                        sentenceIndex: Int,
                        startTime: Double,
                        text: String) async throws -> Bookmark {
        guard let uid else {
            throw NSError(domain: "BookmarkService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing user id"])
        }
        
        let id = Bookmark.makeId(bookId: bookId, chapterId: chapterId, sentenceIndex: sentenceIndex)
        if let existing = bookmarkForId(id) {
            return existing
        }
        
        let b = Bookmark(
            id: id,
            bookId: bookId,
            chapterId: chapterId,
            chapterNumber: chapterNumber,
            isDescription: isDescription,
            sentenceIndex: sentenceIndex,
            startTime: startTime,
            text: text,
            folderIds: [],
            starred: false
        )
        try await bookmarksRef(uid: uid).document(id).setData(b.asFirestoreData(creating: true), merge: true)
        return b
    }
    
    func setFolders(bookmarkId: String, folderIds: [String]) async throws {
        guard let uid else {
            throw NSError(domain: "BookmarkService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing user id"])
        }
        try await bookmarksRef(uid: uid).document(bookmarkId).setData([
            "folderIds": folderIds,
            "updatedAt": FieldValue.serverTimestamp()
        ], merge: true)
    }
    
    func setStarred(bookmarkId: String, starred: Bool) async throws {
        guard let uid else {
            throw NSError(domain: "BookmarkService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing user id"])
        }
        try await bookmarksRef(uid: uid).document(bookmarkId).setData([
            "starred": starred,
            "updatedAt": FieldValue.serverTimestamp()
        ], merge: true)
    }
    
    func createFolder(name: String) async throws -> BookmarkFolder {
        guard let uid else {
            throw NSError(domain: "BookmarkService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing user id"])
        }
        
        let clean = name.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        let folderId = UUID().uuidString
        let folder = BookmarkFolder(id: folderId, name: clean.isEmpty ? "Untitled" : clean)
        try await foldersRef(uid: uid).document(folderId).setData(folder.asFirestoreData(creating: true), merge: true)
        return folder
    }
    
    func renameFolder(folderId: String, name: String) async throws {
        guard let uid else {
            throw NSError(domain: "BookmarkService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing user id"])
        }
        let clean = name.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        try await foldersRef(uid: uid).document(folderId).setData([
            "name": clean,
            "updatedAt": FieldValue.serverTimestamp()
        ], merge: true)
    }
    
    func deleteFolder(folderId: String) async throws {
        guard let uid else {
            throw NSError(domain: "BookmarkService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing user id"])
        }
        
        // Remove folder reference from bookmarks (best-effort).
        let query = bookmarksRef(uid: uid).whereField("folderIds", arrayContains: folderId)
        let snapshot = try await query.getDocuments()
        
        let batch = db.batch()
        for doc in snapshot.documents {
            batch.updateData([
                "folderIds": FieldValue.arrayRemove([folderId]),
                "updatedAt": FieldValue.serverTimestamp()
            ], forDocument: doc.reference)
        }
        batch.deleteDocument(foldersRef(uid: uid).document(folderId))
        try await batch.commit()
    }
    
    // MARK: - Firestore references
    
    private func foldersRef(uid: String) -> CollectionReference {
        db.collection("users").document(uid).collection("folders")
    }
    
    private func bookmarksRef(uid: String) -> CollectionReference {
        db.collection("users").document(uid).collection("bookmarks")
    }
    
    // MARK: - Sorting
    
    private func folderSort(_ a: BookmarkFolder, _ b: BookmarkFolder) -> Bool {
        // Primary: explicit sortOrder; Secondary: updatedAt; Tertiary: name
        if let ao = a.sortOrder, let bo = b.sortOrder, ao != bo {
            return ao < bo
        }
        let ad = a.updatedAt ?? a.createdAt ?? Date.distantPast
        let bd = b.updatedAt ?? b.createdAt ?? Date.distantPast
        if ad != bd { return ad > bd }
        return a.name.lowercased() < b.name.lowercased()
    }
    
    private func bookmarkSort(_ a: Bookmark, _ b: Bookmark) -> Bool {
        let ad = a.updatedAt ?? a.createdAt ?? Date.distantPast
        let bd = b.updatedAt ?? b.createdAt ?? Date.distantPast
        if ad != bd { return ad > bd }
        return a.id < b.id
    }
}


