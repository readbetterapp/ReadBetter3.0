//
//  BookOwnershipService.swift
//  ReadBetterApp3.0
//
//  Created by Ermin on 30/11/2025.
//

import Foundation
import Combine

/// Service for managing book ownership/unlocking
/// For testing: password "unlock" simulates purchase
class BookOwnershipService: ObservableObject {
    static let shared = BookOwnershipService()
    
    @Published var ownedBooks: Set<String> = []
    @Published var isLoaded: Bool = false
    
    private let ownershipKey = "owned-books"
    private let unlockPassword = "unlock" // Test password for simulating purchase
    private let userDefaults = UserDefaults.standard
    
    private init() {
        loadOwnedBooks()
    }
    
    // MARK: - Public Methods
    
    /// Check if user owns a book
    func isBookOwned(bookId: String) -> Bool {
        return ownedBooks.contains(bookId)
    }
    
    /// Attempt to unlock a book with password
    /// Returns true if successful, false otherwise
    func unlockBook(bookId: String, password: String) -> Bool {
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
        saveOwnedBooks()
        
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
    
    private func loadOwnedBooks() {
        if let data = userDefaults.data(forKey: ownershipKey),
           let books = try? JSONDecoder().decode([String].self, from: data) {
            ownedBooks = Set(books)
        }
        isLoaded = true
    }
    
    private func saveOwnedBooks() {
        let booksArray = Array(ownedBooks)
        if let data = try? JSONEncoder().encode(booksArray) {
            userDefaults.set(data, forKey: ownershipKey)
        }
    }
}

