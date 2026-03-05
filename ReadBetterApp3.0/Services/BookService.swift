//
//  BookService.swift
//  ReadBetterApp3.0
//
//  Created by Ermin on 30/11/2025.
//

import Foundation
import Combine
import FirebaseFirestore
import OSLog
import UIKit

/// Service for fetching books from Firestore
/// Note: Book processing (adding new books from GCS) is handled by Cloud Functions
class BookService: ObservableObject {
    static let shared = BookService()
    
    private let db = Firestore.firestore()
    private let logger = Logger(subsystem: "com.readbetter", category: "BookService")
    
    @Published var books: [Book] = []
    @Published var filteredBooks: [Book] = []
    @Published var selectedGenre: String? = nil
    @Published var isLoading = false
    @Published var hasLoadedOnce = false // Track if we've loaded at least once
    @Published var isFetching = false // Track if fetch is in progress (prevents duplicate calls)
    
    private init() {
        // Firestore offline persistence is configured globally in AppDelegate.configureFirebase()
        // before any Firestore operations. No settings needed here.
    }
    
    /// Fetch all books using API (with fallback to Firestore)
    /// Uses GET /api/library API to offload heavy processing to backend
    func fetchBooks(useCache: Bool = true, query: String? = nil, forceRefresh: Bool = false) async throws {
        // Prevent concurrent calls
        let currentlyFetching = await MainActor.run { isFetching }
        if currentlyFetching {
            logger.info("📚 Fetch already in progress, skipping duplicate call")
            return
        }
        
        // Only skip if books are loaded AND not forcing refresh AND no query
        // Check on main thread to ensure we have the latest state
        let bookCount = await MainActor.run { self.books.count }
        let hasBooks = bookCount > 0
        if hasBooks && !forceRefresh && query == nil {
            logger.info("📚 Books already loaded (\(bookCount) books), skipping fetch")
            return
        }
        
        await MainActor.run {
            isFetching = true
            isLoading = true
        }
        
        defer {
            Task { @MainActor in
                isFetching = false
                isLoading = false
                hasLoadedOnce = true
            }
        }
        
        // Direct Firestore query (no API)
        // Try cache first if requested
        if useCache {
            do {
                let cachedSnapshot = try await db.collection("books")
                    .getDocuments(source: .cache)
                
                if !cachedSnapshot.documents.isEmpty {
                    logger.info("📚 Loaded \(cachedSnapshot.documents.count) books from cache")
                    await processBooks(from: cachedSnapshot)
                    
                    // Start preloading images immediately (from cached data)
                    Task.detached(priority: .userInitiated) {
                        await ImagePreloader.shared.preloadImages(for: await MainActor.run { self.books })
                    }
                    
                    // Still fetch from server in background to update cache
                    Task.detached(priority: .background) { [weak self] in
                        guard let self = self else { return }
                        do {
                            let serverSnapshot = try await self.db.collection("books")
                                .getDocuments(source: .server)
                            await self.processBooks(from: serverSnapshot)
                            self.logger.info("📚 Updated books from server")
                            
                            // Preload images for updated books
                            await ImagePreloader.shared.preloadImages(for: await MainActor.run { self.books })
                        } catch {
                            self.logger.error("⚠️ Failed to update from server: \(error.localizedDescription)")
                        }
                    }
                    return
                }
            } catch {
                logger.warning("⚠️ No cache available, fetching from server")
            }
        }
        
        // Fetch from server (or cache if offline)
        let snapshot = try await db.collection("books").getDocuments()
        await processBooks(from: snapshot)
        logger.info("📚 Loaded \(snapshot.documents.count) books from \(useCache ? "server" : "cache")")
        
        // Start preloading images after fetching books
        Task.detached(priority: .userInitiated) {
            await ImagePreloader.shared.preloadImages(for: await MainActor.run { self.books })
        }
    }
    
    /// Process books from Firestore snapshot
    private func processBooks(from snapshot: QuerySnapshot) async {
        var fetchedBooks: [Book] = []
        
        for document in snapshot.documents {
            let data = document.data()
            
            // Parse enrichedData if present
            var enrichedData: EnrichedBookData? = nil
            if let enrichedDataDict = data["enrichedData"] as? [String: Any] {
                enrichedData = EnrichedBookData(data: enrichedDataDict)
            }
            
            let book = Book(
                id: data["id"] as? String ?? document.documentID,
                title: data["title"] as? String ?? "Unknown",
                author: data["author"] as? String ?? "Unknown",
                description: data["description"] as? String,
                coverUrl: data["coverUrl"] as? String,
                publisher: data["publisher"] as? String,
                publishedDate: data["publishedDate"] as? String,
                isbn10: data["isbn10"] as? String ?? document.documentID,
                isbn13: data["isbn13"] as? String,
                chapters: (data["chapters"] as? [[String: Any]])?.compactMap { chapterData in
                    guard let id = chapterData["id"] as? String,
                          let title = chapterData["title"] as? String,
                          let audioUrl = chapterData["audioUrl"] as? String,
                          let jsonUrl = chapterData["jsonUrl"] as? String,
                          let order = chapterData["order"] as? Int else {
                        return nil
                    }
                    let duration = chapterData["duration"] as? Double
                    return Chapter(id: id, title: title, audioUrl: audioUrl, jsonUrl: jsonUrl, order: order, duration: duration)
                } ?? [],
                createdAt: (data["createdAt"] as? Timestamp)?.dateValue(),
                hasDescription: data["hasDescription"] as? Bool,
                descriptionAudioUrl: data["descriptionAudioUrl"] as? String,
                descriptionJsonUrl: data["descriptionJsonUrl"] as? String,
                enrichedData: enrichedData
            )
            
            fetchedBooks.append(book)
        }
        
        await MainActor.run {
            books = fetchedBooks.sorted { $0.title < $1.title }
        }
    }
    
    /// Get book by ISBN (fresh from Firebase, no caching)
    func getBook(isbn: String) async throws -> Book? {
        logger.info("📥 Loading book from Firebase for \(isbn)")
        
        let docRef = db.collection("books").document(isbn)
        let document = try await docRef.getDocument()
        
        guard document.exists, let data = document.data() else {
            return nil
        }
        
        // Parse enrichedData if present
        var enrichedData: EnrichedBookData? = nil
        if let enrichedDataDict = data["enrichedData"] as? [String: Any] {
            enrichedData = EnrichedBookData(data: enrichedDataDict)
        }
        
        let book = Book(
            id: data["id"] as? String ?? document.documentID,
            title: data["title"] as? String ?? "Unknown",
            author: data["author"] as? String ?? "Unknown",
            description: data["description"] as? String,
            coverUrl: data["coverUrl"] as? String,
            publisher: data["publisher"] as? String,
            publishedDate: data["publishedDate"] as? String,
            isbn10: data["isbn10"] as? String ?? document.documentID,
            isbn13: data["isbn13"] as? String,
            chapters: (data["chapters"] as? [[String: Any]])?.compactMap { chapterData in
                guard let id = chapterData["id"] as? String,
                      let title = chapterData["title"] as? String,
                      let audioUrl = chapterData["audioUrl"] as? String,
                      let jsonUrl = chapterData["jsonUrl"] as? String,
                      let order = chapterData["order"] as? Int else {
                    return nil
                }
                let duration = chapterData["duration"] as? Double
                return Chapter(id: id, title: title, audioUrl: audioUrl, jsonUrl: jsonUrl, order: order, duration: duration)
            } ?? [],
            createdAt: (data["createdAt"] as? Timestamp)?.dateValue(),
            hasDescription: data["hasDescription"] as? Bool,
            descriptionAudioUrl: data["descriptionAudioUrl"] as? String,
            descriptionJsonUrl: data["descriptionJsonUrl"] as? String,
            enrichedData: enrichedData
        )
        
        logger.info("✅ Loaded book from Firebase: \(book.title)")
        
        return book
    }
    
    /// Filter books by genre search terms
    /// Searches across book titles, authors, and descriptions
    func filterBooksByGenre(_ searchTerms: [String]) {
        Task { @MainActor [self] in
            guard !books.isEmpty else {
                filteredBooks = []
                return
            }
            
            let lowercasedTerms = searchTerms.map { $0.lowercased() }
            
            filteredBooks = books.filter { book in
                // Search in title
                let titleMatch = lowercasedTerms.contains { term in
                    book.title.lowercased().contains(term)
                }
                
                // Search in author
                let authorMatch = lowercasedTerms.contains { term in
                    book.author.lowercased().contains(term)
                }
                
                // Search in description
                let descriptionMatch: Bool
                if let description = book.description?.lowercased() {
                    descriptionMatch = lowercasedTerms.contains { term in
                        description.contains(term)
                    }
                } else {
                    descriptionMatch = false
                }
                
                // Search in enriched genres
                let genreMatch: Bool
                if let genres = book.enrichedData?.genres {
                    let lowercasedGenres = genres.map { $0.lowercased() }
                    genreMatch = lowercasedTerms.contains { term in
                        lowercasedGenres.contains { genre in
                            genre.contains(term) || term.contains(genre)
                        }
                    }
                } else {
                    genreMatch = false
                }
                
                return titleMatch || authorMatch || descriptionMatch || genreMatch
            }
            
            logger.info("🔍 Filtered \(filteredBooks.count) books for genre terms: \(searchTerms.joined(separator: ", "))")
        }
    }
    
    /// Clear genre filter and reset filtered books
    func clearGenreFilter() {
        Task { @MainActor [self] in
            selectedGenre = nil
            filteredBooks = []
            logger.info("🔍 Cleared genre filter")
        }
    }
    
}

// MARK: - Errors

enum BookServiceError: LocalizedError {
    case bookNotFound
    case firestoreError
    
    var errorDescription: String? {
        switch self {
        case .bookNotFound:
            return "Book not found"
        case .firestoreError:
            return "Firestore error"
        }
    }
}

