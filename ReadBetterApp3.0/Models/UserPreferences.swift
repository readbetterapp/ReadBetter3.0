//
//  UserPreferences.swift
//  ReadBetterApp3.0
//
//  User onboarding preferences for Learning Path recommendations.
//  Stored in Firestore under users/{uid}/preferences
//

import Foundation
import FirebaseFirestore

struct UserPreferences: Codable, Equatable {
    // Genre preferences selected during onboarding
    var genres: [String]
    
    // How many books the user wants to read per month (1, 2, 3, or 4+)
    var booksPerMonth: Int
    
    // Whether the user has completed the onboarding flow
    var onboardingComplete: Bool
    
    // Timestamps
    var createdAt: Date
    var updatedAt: Date
    
    // MARK: - Initialization
    
    init(
        genres: [String] = [],
        booksPerMonth: Int = 2,
        onboardingComplete: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.genres = genres
        self.booksPerMonth = booksPerMonth
        self.onboardingComplete = onboardingComplete
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
    
    // MARK: - Firestore Conversion
    
    init?(data: [String: Any]) {
        self.genres = data["genres"] as? [String] ?? []
        self.booksPerMonth = data["booksPerMonth"] as? Int ?? 2
        self.onboardingComplete = data["onboardingComplete"] as? Bool ?? false
        
        if let ts = data["createdAt"] as? Timestamp {
            self.createdAt = ts.dateValue()
        } else {
            self.createdAt = Date()
        }
        
        if let ts = data["updatedAt"] as? Timestamp {
            self.updatedAt = ts.dateValue()
        } else {
            self.updatedAt = Date()
        }
    }
    
    func asFirestoreData() -> [String: Any] {
        return [
            "genres": genres,
            "booksPerMonth": booksPerMonth,
            "onboardingComplete": onboardingComplete,
            "createdAt": Timestamp(date: createdAt),
            "updatedAt": FieldValue.serverTimestamp()
        ]
    }
}

// MARK: - Available Genres

extension UserPreferences {
    /// Available genre options for onboarding selection
    static let availableGenres: [GenreOption] = [
        GenreOption(id: "fiction", name: "Fiction & Storytelling", icon: "book.fill"),
        GenreOption(id: "self-help", name: "Self-Improvement", icon: "person.fill.checkmark"),
        GenreOption(id: "business", name: "Business & Money", icon: "chart.line.uptrend.xyaxis"),
        GenreOption(id: "biography", name: "Biography & Memoir", icon: "person.text.rectangle"),
        GenreOption(id: "history", name: "History", icon: "clock.fill"),
        GenreOption(id: "philosophy", name: "Philosophy", icon: "lightbulb.fill"),
        GenreOption(id: "science", name: "Science & Technology", icon: "atom"),
        GenreOption(id: "health", name: "Health & Wellness", icon: "heart.fill"),
        GenreOption(id: "romance", name: "Romance", icon: "heart.text.square.fill"),
        GenreOption(id: "mystery", name: "Mystery & Thriller", icon: "magnifyingglass"),
        GenreOption(id: "fantasy", name: "Fantasy & Sci-Fi", icon: "sparkles"),
        GenreOption(id: "psychology", name: "Psychology", icon: "brain.head.profile")
    ]
}

struct GenreOption: Identifiable {
    let id: String
    let name: String
    let icon: String
}

