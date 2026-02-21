//
//  EnrichedBookData.swift
//  ReadBetterApp3.0
//
//  AI-generated metadata for books, including series info, genres, and themes.
//  Added to books/{isbn} document as an enrichedData field.
//

import Foundation
import FirebaseFirestore

// MARK: - Series Information

struct SeriesInfo: Codable, Equatable {
    /// Name of the series (e.g., "The Hunger Games")
    let name: String
    
    /// Position of this book in the series (1-indexed)
    let position: Int
    
    /// Total number of books in the series
    let totalBooks: Int
    
    /// ISBNs of all books in the series, in order
    let allIsbns: [String]
    
    init(name: String, position: Int, totalBooks: Int, allIsbns: [String]) {
        self.name = name
        self.position = position
        self.totalBooks = totalBooks
        self.allIsbns = allIsbns
    }
    
    init?(data: [String: Any]) {
        guard let name = data["name"] as? String,
              let position = data["position"] as? Int,
              let totalBooks = data["totalBooks"] as? Int else {
            return nil
        }
        
        self.name = name
        self.position = position
        self.totalBooks = totalBooks
        self.allIsbns = data["allIsbns"] as? [String] ?? []
    }
    
    func asFirestoreData() -> [String: Any] {
        return [
            "name": name,
            "position": position,
            "totalBooks": totalBooks,
            "allIsbns": allIsbns
        ]
    }
    
    /// Returns true if there are more books after this one in the series
    var hasNextBook: Bool {
        return position < totalBooks
    }
    
    /// Returns the ISBN of the next book in the series, if available
    var nextBookIsbn: String? {
        guard hasNextBook, allIsbns.count > position else { return nil }
        return allIsbns[position] // position is 1-indexed, array is 0-indexed
    }
    
    /// Returns ISBNs of remaining books in the series after this one
    var remainingBookIsbns: [String] {
        guard position < allIsbns.count else { return [] }
        return Array(allIsbns.dropFirst(position))
    }
}

// MARK: - Enriched Book Data

struct EnrichedBookData: Codable {
    /// Series information, if this book is part of a series
    let series: SeriesInfo?
    
    /// Genre tags (e.g., ["dystopian", "young-adult", "fiction"])
    let genres: [String]
    
    /// Theme tags (e.g., ["survival", "rebellion", "love"])
    let themes: [String]
    
    /// ISBNs of related/similar books
    let relatedIsbns: [String]
    
    /// When this enrichment was generated
    let enrichedAt: Date
    
    init(
        series: SeriesInfo? = nil,
        genres: [String] = [],
        themes: [String] = [],
        relatedIsbns: [String] = [],
        enrichedAt: Date = Date()
    ) {
        self.series = series
        self.genres = genres
        self.themes = themes
        self.relatedIsbns = relatedIsbns
        self.enrichedAt = enrichedAt
    }
    
    init?(data: [String: Any]) {
        // Parse series if present
        if let seriesData = data["series"] as? [String: Any] {
            self.series = SeriesInfo(data: seriesData)
        } else {
            self.series = nil
        }
        
        self.genres = data["genres"] as? [String] ?? []
        self.themes = data["themes"] as? [String] ?? []
        self.relatedIsbns = data["relatedIsbns"] as? [String] ?? []
        
        if let ts = data["enrichedAt"] as? Timestamp {
            self.enrichedAt = ts.dateValue()
        } else {
            self.enrichedAt = Date()
        }
    }
    
    func asFirestoreData() -> [String: Any] {
        var data: [String: Any] = [
            "genres": genres,
            "themes": themes,
            "relatedIsbns": relatedIsbns,
            "enrichedAt": Timestamp(date: enrichedAt)
        ]
        
        if let series = series {
            data["series"] = series.asFirestoreData()
        }
        
        return data
    }
    
    /// Returns true if this book is part of a series
    var isPartOfSeries: Bool {
        return series != nil
    }
    
    /// Returns a human-readable series position string (e.g., "Book 2 of 4")
    var seriesPositionText: String? {
        guard let series = series else { return nil }
        return "Book \(series.position) of \(series.totalBooks)"
    }
}


