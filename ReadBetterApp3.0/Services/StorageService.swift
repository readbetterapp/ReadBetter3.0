//
//  StorageService.swift
//  ReadBetterApp3.0
//
//  Created by Ermin on 30/11/2025.
//

import Foundation

/// Service for building GCS URLs
/// Note: Chapters are now discovered by Cloud Functions and stored in Firestore
/// This service only provides URL construction utilities
class StorageService {
    static let shared = StorageService()
    
    private let bucketName = "myapp-readeraudio"
    private let baseURL = "https://storage.googleapis.com"
    
    private init() {}
    
    /// Get public URL for a file in GCS
    func getPublicURL(for path: String) -> String {
        return "\(baseURL)/\(bucketName)/\(path)"
    }
    
    /// Get cover image URL for a book
    func getCoverURL(isbn: String) -> String {
        return getPublicURL(for: "\(isbn)/cover.jpg")
    }
    
    /// Get chapter audio URL
    func getChapterAudioURL(isbn: String, chapterName: String) -> String {
        return getPublicURL(for: "\(isbn)/\(chapterName).m4a")
    }
    
    /// Get chapter JSON URL
    func getChapterJSONURL(isbn: String, chapterName: String) -> String {
        return getPublicURL(for: "\(isbn)/\(chapterName).json")
    }
}

