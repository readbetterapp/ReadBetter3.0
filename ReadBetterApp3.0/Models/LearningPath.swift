//
//  LearningPath.swift
//  ReadBetterApp3.0
//
//  User's personalized reading path (5 books).
//  Stored in Firestore under users/{uid}/learningPath
//

import Foundation
import FirebaseFirestore

// MARK: - Path Book Status

enum PathBookStatus: String, Codable {
    case reading = "reading"       // Currently reading this book
    case upcoming = "upcoming"     // Next in the queue
    case completed = "completed"   // Finished reading
}

// MARK: - Learning Path Book

struct LearningPathBook: Identifiable, Codable {
    var id: String { isbn }
    
    /// ISBN of the book
    let isbn: String
    
    /// Book title
    let title: String
    
    /// Book author
    let author: String
    
    /// Cover image URL
    let coverUrl: String?
    
    /// Position in the learning path (1-5)
    let position: Int
    
    /// Current status of the book in the path
    var status: PathBookStatus
    
    /// Whether the book is available in the catalogue (false = phantom book)
    let available: Bool
    
    /// AI-generated reason for recommendation
    let reason: String
    
    /// Series information if this book is part of a series
    let seriesInfo: SeriesInfo?
    
    init(
        isbn: String,
        title: String,
        author: String,
        coverUrl: String? = nil,
        position: Int,
        status: PathBookStatus = .upcoming,
        available: Bool,
        reason: String,
        seriesInfo: SeriesInfo? = nil
    ) {
        self.isbn = isbn
        self.title = title
        self.author = author
        self.coverUrl = coverUrl
        self.position = position
        self.status = status
        self.available = available
        self.reason = reason
        self.seriesInfo = seriesInfo
    }
    
    init?(data: [String: Any]) {
        guard let isbn = data["isbn"] as? String,
              let title = data["title"] as? String,
              let author = data["author"] as? String,
              let position = data["position"] as? Int,
              let statusString = data["status"] as? String,
              let status = PathBookStatus(rawValue: statusString),
              let available = data["available"] as? Bool,
              let reason = data["reason"] as? String else {
            return nil
        }
        
        self.isbn = isbn
        self.title = title
        self.author = author
        self.coverUrl = data["coverUrl"] as? String
        self.position = position
        self.status = status
        self.available = available
        self.reason = reason
        
        if let seriesData = data["seriesInfo"] as? [String: Any] {
            self.seriesInfo = SeriesInfo(data: seriesData)
        } else {
            self.seriesInfo = nil
        }
    }
    
    func asFirestoreData() -> [String: Any] {
        var data: [String: Any] = [
            "isbn": isbn,
            "title": title,
            "author": author,
            "position": position,
            "status": status.rawValue,
            "available": available,
            "reason": reason
        ]
        
        if let coverUrl = coverUrl {
            data["coverUrl"] = coverUrl
        }
        
        if let seriesInfo = seriesInfo {
            data["seriesInfo"] = seriesInfo.asFirestoreData()
        }
        
        return data
    }
    
    /// Returns availability badge text
    var availabilityText: String? {
        if available {
            return nil
        }
        return "Coming Soon"
    }
    
    /// Returns true if this is a series book
    var isSeriesBook: Bool {
        return seriesInfo != nil
    }
}

// MARK: - Learning Path

struct LearningPath: Codable {
    /// The books in this learning path (ordered by position)
    var books: [LearningPathBook]
    
    /// When this path was created
    let createdAt: Date
    
    /// The ISBN of the book the user chose to start with
    let startingBookIsbn: String
    
    init(
        books: [LearningPathBook],
        createdAt: Date = Date(),
        startingBookIsbn: String
    ) {
        self.books = books.sorted { $0.position < $1.position }
        self.createdAt = createdAt
        self.startingBookIsbn = startingBookIsbn
    }
    
    init?(data: [String: Any]) {
        guard let booksData = data["books"] as? [[String: Any]],
              let startingBookIsbn = data["startingBookIsbn"] as? String else {
            return nil
        }
        
        self.books = booksData.compactMap { LearningPathBook(data: $0) }
            .sorted { $0.position < $1.position }
        self.startingBookIsbn = startingBookIsbn
        
        if let ts = data["createdAt"] as? Timestamp {
            self.createdAt = ts.dateValue()
        } else {
            self.createdAt = Date()
        }
    }
    
    func asFirestoreData() -> [String: Any] {
        return [
            "books": books.map { $0.asFirestoreData() },
            "createdAt": Timestamp(date: createdAt),
            "startingBookIsbn": startingBookIsbn
        ]
    }
    
    // MARK: - Computed Properties
    
    /// Returns the book currently being read
    var currentBook: LearningPathBook? {
        return books.first { $0.status == .reading }
    }
    
    /// Returns the next upcoming book
    var nextBook: LearningPathBook? {
        return books.first { $0.status == .upcoming }
    }
    
    /// Returns all completed books
    var completedBooks: [LearningPathBook] {
        return books.filter { $0.status == .completed }
    }
    
    /// Returns all upcoming books
    var upcomingBooks: [LearningPathBook] {
        return books.filter { $0.status == .upcoming }
    }
    
    /// Returns total number of books in the path
    var totalBooks: Int {
        return books.count
    }
    
    /// Returns number of completed books
    var completedCount: Int {
        return completedBooks.count
    }
    
    /// Returns progress as a percentage (0-100)
    var progressPercentage: Double {
        guard totalBooks > 0 else { return 0 }
        return Double(completedCount) / Double(totalBooks) * 100
    }
    
    /// Returns number of unavailable (phantom) books
    var unavailableCount: Int {
        return books.filter { !$0.available }.count
    }
    
    /// Returns number of available books
    var availableCount: Int {
        return books.filter { $0.available }.count
    }
    
    // MARK: - Mutation Methods
    
    /// Marks a book as completed and promotes the next book to "reading"
    mutating func markBookCompleted(isbn: String) {
        guard let index = books.firstIndex(where: { $0.isbn == isbn }) else { return }
        
        // Mark current book as completed
        books[index].status = .completed
        
        // Find and promote next upcoming book to reading
        if let nextIndex = books.firstIndex(where: { $0.status == .upcoming }) {
            books[nextIndex].status = .reading
        }
    }
    
    /// Marks a book as currently reading
    mutating func startReading(isbn: String) {
        guard let index = books.firstIndex(where: { $0.isbn == isbn }) else { return }
        
        // Set any currently reading book back to upcoming
        if let currentIndex = books.firstIndex(where: { $0.status == .reading }) {
            books[currentIndex].status = .upcoming
        }
        
        // Mark the target book as reading
        books[index].status = .reading
    }
}


