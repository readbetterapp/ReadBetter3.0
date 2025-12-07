//
//  Book.swift
//  ReadBetterApp3.0
//
//  Created by Ermin on 30/11/2025.
//

import Foundation

struct Book: Identifiable {
    let id: String // ISBN-10
    let title: String
    let author: String
    let description: String?
    let coverUrl: String?
    let publisher: String?
    let publishedDate: String?
    let isbn10: String
    let isbn13: String?
    var chapters: [Chapter]
    let createdAt: Date?
    
    // Description summary fields (for books with description.json + chapters.mp3)
    let hasDescription: Bool?
    let descriptionAudioUrl: String?
    let descriptionJsonUrl: String?
    
    init(
        id: String,
        title: String,
        author: String,
        description: String? = nil,
        coverUrl: String? = nil,
        publisher: String? = nil,
        publishedDate: String? = nil,
        isbn10: String,
        isbn13: String? = nil,
        chapters: [Chapter] = [],
        createdAt: Date? = nil,
        hasDescription: Bool? = nil,
        descriptionAudioUrl: String? = nil,
        descriptionJsonUrl: String? = nil
    ) {
        self.id = id
        self.title = title
        self.author = author
        self.description = description
        self.coverUrl = coverUrl
        self.publisher = publisher
        self.publishedDate = publishedDate
        self.isbn10 = isbn10
        self.isbn13 = isbn13
        self.chapters = chapters
        self.createdAt = createdAt
        self.hasDescription = hasDescription
        self.descriptionAudioUrl = descriptionAudioUrl
        self.descriptionJsonUrl = descriptionJsonUrl
    }
}

struct Chapter: Identifiable, Codable {
    let id: String
    let title: String
    let audioUrl: String
    let jsonUrl: String
    let order: Int
    
    init(id: String, title: String, audioUrl: String, jsonUrl: String, order: Int) {
        self.id = id
        self.title = title
        self.audioUrl = audioUrl
        self.jsonUrl = jsonUrl
        self.order = order
    }
}

