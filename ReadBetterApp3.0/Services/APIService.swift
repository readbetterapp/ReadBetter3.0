//
//  APIService.swift
//  ReadBetterApp3.0
//
//  Service for calling backend APIs (Firebase Cloud Functions)
//

import Foundation
import OSLog

class APIService {
    static let shared = APIService()
    
    // Base URL for Firebase Functions
    // Format: https://{region}-{project-id}.cloudfunctions.net
    // Update this after deploying functions to get the actual URL
    private let baseURL = "https://australia-southeast1-read-better-app.cloudfunctions.net"
    
    private let session: URLSession
    private let logger = Logger(subsystem: "com.readbetter", category: "APIService")
    
    private init() {
        let config = URLSessionConfiguration.default
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.urlCache = nil
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        self.session = URLSession(configuration: config)
    }
    
    // MARK: - Library API
    
    /// Fetch books from library API with pagination
    /// GET /api/library?page=1&pageSize=20&query=...
    func fetchLibrary(page: Int = 1, pageSize: Int = 20, query: String? = nil) async throws -> LibraryResponse {
        var components = URLComponents(string: "\(baseURL)/getLibrary")!
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "page", value: "\(page)"),
            URLQueryItem(name: "pageSize", value: "\(pageSize)")
        ]
        
        if let query = query, !query.isEmpty {
            queryItems.append(URLQueryItem(name: "query", value: query))
        }
        
        components.queryItems = queryItems
        
        guard let url = components.url else {
            logger.error("❌ Failed to create URL from components")
            throw APIError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        logger.info("📡 Calling GET \(url.absoluteString)")
        logger.debug("📡 Request headers: \(String(describing: request.allHTTPHeaderFields))")
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            logger.error("❌ Invalid response type")
            throw APIError.invalidResponse
        }
        
        logger.info("📡 HTTP Status: \(httpResponse.statusCode)")
        logger.debug("📡 Response headers: \(String(describing: httpResponse.allHeaderFields))")
        
        guard httpResponse.statusCode == 200 else {
            logger.error("❌ HTTP Error \(httpResponse.statusCode)")
            if let dataString = String(data: data, encoding: .utf8) {
                logger.error("❌ Response body: \(String(dataString.prefix(500)))")
            }
            throw APIError.httpError(httpResponse.statusCode)
        }
        
        let decoder = JSONDecoder()
        let libraryResponse = try decoder.decode(LibraryResponse.self, from: data)
        
        logger.info("✅ Received \(libraryResponse.books.count) books")
        
        return libraryResponse
    }
    
    // MARK: - Chapter Index API
    
    /// Get precomputed chapter index
    /// GET /api/books/:bookId/chapters/:chapterId/index
    func getChapterIndex(bookId: String, chapterId: String) async throws -> ChapterIndexResponse {
        let urlString = "\(baseURL)/getChapterIndex/\(bookId)/\(chapterId)"
        
        logger.info("📡 Building URL: \(urlString)")
        
        guard let url = URL(string: urlString) else {
            logger.error("❌ Failed to create URL from string: \(urlString)")
            throw APIError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        logger.info("📡 Calling GET \(url.absoluteString)")
        logger.debug("📡 Request headers: \(String(describing: request.allHTTPHeaderFields))")
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            logger.error("❌ Invalid response type")
            throw APIError.invalidResponse
        }
        
        logger.info("📡 HTTP Status: \(httpResponse.statusCode)")
        logger.debug("📡 Response headers: \(String(describing: httpResponse.allHeaderFields))")
        
        guard httpResponse.statusCode == 200 else {
            logger.error("❌ HTTP Error \(httpResponse.statusCode)")
            if let dataString = String(data: data, encoding: .utf8) {
                logger.error("❌ Response body: \(String(dataString.prefix(500)))")
            }
            throw APIError.httpError(httpResponse.statusCode)
        }
        
        let decoder = JSONDecoder()
        let indexResponse = try decoder.decode(ChapterIndexResponse.self, from: data)
        
        logger.info("✅ Received chapter index with \(indexResponse.words.count) words, \(indexResponse.sentences.count) sentences")
        
        return indexResponse
    }
    
    /// Trigger chapter index processing (optional - usually auto-triggers on first GET)
    /// POST /api/books/:bookId/chapters/:chapterId/prep
    func prepChapterIndex(bookId: String, chapterId: String) async throws -> PrepChapterIndexResponse {
        let urlString = "\(baseURL)/prepChapterIndex/\(bookId)/\(chapterId)"
        
        guard let url = URL(string: urlString) else {
            throw APIError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        print("📡 APIService: Calling POST \(url.absoluteString)")
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            print("❌ APIService: HTTP \(httpResponse.statusCode)")
            throw APIError.httpError(httpResponse.statusCode)
        }
        
        let decoder = JSONDecoder()
        let prepResponse = try decoder.decode(PrepChapterIndexResponse.self, from: data)
        
        print("✅ APIService: Chapter index processing triggered")
        
        return prepResponse
    }
}

// MARK: - Response Models

struct LibraryResponse: Codable {
    let books: [LibraryBook]
    let pagination: Pagination
}

struct LibraryBook: Codable {
    let id: String
    let title: String
    let author: String
    let coverUrl: String?
    let shortDescription: String?
    let chapterCount: Int
    let hasDescription: Bool
}

struct Pagination: Codable {
    let page: Int
    let pageSize: Int
    let total: Int
    let hasMore: Bool
}

struct ChapterIndexResponse: Codable {
    let fullText: String
    let sentences: [ChapterSentence]
    let words: [ChapterWord]
    let timeBuckets: [String: [Int]]? // Optional time buckets
}

struct ChapterSentence: Codable {
    let text: String
    let wordIndices: [Int] // Original JSON indices
    let startTime: Double
    let endTime: Double
}

struct ChapterWord: Codable {
    let text: String
    let start: Double
    let end: Double
    let index: Int // Original JSON index
    let hasLineBreak: Bool
}

struct PrepChapterIndexResponse: Codable {
    let success: Bool
    let message: String
    let wordCount: Int?
    let sentenceCount: Int?
}

// MARK: - Errors

enum APIError: LocalizedError {
    case invalidURL
    case invalidResponse
    case httpError(Int)
    case decodingError(Error)
    case networkError(Error)
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid API URL"
        case .invalidResponse:
            return "Invalid API response"
        case .httpError(let code):
            return "HTTP error \(code)"
        case .decodingError(let error):
            return "Failed to decode response: \(error.localizedDescription)"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        }
    }
}

