//
//  PhantomBook.swift
//  ReadBetterApp3.0
//
//  Represents a book that is not yet available in the catalogue.
//  Discovered via Google Books API for Learning Path recommendations.
//  Stored in Firestore under phantomBooks/{isbn}
//

import Foundation
import FirebaseFirestore

struct PhantomBook: Identifiable, Codable {
    var id: String { isbn }
    
    /// ISBN of the book
    let isbn: String
    
    /// Book title
    let title: String
    
    /// Book author
    let author: String
    
    /// Book description/summary
    let description: String?
    
    /// Cover image URL (from Google Books)
    let coverUrl: String?
    
    /// Source of the book data (e.g., "google-books")
    let source: String
    
    /// Always false for phantom books
    let available: Bool
    
    /// Estimated availability date/year (e.g., "2026", "Q1 2026", or nil)
    let estimatedAvailability: String?
    
    /// Series information if this book is part of a series
    let series: SeriesInfo?
    
    /// Publisher name
    let publisher: String?
    
    /// Published date
    let publishedDate: String?
    
    /// When this phantom book record was created
    let createdAt: Date
    
    init(
        isbn: String,
        title: String,
        author: String,
        description: String? = nil,
        coverUrl: String? = nil,
        source: String = "google-books",
        available: Bool = false,
        estimatedAvailability: String? = nil,
        series: SeriesInfo? = nil,
        publisher: String? = nil,
        publishedDate: String? = nil,
        createdAt: Date = Date()
    ) {
        self.isbn = isbn
        self.title = title
        self.author = author
        self.description = description
        self.coverUrl = coverUrl
        self.source = source
        self.available = available
        self.estimatedAvailability = estimatedAvailability
        self.series = series
        self.publisher = publisher
        self.publishedDate = publishedDate
        self.createdAt = createdAt
    }
    
    init?(id: String, data: [String: Any]) {
        guard let title = data["title"] as? String,
              let author = data["author"] as? String else {
            return nil
        }
        
        self.isbn = id
        self.title = title
        self.author = author
        self.description = data["description"] as? String
        self.coverUrl = data["coverUrl"] as? String
        self.source = data["source"] as? String ?? "google-books"
        self.available = data["available"] as? Bool ?? false
        self.estimatedAvailability = data["estimatedAvailability"] as? String
        self.publisher = data["publisher"] as? String
        self.publishedDate = data["publishedDate"] as? String
        
        if let seriesData = data["series"] as? [String: Any] {
            self.series = SeriesInfo(data: seriesData)
        } else {
            self.series = nil
        }
        
        if let ts = data["createdAt"] as? Timestamp {
            self.createdAt = ts.dateValue()
        } else {
            self.createdAt = Date()
        }
    }
    
    func asFirestoreData() -> [String: Any] {
        var data: [String: Any] = [
            "isbn": isbn,
            "title": title,
            "author": author,
            "source": source,
            "available": available,
            "createdAt": Timestamp(date: createdAt)
        ]
        
        if let description = description {
            data["description"] = description
        }
        
        if let coverUrl = coverUrl {
            data["coverUrl"] = coverUrl
        }
        
        if let estimatedAvailability = estimatedAvailability {
            data["estimatedAvailability"] = estimatedAvailability
        }
        
        if let series = series {
            data["series"] = series.asFirestoreData()
        }
        
        if let publisher = publisher {
            data["publisher"] = publisher
        }
        
        if let publishedDate = publishedDate {
            data["publishedDate"] = publishedDate
        }
        
        return data
    }
    
    /// Returns availability badge text
    var availabilityBadge: String {
        if let estimated = estimatedAvailability {
            return "Coming \(estimated)"
        }
        return "Coming Soon"
    }
    
    /// Returns true if this book is part of a series
    var isPartOfSeries: Bool {
        return series != nil
    }
    
    /// Returns series position text (e.g., "Book 2 of 4")
    var seriesPositionText: String? {
        guard let series = series else { return nil }
        return "Book \(series.position) of \(series.totalBooks)"
    }
}

// MARK: - Conversion to Book-like display

extension PhantomBook {
    /// Converts to a display-friendly format for UI components that expect Book-like data
    var displayTitle: String {
        return title
    }
    
    var displayAuthor: String {
        return author
    }
    
    var displayCoverUrl: String? {
        return coverUrl
    }
}


