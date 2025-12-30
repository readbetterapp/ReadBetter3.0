//
//  ReadingProgress.swift
//  ReadBetterApp3.0
//
//  Model for tracking user's reading progress through books.
//  Supports hybrid local+cloud sync for offline reading.
//

import Foundation
import FirebaseFirestore

struct ChapterProgress: Codable, Hashable {
    var listenedSeconds: Double
    var durationSeconds: Double
    
    var fractionComplete: Double {
        guard durationSeconds > 0 else { return 0 }
        return min(1.0, max(0, listenedSeconds / durationSeconds))
    }
}

struct ReadingProgress: Codable, Identifiable {
    var id: String { bookId }
    
    // Book identification
    let bookId: String
    var bookTitle: String
    var bookAuthor: String
    var bookCoverUrl: String?
    
    // Current position
    var currentChapterId: String
    var currentChapterNumber: Int
    var currentChapterTitle: String
    var currentTime: Double // seconds into current chapter
    var chapterDuration: Double // total duration of current chapter
    
    // Overall progress
    var totalBookDuration: Double // sum of all chapter durations
    var completedChapterIds: [String] // chapters fully listened to
    var chapterProgressById: [String: ChapterProgress] // per-chapter progress (for progress bars + accurate totals)
    var totalChapters: Int
    
    // Timestamps
    var lastReadAt: Date
    var createdAt: Date
    var updatedAt: Date
    
    // Computed properties
    var percentComplete: Double {
        let listened = totalListenedSeconds
        let total = totalDurationSecondsForCalc
        guard total > 0 else { return 0 }
        return min(100, (listened / total) * 100)
    }
    
    var timeRemainingSeconds: Double {
        let total = totalDurationSecondsForCalc
        guard total > 0 else { return 0 }
        return max(0, total - totalListenedSeconds)
    }
    
    var timeRemainingFormatted: String {
        let remaining = timeRemainingSeconds
        let hours = Int(remaining) / 3600
        let minutes = (Int(remaining) % 3600) / 60
        
        if hours > 0 {
            return "\(hours)h \(minutes)m left"
        } else if minutes > 0 {
            return "\(minutes)m left"
        } else {
            return "Almost done"
        }
    }
    
    var currentChapterProgress: Double {
        guard chapterDuration > 0 else { return 0 }
        return min(1.0, currentTime / chapterDuration)
    }
    
    private var totalDurationSecondsForCalc: Double {
        // If we have durations for all chapters, use exact sum.
        let knownDurations = chapterProgressById.values.map { $0.durationSeconds }.filter { $0 > 0 }
        if totalChapters > 0 && knownDurations.count >= totalChapters {
            return knownDurations.reduce(0, +)
        }
        // Otherwise fall back to stored estimate (what we had before), or sum known durations if that's better.
        if totalBookDuration > 0 {
            return max(totalBookDuration, knownDurations.reduce(0, +))
        }
        return knownDurations.reduce(0, +)
    }
    
    private var totalListenedSeconds: Double {
        // Prefer per-chapter listenedSeconds when available.
        var listened = chapterProgressById.values.reduce(0) { partial, cp in
            partial + min(max(0, cp.listenedSeconds), max(0, cp.durationSeconds))
        }
        
        // If we have no per-chapter entries yet, fall back to currentTime + completed chapters approximation.
        if listened <= 0 {
            var completedTime: Double = 0
            if totalChapters > 0 && completedChapterIds.count > 0 && totalBookDuration > 0 {
                let avgChapterDuration = totalBookDuration / Double(totalChapters)
                completedTime = Double(completedChapterIds.count) * avgChapterDuration
            }
            listened = completedTime + currentTime
        }
        
        return listened
    }
    
    // MARK: - Initialization
    
    init(
        bookId: String,
        bookTitle: String,
        bookAuthor: String,
        bookCoverUrl: String? = nil,
        currentChapterId: String,
        currentChapterNumber: Int,
        currentChapterTitle: String,
        currentTime: Double,
        chapterDuration: Double,
        totalBookDuration: Double,
        completedChapterIds: [String] = [],
        chapterProgressById: [String: ChapterProgress] = [:],
        totalChapters: Int,
        lastReadAt: Date = Date(),
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.bookId = bookId
        self.bookTitle = bookTitle
        self.bookAuthor = bookAuthor
        self.bookCoverUrl = bookCoverUrl
        self.currentChapterId = currentChapterId
        self.currentChapterNumber = currentChapterNumber
        self.currentChapterTitle = currentChapterTitle
        self.currentTime = currentTime
        self.chapterDuration = chapterDuration
        self.totalBookDuration = totalBookDuration
        self.completedChapterIds = completedChapterIds
        self.chapterProgressById = chapterProgressById
        self.totalChapters = totalChapters
        self.lastReadAt = lastReadAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
    
    // MARK: - Firestore Conversion
    
    init?(id: String, data: [String: Any]) {
        guard let bookTitle = data["bookTitle"] as? String,
              let bookAuthor = data["bookAuthor"] as? String,
              let currentChapterId = data["currentChapterId"] as? String,
              let currentChapterNumber = data["currentChapterNumber"] as? Int,
              let currentChapterTitle = data["currentChapterTitle"] as? String,
              let currentTime = data["currentTime"] as? Double,
              let chapterDuration = data["chapterDuration"] as? Double,
              let totalBookDuration = data["totalBookDuration"] as? Double,
              let totalChapters = data["totalChapters"] as? Int
        else {
            return nil
        }
        
        self.bookId = id
        self.bookTitle = bookTitle
        self.bookAuthor = bookAuthor
        self.bookCoverUrl = data["bookCoverUrl"] as? String
        self.currentChapterId = currentChapterId
        self.currentChapterNumber = currentChapterNumber
        self.currentChapterTitle = currentChapterTitle
        self.currentTime = currentTime
        self.chapterDuration = chapterDuration
        self.totalBookDuration = totalBookDuration
        self.completedChapterIds = data["completedChapterIds"] as? [String] ?? []
        
        // Per-chapter progress
        var chapterProgress: [String: ChapterProgress] = [:]
        if let rawMap = data["chapterProgressById"] as? [String: Any] {
            for (chapterId, value) in rawMap {
                if let dict = value as? [String: Any] {
                    let listenedSeconds = dict["listenedSeconds"] as? Double ?? 0
                    let durationSeconds = dict["durationSeconds"] as? Double ?? 0
                    chapterProgress[chapterId] = ChapterProgress(listenedSeconds: listenedSeconds, durationSeconds: durationSeconds)
                }
            }
        }
        self.chapterProgressById = chapterProgress
        self.totalChapters = totalChapters
        
        if let timestamp = data["lastReadAt"] as? Timestamp {
            self.lastReadAt = timestamp.dateValue()
        } else {
            self.lastReadAt = Date()
        }
        
        if let timestamp = data["createdAt"] as? Timestamp {
            self.createdAt = timestamp.dateValue()
        } else {
            self.createdAt = Date()
        }
        
        if let timestamp = data["updatedAt"] as? Timestamp {
            self.updatedAt = timestamp.dateValue()
        } else {
            self.updatedAt = Date()
        }
    }
    
    func asFirestoreData() -> [String: Any] {
        let chapterMap: [String: Any] = Dictionary(uniqueKeysWithValues: chapterProgressById.map { (key, value) in
            (key, [
                "listenedSeconds": value.listenedSeconds,
                "durationSeconds": value.durationSeconds
            ])
        })
        return [
            "bookTitle": bookTitle,
            "bookAuthor": bookAuthor,
            "bookCoverUrl": bookCoverUrl as Any,
            "currentChapterId": currentChapterId,
            "currentChapterNumber": currentChapterNumber,
            "currentChapterTitle": currentChapterTitle,
            "currentTime": currentTime,
            "chapterDuration": chapterDuration,
            "totalBookDuration": totalBookDuration,
            "completedChapterIds": completedChapterIds,
            "chapterProgressById": chapterMap,
            "totalChapters": totalChapters,
            "lastReadAt": Timestamp(date: lastReadAt),
            "createdAt": Timestamp(date: createdAt),
            "updatedAt": FieldValue.serverTimestamp()
        ]
    }
    
    // MARK: - Update Methods
    
    mutating func updatePosition(chapterId: String, chapterNumber: Int, chapterTitle: String, time: Double, duration: Double) {
        // If we moved to a new chapter, mark the previous as complete if we were near the end
        if currentChapterId != chapterId && currentTime > chapterDuration * 0.95 {
            if !completedChapterIds.contains(currentChapterId) {
                completedChapterIds.append(currentChapterId)
            }
        }
        
        // Update per-chapter progress (keep max listened so scrub backward doesn't reduce progress)
        let existing = chapterProgressById[chapterId]
        let nextListened = max(existing?.listenedSeconds ?? 0, time)
        chapterProgressById[chapterId] = ChapterProgress(listenedSeconds: nextListened, durationSeconds: duration)
        
        self.currentChapterId = chapterId
        self.currentChapterNumber = chapterNumber
        self.currentChapterTitle = chapterTitle
        self.currentTime = time
        self.chapterDuration = duration
        self.lastReadAt = Date()
        self.updatedAt = Date()
    }
    
    mutating func markChapterComplete(_ chapterId: String) {
        if !completedChapterIds.contains(chapterId) {
            completedChapterIds.append(chapterId)
            updatedAt = Date()
        }
        
        // If we know the duration, mark listenedSeconds to full duration.
        if var cp = chapterProgressById[chapterId], cp.durationSeconds > 0 {
            cp.listenedSeconds = cp.durationSeconds
            chapterProgressById[chapterId] = cp
        }
    }
}

