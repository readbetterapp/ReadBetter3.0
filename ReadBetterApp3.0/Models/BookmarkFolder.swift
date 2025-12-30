//
//  BookmarkFolder.swift
//  ReadBetterApp3.0
//
//  User-owned folder/tag for organizing bookmarks.
//  Stored in Firestore under users/{uid}/folders/{folderId}
//

import Foundation
import FirebaseFirestore

struct BookmarkFolder: Identifiable, Hashable {
    let id: String
    var name: String
    var sortOrder: Int?
    var createdAt: Date?
    var updatedAt: Date?
    
    init(id: String,
         name: String,
         sortOrder: Int? = nil,
         createdAt: Date? = nil,
         updatedAt: Date? = nil) {
        self.id = id
        self.name = name
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
    
    init(id: String, data: [String: Any]) {
        self.id = id
        self.name = data["name"] as? String ?? "Untitled"
        self.sortOrder = data["sortOrder"] as? Int
        
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
            "name": name,
            "updatedAt": FieldValue.serverTimestamp()
        ]
        if creating {
            out["createdAt"] = FieldValue.serverTimestamp()
        }
        if let sortOrder {
            out["sortOrder"] = sortOrder
        }
        return out
    }
}




