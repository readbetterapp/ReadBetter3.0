//
//  ReadingSession.swift
//  ReadBetterApp3.0
//
//  Model for tracking daily reading activity.
//  Used to calculate streaks, weekly stats, and future analytics.
//

import Foundation
import FirebaseFirestore

struct ReadingSession: Codable, Identifiable {
    var id: String { date }
    
    // Date identifier (YYYY-MM-DD format)
    let date: String
    
    // Daily activity metrics
    var listenedSeconds: Double
    var chaptersCompleted: Int
    var booksRead: [String]  // Book IDs read that day
    
    // Timestamps
    var lastUpdated: Date
    
    // MARK: - Computed Properties
    
    /// Returns true if this session counts toward a streak (5+ minutes)
    var countsTowardStreak: Bool {
        listenedSeconds >= 300 // 5 minutes minimum
    }
    
    /// Formatted listening time (e.g., "1h 23m" or "45m")
    var listenedTimeFormatted: String {
        let hours = Int(listenedSeconds) / 3600
        let minutes = (Int(listenedSeconds) % 3600) / 60
        
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else if minutes > 0 {
            return "\(minutes)m"
        } else {
            return "<1m"
        }
    }
    
    // MARK: - Initialization
    
    init(
        date: String,
        listenedSeconds: Double = 0,
        chaptersCompleted: Int = 0,
        booksRead: [String] = [],
        lastUpdated: Date = Date()
    ) {
        self.date = date
        self.listenedSeconds = listenedSeconds
        self.chaptersCompleted = chaptersCompleted
        self.booksRead = booksRead
        self.lastUpdated = lastUpdated
    }
    
    /// Create a session for today
    static func today() -> ReadingSession {
        ReadingSession(date: Self.dateString(for: Date()))
    }
    
    /// Get date string in YYYY-MM-DD format
    static func dateString(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone.current
        return formatter.string(from: date)
    }
    
    /// Parse date string back to Date
    static func date(from string: String) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone.current
        return formatter.date(from: string)
    }
    
    // MARK: - Firestore Conversion
    
    init?(id: String, data: [String: Any]) {
        self.date = id
        self.listenedSeconds = data["listenedSeconds"] as? Double ?? 0
        self.chaptersCompleted = data["chaptersCompleted"] as? Int ?? 0
        self.booksRead = data["booksRead"] as? [String] ?? []
        
        if let timestamp = data["lastUpdated"] as? Timestamp {
            self.lastUpdated = timestamp.dateValue()
        } else {
            self.lastUpdated = Date()
        }
    }
    
    func asFirestoreData() -> [String: Any] {
        return [
            "listenedSeconds": listenedSeconds,
            "chaptersCompleted": chaptersCompleted,
            "booksRead": booksRead,
            "lastUpdated": Timestamp(date: lastUpdated)
        ]
    }
    
    // MARK: - Mutation Methods
    
    mutating func addListeningTime(_ seconds: Double, bookId: String) {
        listenedSeconds += seconds
        if !booksRead.contains(bookId) {
            booksRead.append(bookId)
        }
        lastUpdated = Date()
    }
    
    mutating func addChapterCompleted(bookId: String) {
        chaptersCompleted += 1
        if !booksRead.contains(bookId) {
            booksRead.append(bookId)
        }
        lastUpdated = Date()
    }
}
