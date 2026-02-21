//
//  BookOwnershipService.swift
//  ReadBetterApp3.0
//
//  Created by Ermin on 30/11/2025.
//

import Foundation
import Combine
import FirebaseFirestore
import FirebaseAuth

/// Service for managing book ownership/unlocking
/// For testing: password "unlock" simulates purchase
/// IMPORTANT: Only signed-in users (not anonymous/guests) can own books
class BookOwnershipService: ObservableObject {
    static let shared = BookOwnershipService()
    
    @Published var ownedBooks: Set<String> = []
    @Published var isLoaded: Bool = false
    
    private let ownershipKey = "owned-books"
    private let unlockPassword = "unlock" // Test password for simulating purchase
    private let userDefaults = UserDefaults.standard
    private let db = Firestore.firestore()
    private var listener: ListenerRegistration?
    private var authListener: NSObjectProtocol?
    
    private init() {
        // Listen for auth state changes to reload data when user signs in/out
        authListener = NotificationCenter.default.addObserver(
            forName: .AuthStateDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleAuthStateChange()
        }
        
        handleAuthStateChange()
    }
    
    /// Handle auth state changes - reload data for current user
    private func handleAuthStateChange() {
        // Remove old listener
        listener?.remove()
        listener = nil
        
        guard let currentUser = Auth.auth().currentUser else {
            // No user signed in - clear owned books (guests don't own anything)
            ownedBooks = []
            isLoaded = true
            print("ℹ️ BookOwnershipService: No user signed in, cleared owned books")
            return
        }
        
        // Only load ownership data for real accounts (not anonymous)
        if currentUser.isAnonymous {
            ownedBooks = []
            isLoaded = true
            print("ℹ️ BookOwnershipService: Anonymous user, no owned books")
            return
        }
        
        // Real user - load their data
        loadOwnedBooks(for: currentUser.uid)
        setupFirestoreListener()
    }
    
    // MARK: - Public Methods
    
    /// Check if user owns a book
    func isBookOwned(bookId: String) -> Bool {
        return ownedBooks.contains(bookId)
    }
    
    /// Check if user can purchase books (must be signed in with real account)
    var canPurchase: Bool {
        guard let user = Auth.auth().currentUser else { return false }
        return !user.isAnonymous
    }
    
    /// Attempt to unlock a book with password
    /// Returns true if successful, false otherwise
    /// REQUIRES: User must be signed in with a real account (not anonymous/guest)
    func unlockBook(bookId: String, password: String) -> Bool {
        // REQUIRE real account for purchases
        guard let currentUser = Auth.auth().currentUser, !currentUser.isAnonymous else {
            print("⚠️ BookOwnershipService: Cannot unlock book - user must be signed in")
            return false
        }
        
        // Check if already owned
        if ownedBooks.contains(bookId) {
            return true
        }
        
        // Validate password
        if password.lowercased().trimmingCharacters(in: .whitespaces) != unlockPassword {
            return false
        }
        
        // Add to owned books
        ownedBooks.insert(bookId)
        saveOwnedBooks(for: currentUser.uid)
        syncToFirestore(bookId: bookId)
        
        return true
    }
    
    /// Get all owned book IDs
    func getOwnedBooks() -> Set<String> {
        return ownedBooks
    }
    
    /// Clear all ownership (for testing/logout)
    func clearOwnership() {
        ownedBooks.removeAll()
        saveOwnedBooks()
    }
    
    // MARK: - Private Methods
    
    /// Load owned books for a specific user (stored per-user in UserDefaults)
    private func loadOwnedBooks(for userId: String) {
        let key = "\(ownershipKey)-\(userId)"
        if let data = userDefaults.data(forKey: key),
           let books = try? JSONDecoder().decode([String].self, from: data) {
            ownedBooks = Set(books)
            print("✅ BookOwnershipService: Loaded \(ownedBooks.count) owned books for user \(userId)")
        } else {
            ownedBooks = []
        }
        isLoaded = true
    }
    
    /// Save owned books for a specific user
    private func saveOwnedBooks(for userId: String) {
        let key = "\(ownershipKey)-\(userId)"
        let booksArray = Array(ownedBooks)
        if let data = try? JSONEncoder().encode(booksArray) {
            userDefaults.set(data, forKey: key)
        }
    }
    
    /// Legacy save method - uses current user
    private func saveOwnedBooks() {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        saveOwnedBooks(for: userId)
    }
    
    // MARK: - Firestore Sync
    
    private func setupFirestoreListener() {
        guard let currentUser = Auth.auth().currentUser,
              !currentUser.isAnonymous else {
            print("ℹ️ BookOwnershipService: Skipping Firestore listener for guest/anonymous user")
            return
        }
        
        let userId = currentUser.uid
        
        listener = db.collection("users")
            .document(userId)
            .collection("ownedBooks")
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self = self else { return }
                
                if let error = error {
                    print("❌ BookOwnershipService: Error listening to Firestore: \(error)")
                    return
                }
                
                guard let documents = snapshot?.documents else { return }
                
                let firestoreBooks = Set(documents.map { $0.documentID })
                
                // FIREBASE IS SOURCE OF TRUTH
                // Update local to match Firebase (handles both additions and deletions)
                if firestoreBooks != self.ownedBooks {
                    let added = firestoreBooks.subtracting(self.ownedBooks)
                    let removed = self.ownedBooks.subtracting(firestoreBooks)
                    
                    if !added.isEmpty {
                        print("✅ BookOwnershipService: Added books from Firestore: \(added)")
                    }
                    if !removed.isEmpty {
                        print("🗑️ BookOwnershipService: Removed books deleted from Firestore: \(removed)")
                    }
                    
                    self.ownedBooks = firestoreBooks
                    self.saveOwnedBooks(for: userId)
                    print("✅ BookOwnershipService: Synced \(firestoreBooks.count) owned books from Firestore")
                }
            }
    }
    
    private func syncToFirestore(bookId: String) {
        guard let userId = Auth.auth().currentUser?.uid else {
            print("⚠️ BookOwnershipService: No user logged in, skipping Firestore sync")
            return
        }
        
        let docRef = db.collection("users")
            .document(userId)
            .collection("ownedBooks")
            .document(bookId)
        
        docRef.setData([
            "unlockedAt": FieldValue.serverTimestamp(),
            "bookId": bookId
        ]) { error in
            if let error = error {
                print("❌ BookOwnershipService: Failed to sync \(bookId) to Firestore: \(error)")
            } else {
                print("✅ BookOwnershipService: Successfully synced \(bookId) to Firestore")
            }
        }
    }
    
    /// Sync all locally owned books to Firestore (for migration/initial sync)
    private func syncLocalBooksToFirestore() {
        guard let currentUser = Auth.auth().currentUser,
              !currentUser.isAnonymous else {
            print("⚠️ BookOwnershipService: No real user logged in, skipping local books sync")
            return
        }
        
        let userId = currentUser.uid
        
        guard !ownedBooks.isEmpty else {
            print("ℹ️ BookOwnershipService: No local books to sync")
            return
        }
        
        print("🔄 BookOwnershipService: Syncing \(ownedBooks.count) local books to Firestore...")
        
        let batch = db.batch()
        let userRef = db.collection("users").document(userId)
        
        for bookId in ownedBooks {
            let bookRef = userRef.collection("ownedBooks").document(bookId)
            batch.setData([
                "unlockedAt": FieldValue.serverTimestamp(),
                "bookId": bookId
            ], forDocument: bookRef, merge: true)
        }
        
        batch.commit { error in
            if let error = error {
                print("❌ BookOwnershipService: Failed to sync local books: \(error)")
            } else {
                print("✅ BookOwnershipService: Successfully synced \(self.ownedBooks.count) local books to Firestore")
            }
        }
    }
    
    deinit {
        listener?.remove()
        if let authListener = authListener {
            NotificationCenter.default.removeObserver(authListener)
        }
    }
}

// MARK: - Auth State Change Notification
extension Notification.Name {
    static let AuthStateDidChangeNotification = Notification.Name("AuthStateDidChangeNotification")
}

