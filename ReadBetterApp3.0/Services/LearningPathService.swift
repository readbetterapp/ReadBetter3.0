//
//  LearningPathService.swift
//  ReadBetterApp3.0
//
//  Service for managing user Learning Paths.
//  Handles API calls to generate paths and Firestore operations.
//

import Foundation
import Combine
import FirebaseFirestore
import FirebaseAuth
import OSLog

@MainActor
final class LearningPathService: ObservableObject {
    static let shared = LearningPathService()
    
    // MARK: - Published State
    
    @Published private(set) var currentPath: LearningPath?
    @Published private(set) var userPreferences: UserPreferences?
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var isGenerating: Bool = false
    @Published private(set) var error: String?
    
    /// Set to true to request showing the onboarding flow
    @Published var shouldShowOnboarding: Bool = false
    
    // MARK: - Private Properties
    
    private let db = Firestore.firestore()
    private let logger = Logger(subsystem: "com.readbetter", category: "LearningPathService")
    
    /// Base URL for Firebase Functions
    private let functionsBaseUrl = "https://australia-southeast1-read-better-app.cloudfunctions.net"
    
    private var pathListener: ListenerRegistration?
    private var preferencesListener: ListenerRegistration?
    private var currentUserId: String?
    
    // MARK: - Initialization
    
    private init() {}
    
    // MARK: - User Binding
    
    /// Call this when a user logs in to start listening to their data
    func setUser(uid: String?) {
        // Clean up existing listeners
        pathListener?.remove()
        preferencesListener?.remove()
        pathListener = nil
        preferencesListener = nil
        
        currentUserId = uid
        currentPath = nil
        userPreferences = nil
        
        guard let uid = uid else {
            logger.info("📚 LearningPathService: User logged out, cleared data")
            return
        }
        
        logger.info("📚 LearningPathService: Setting up listeners for user \(uid)")
        
        // Listen to learning path
        setupPathListener(uid: uid)
        
        // Listen to preferences
        setupPreferencesListener(uid: uid)
    }
    
    // MARK: - Path Operations
    
    /// Check if user has a learning path
    var hasLearningPath: Bool {
        return currentPath != nil && !(currentPath?.books.isEmpty ?? true)
    }
    
    /// Check if user has completed onboarding
    var hasCompletedOnboarding: Bool {
        return userPreferences?.onboardingComplete ?? false
    }
    
    /// Generate a new learning path for the user
    func generateLearningPath(
        startingBookIsbn: String,
        genres: [String] = [],
        booksPerMonth: Int = 2
    ) async throws {
        guard let userId = currentUserId else {
            throw LearningPathError.notLoggedIn
        }
        
        isGenerating = true
        error = nil
        
        defer {
            isGenerating = false
        }
        
        logger.info("🎯 Generating learning path starting with \(startingBookIsbn)")
        
        // Call the Firebase Function
        let url = URL(string: "\(functionsBaseUrl)/generateLearningPath")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "userId": userId,
            "startingBookIsbn": startingBookIsbn,
            "preferences": [
                "genres": genres,
                "booksPerMonth": booksPerMonth
            ]
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw LearningPathError.networkError("Invalid response")
        }
        
        if httpResponse.statusCode != 200 {
            if let errorResponse = try? JSONDecoder().decode(ErrorResponse.self, from: data) {
                throw LearningPathError.serverError(errorResponse.error)
            }
            throw LearningPathError.serverError("Server returned status \(httpResponse.statusCode)")
        }
        
        // Parse response
        let result = try JSONDecoder().decode(GeneratePathResponse.self, from: data)
        
        if result.success {
            logger.info("✅ Learning path generated with \(result.learningPath?.totalBooks ?? 0) books")
            // The Firestore listener will update currentPath automatically
        } else {
            throw LearningPathError.serverError("Failed to generate path")
        }
    }
    
    /// Update book status in the learning path
    func updateBookStatus(isbn: String, status: PathBookStatus) async throws {
        guard let userId = currentUserId else {
            throw LearningPathError.notLoggedIn
        }
        
        logger.info("📝 Updating book \(isbn) status to \(status.rawValue)")
        
        // Call the Firebase Function
        let url = URL(string: "\(functionsBaseUrl)/updateLearningPathProgress")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "userId": userId,
            "isbn": isbn,
            "status": status.rawValue
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            if let errorResponse = try? JSONDecoder().decode(ErrorResponse.self, from: data) {
                throw LearningPathError.serverError(errorResponse.error)
            }
            throw LearningPathError.networkError("Failed to update status")
        }
        
        logger.info("✅ Book status updated")
    }
    
    /// Mark a book as completed and advance to the next
    func markBookCompleted(isbn: String) async throws {
        try await updateBookStatus(isbn: isbn, status: .completed)
    }
    
    /// Clear the current learning path
    func clearLearningPath() async throws {
        guard let userId = currentUserId else {
            throw LearningPathError.notLoggedIn
        }
        
        try await db.collection("users").document(userId)
            .collection("learningPath").document("current").delete()
        
        logger.info("🗑️ Learning path cleared")
    }
    
    // MARK: - Preferences Operations
    
    /// Save user preferences
    func savePreferences(_ preferences: UserPreferences) async throws {
        guard let userId = currentUserId else {
            throw LearningPathError.notLoggedIn
        }
        
        var updatedPreferences = preferences
        updatedPreferences.updatedAt = Date()
        
        try await db.collection("users").document(userId)
            .collection("preferences").document("reading")
            .setData(updatedPreferences.asFirestoreData(), merge: true)
        
        logger.info("✅ Preferences saved")
    }
    
    /// Mark onboarding as complete
    func completeOnboarding(genres: [String], booksPerMonth: Int) async throws {
        let preferences = UserPreferences(
            genres: genres,
            booksPerMonth: booksPerMonth,
            onboardingComplete: true,
            createdAt: Date(),
            updatedAt: Date()
        )
        
        try await savePreferences(preferences)
    }
    
    // MARK: - Phantom Books
    
    /// Fetch a phantom book by ISBN
    func getPhantomBook(isbn: String) async throws -> PhantomBook? {
        let doc = try await db.collection("phantomBooks").document(isbn).getDocument()
        
        guard doc.exists, let data = doc.data() else {
            return nil
        }
        
        return PhantomBook(id: isbn, data: data)
    }
    
    /// Fetch all phantom books in the current learning path
    func getPathPhantomBooks() async -> [PhantomBook] {
        guard let path = currentPath else { return [] }
        
        let unavailableIsbns = path.books.filter { !$0.available }.map { $0.isbn }
        var phantomBooks: [PhantomBook] = []
        
        for isbn in unavailableIsbns {
            if let phantom = try? await getPhantomBook(isbn: isbn) {
                phantomBooks.append(phantom)
            }
        }
        
        return phantomBooks
    }
    
    // MARK: - Private Methods
    
    private func setupPathListener(uid: String) {
        pathListener = db.collection("users").document(uid)
            .collection("learningPath").document("current")
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self = self else { return }
                
                if let error = error {
                    self.logger.error("❌ Path listener error: \(error.localizedDescription)")
                    return
                }
                
                guard let data = snapshot?.data() else {
                    self.currentPath = nil
                    self.logger.info("📚 No learning path found")
                    return
                }
                
                self.currentPath = LearningPath(data: data)
                self.logger.info("📚 Learning path loaded: \(self.currentPath?.books.count ?? 0) books")
            }
    }
    
    private func setupPreferencesListener(uid: String) {
        preferencesListener = db.collection("users").document(uid)
            .collection("preferences").document("reading")
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self = self else { return }
                
                if let error = error {
                    self.logger.error("❌ Preferences listener error: \(error.localizedDescription)")
                    return
                }
                
                guard let data = snapshot?.data() else {
                    self.userPreferences = nil
                    return
                }
                
                self.userPreferences = UserPreferences(data: data)
                self.logger.info("📚 Preferences loaded: onboardingComplete=\(self.userPreferences?.onboardingComplete ?? false)")
            }
    }
    
    // MARK: - Cleanup
    
    deinit {
        pathListener?.remove()
        preferencesListener?.remove()
    }
}

// MARK: - Error Types

enum LearningPathError: LocalizedError {
    case notLoggedIn
    case networkError(String)
    case serverError(String)
    case invalidData
    
    var errorDescription: String? {
        switch self {
        case .notLoggedIn:
            return "You must be logged in to access learning paths"
        case .networkError(let message):
            return "Network error: \(message)"
        case .serverError(let message):
            return "Server error: \(message)"
        case .invalidData:
            return "Invalid data received"
        }
    }
}

// MARK: - Response Types

private struct GeneratePathResponse: Codable {
    let success: Bool
    let userId: String?
    let learningPath: GeneratedPath?
    
    struct GeneratedPath: Codable {
        let totalBooks: Int
        let availableBooks: Int
        let unavailableBooks: Int
    }
}

private struct ErrorResponse: Codable {
    let success: Bool
    let error: String
}

