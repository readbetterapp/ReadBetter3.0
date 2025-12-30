//
//  Bookmark.swift
//  ReadBetterApp3.0
//
//  User-owned bookmark pointing to a specific sentence (and time) in the reader.
//  Stored in Firestore under users/{uid}/bookmarks/{bookmarkId}
//

import Foundation
import FirebaseFirestore

struct Bookmark: Identifiable, Hashable {
    let id: String
    
    let bookId: String
    let chapterId: String
    let chapterNumber: Int?
    let isDescription: Bool
    
    let sentenceIndex: Int
    let startTime: Double
    let text: String
    
    var folderIds: [String]
    var starred: Bool
    
    var createdAt: Date?
    var updatedAt: Date?
    
    static func makeId(bookId: String, chapterId: String, sentenceIndex: Int) -> String {
        // Keep IDs Firestore-safe and deterministic.
        let safeBook = bookId.replacingOccurrences(of: "/", with: "_")
        let safeChapter = chapterId.replacingOccurrences(of: "/", with: "_")
        return "\(safeBook)_\(safeChapter)_s\(sentenceIndex)"
    }
    
    init(id: String,
         bookId: String,
         chapterId: String,
         chapterNumber: Int?,
         isDescription: Bool,
         sentenceIndex: Int,
         startTime: Double,
         text: String,
         folderIds: [String] = [],
         starred: Bool = false,
         createdAt: Date? = nil,
         updatedAt: Date? = nil) {
        self.id = id
        self.bookId = bookId
        self.chapterId = chapterId
        self.chapterNumber = chapterNumber
        self.isDescription = isDescription
        self.sentenceIndex = sentenceIndex
        self.startTime = startTime
        self.text = text
        self.folderIds = folderIds
        self.starred = starred
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
    
    init(id: String, data: [String: Any]) {
        self.id = id
        self.bookId = data["bookId"] as? String ?? ""
        self.chapterId = data["chapterId"] as? String ?? ""
        self.chapterNumber = data["chapterNumber"] as? Int
        self.isDescription = data["isDescription"] as? Bool ?? false
        self.sentenceIndex = data["sentenceIndex"] as? Int ?? 0
        self.startTime = data["startTime"] as? Double ?? 0
        self.text = data["text"] as? String ?? ""
        self.folderIds = data["folderIds"] as? [String] ?? []
        self.starred = data["starred"] as? Bool ?? false
        
        if let ts = data["createdAt"] as? Timestamp {
            self.createdAt = ts.dateValue()
        } else {
            self.createdAt = nil
        }
        
        if let ts = data["updatedAt"] as? Timestamp {
            self.updatedAt = ts.dateValue()
        } else {
            self.updatedAt = nil
        }
    }
    
    func asFirestoreData(creating: Bool) -> [String: Any] {
        var out: [String: Any] = [
            "bookId": bookId,
            "chapterId": chapterId,
            "sentenceIndex": sentenceIndex,
            "startTime": startTime,
            "text": text,
            "folderIds": folderIds,
            "starred": starred,
            "isDescription": isDescription,
            "updatedAt": FieldValue.serverTimestamp()
        ]
        if let chapterNumber {
            out["chapterNumber"] = chapterNumber
        }
        if creating {
            out["createdAt"] = FieldValue.serverTimestamp()
        }
        return out
    }
}




