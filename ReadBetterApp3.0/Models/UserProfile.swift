//
//  UserProfile.swift
//  ReadBetterApp3.0
//
//  Stores user-facing profile data (display name, email, etc.)
//  Kept in Firestore under users/{uid}
//

import Foundation
import FirebaseFirestore

struct UserProfile: Identifiable {
    var id: String { uid }
    
    let uid: String
    var displayName: String
    var email: String?
    var photoURL: String?
    var isAnonymous: Bool
    var providers: [String]
    
    var createdAt: Date?
    var updatedAt: Date?
    
    init(uid: String,
         displayName: String,
         email: String? = nil,
         photoURL: String? = nil,
         isAnonymous: Bool,
         providers: [String],
         createdAt: Date? = nil,
         updatedAt: Date? = nil) {
        self.uid = uid
        self.displayName = displayName
        self.email = email
        self.photoURL = photoURL
        self.isAnonymous = isAnonymous
        self.providers = providers
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
    
    init(uid: String, data: [String: Any]) {
        self.uid = uid
        self.displayName = data["displayName"] as? String ?? UserProfile.defaultDisplayName(isAnonymous: false)
        self.email = data["email"] as? String
        self.photoURL = data["photoURL"] as? String
        self.isAnonymous = data["isAnonymous"] as? Bool ?? false
        self.providers = data["providers"] as? [String] ?? []
        
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
            "uid": uid,
            "displayName": displayName,
            "isAnonymous": isAnonymous,
            "providers": providers,
            "updatedAt": FieldValue.serverTimestamp()
        ]
        
        if creating {
            out["createdAt"] = FieldValue.serverTimestamp()
        }
        if let email { out["email"] = email }
        if let photoURL { out["photoURL"] = photoURL }
        
        return out
    }
    
    static func defaultDisplayName(isAnonymous: Bool) -> String {
        isAnonymous ? "Guest" : "Reader"
    }
}


