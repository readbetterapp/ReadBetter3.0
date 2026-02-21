//
//  QuoteService.swift
//  ReadBetterApp3.0
//
//  Service for fetching daily inspirational quotes from OpenAI API
//  Caches quotes for 24 hours to minimize API calls
//

import Foundation
import Combine

@MainActor
final class QuoteService: ObservableObject {
    @Published private(set) var currentQuote: DailyQuote?
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var lastError: String?
    
    private let userDefaults = UserDefaults.standard
    private let quoteKey = "cached_daily_quote"
    private let quoteDateKey = "cached_quote_date"
    private let quoteAuthorKey = "cached_quote_author"
    private let cacheVersionKey = "quote_cache_version"
    private let currentCacheVersion = 3  // Increment this to force cache clear
    
    // OpenAI API Configuration
    private let openAIAPIKey: String
    private let apiEndpoint = "https://api.openai.com/v1/chat/completions"
    
    init(apiKey: String = "") {
        self.openAIAPIKey = apiKey
        
        // Check cache version - clear if outdated
        let savedVersion = userDefaults.integer(forKey: cacheVersionKey)
        if savedVersion < currentCacheVersion {
            print("📖 QuoteService: Cache version outdated (\(savedVersion) < \(currentCacheVersion)), clearing cache")
            clearCacheSync()
            userDefaults.set(currentCacheVersion, forKey: cacheVersionKey)
        }
        
        loadCachedQuote()
    }
    
    private func clearCacheSync() {
        userDefaults.removeObject(forKey: quoteKey)
        userDefaults.removeObject(forKey: quoteAuthorKey)
        userDefaults.removeObject(forKey: quoteDateKey)
    }
    
    // MARK: - Public Methods
    
    func fetchDailyQuote() async {
        // Check if we have a valid cached quote from today
        if let cachedQuote = currentQuote, isCachedQuoteValid() {
            print("📖 QuoteService: Using cached quote from today (cached date: \(cachedQuote.date))")
            return
        }
        
        // Clear old cache if it exists but is invalid
        if currentQuote != nil {
            print("📖 QuoteService: Cache expired, clearing old quote")
            clearCache()
        }
        
        isLoading = true
        lastError = nil
        
        // If no API key, show error
        if openAIAPIKey.isEmpty {
            lastError = "OpenAI API key not configured"
            print("❌ QuoteService: No API key configured")
            isLoading = false
            return
        }
        
        do {
            print("🔄 QuoteService: Fetching new quote from OpenAI...")
            let quote = try await fetchFromOpenAI()
            currentQuote = quote
            cacheQuote(quote)
            print("✅ QuoteService: Successfully fetched and cached quote: \"\(quote.text)\" - \(quote.author)")
            isLoading = false
        } catch {
            lastError = error.localizedDescription
            print("❌ QuoteService: Failed to fetch quote - \(error)")
            print("❌ QuoteService: Error details - \(String(describing: error))")
            isLoading = false
        }
    }
    
    // MARK: - Private Methods
    
    private func loadCachedQuote() {
        guard let quoteText = userDefaults.string(forKey: quoteKey),
              let author = userDefaults.string(forKey: quoteAuthorKey),
              let dateString = userDefaults.string(forKey: quoteDateKey),
              let date = ISO8601DateFormatter().date(from: dateString) else {
            print("📖 QuoteService: No cached quote found")
            return
        }
        
        currentQuote = DailyQuote(text: quoteText, author: author, date: date)
        print("📖 QuoteService: Loaded cached quote from \(dateString)")
    }
    
    private func isCachedQuoteValid() -> Bool {
        guard let quote = currentQuote else { return false }
        
        let calendar = Calendar.current
        let now = Date()
        
        // Check if quote is from today
        let isToday = calendar.isDate(quote.date, inSameDayAs: now)
        
        // Also check the seed matches (extra validation)
        let cachedSeed = calendar.dateComponents([.year, .month, .day], from: quote.date)
        let todaySeed = calendar.dateComponents([.year, .month, .day], from: now)
        
        let seedMatches = cachedSeed.year == todaySeed.year &&
                          cachedSeed.month == todaySeed.month &&
                          cachedSeed.day == todaySeed.day
        
        print("📖 QuoteService: Cache validation - isToday: \(isToday), seedMatches: \(seedMatches), quoteDate: \(quote.date), now: \(now)")
        
        return isToday && seedMatches
    }
    
    private func cacheQuote(_ quote: DailyQuote) {
        userDefaults.set(quote.text, forKey: quoteKey)
        userDefaults.set(quote.author, forKey: quoteAuthorKey)
        userDefaults.set(ISO8601DateFormatter().string(from: quote.date), forKey: quoteDateKey)
        print("📖 QuoteService: Cached quote for date: \(ISO8601DateFormatter().string(from: quote.date))")
    }
    
    private func clearCache() {
        userDefaults.removeObject(forKey: quoteKey)
        userDefaults.removeObject(forKey: quoteAuthorKey)
        userDefaults.removeObject(forKey: quoteDateKey)
        currentQuote = nil
    }
    
    private func getDailySeed() -> Int {
        // Use current date as seed so all users get the same quote on the same day
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month, .day], from: Date())
        return (components.year ?? 2025) * 10000 + (components.month ?? 1) * 100 + (components.day ?? 1)
    }
    
    private func fetchFromOpenAI() async throws -> DailyQuote {
        guard let url = URL(string: apiEndpoint) else {
            throw QuoteError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(openAIAPIKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let dailySeed = getDailySeed()
        
        // List of famous authors to rotate through based on the day
        let authors = [
            "Ernest Hemingway", "Mark Twain", "Oscar Wilde", "Jane Austen",
            "Charles Dickens", "Virginia Woolf", "Jorge Luis Borges", "Franz Kafka",
            "Leo Tolstoy", "Gabriel García Márquez", "Fyodor Dostoevsky", "Marcel Proust",
            "James Baldwin", "Toni Morrison", "Ralph Waldo Emerson", "Henry David Thoreau",
            "C.S. Lewis", "J.R.R. Tolkien", "Ray Bradbury", "Isaac Asimov",
            "Ursula K. Le Guin", "Margaret Atwood", "Neil Gaiman", "Stephen King",
            "Haruki Murakami", "Umberto Eco", "Albert Camus", "Simone de Beauvoir",
            "Maya Angelou", "Walt Whitman", "Emily Dickinson"
        ]
        let authorIndex = dailySeed % authors.count
        let featuredAuthor = authors[authorIndex]
        
        let prompt = """
        Give me a real, famous quote about reading, books, or literature from \(featuredAuthor).
        It must be an actual quote they said or wrote, not made up.
        Format your response as JSON with two fields: "quote" and "author".
        Keep the quote under 150 characters.
        Example: {"quote": "A reader lives a thousand lives before he dies.", "author": "George R.R. Martin"}
        """
        
        let requestBody: [String: Any] = [
            "model": "gpt-3.5-turbo",
            "messages": [
                ["role": "system", "content": "You are a helpful assistant that provides real, verified quotes about reading and books from famous authors. Only provide actual quotes, never make them up."],
                ["role": "user", "content": prompt]
            ],
            "temperature": 0.3,  // Slight variation while staying accurate
            "max_tokens": 150
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        print("📡 QuoteService: Making API request to OpenAI...")
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            print("❌ QuoteService: Invalid response type")
            throw QuoteError.invalidResponse
        }
        
        print("📡 QuoteService: Got response with status code: \(httpResponse.statusCode)")
        
        guard httpResponse.statusCode == 200 else {
            if let errorBody = String(data: data, encoding: .utf8) {
                print("❌ QuoteService: API error body: \(errorBody)")
            }
            throw QuoteError.apiError(statusCode: httpResponse.statusCode)
        }
        
        let openAIResponse = try JSONDecoder().decode(OpenAIResponse.self, from: data)
        
        guard let content = openAIResponse.choices.first?.message.content else {
            print("❌ QuoteService: No content in response")
            throw QuoteError.noContent
        }
        
        print("📡 QuoteService: Got content from OpenAI: \(content)")
        
        // Parse the JSON response from the content
        let quoteData = try parseQuoteFromContent(content)
        
        return DailyQuote(text: quoteData.quote, author: quoteData.author, date: Date())
    }
    
    private func parseQuoteFromContent(_ content: String) throws -> (quote: String, author: String) {
        // Try to parse as JSON first
        if let jsonData = content.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: String],
           let quote = json["quote"],
           let author = json["author"] {
            return (quote, author)
        }
        
        // Fallback: try to extract from text
        // Look for patterns like "quote" - Author or "quote" by Author
        let patterns = [
            #""([^"]+)"\s*-\s*([^"\n]+)"#,
            #""([^"]+)"\s+by\s+([^"\n]+)"#,
            #"\"([^\"]+)\"\s*-\s*([^\"\n]+)"#
        ]
        
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: content, range: NSRange(content.startIndex..., in: content)) {
                if let quoteRange = Range(match.range(at: 1), in: content),
                   let authorRange = Range(match.range(at: 2), in: content) {
                    let quote = String(content[quoteRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                    let author = String(content[authorRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                    return (quote, author)
                }
            }
        }
        
        throw QuoteError.parseError
    }
}

// MARK: - Models

struct DailyQuote {
    let text: String
    let author: String
    let date: Date
}

enum QuoteError: LocalizedError {
    case invalidURL
    case invalidResponse
    case apiError(statusCode: Int)
    case noContent
    case parseError
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid API URL"
        case .invalidResponse:
            return "Invalid response from server"
        case .apiError(let statusCode):
            return "API error with status code: \(statusCode)"
        case .noContent:
            return "No content in response"
        case .parseError:
            return "Failed to parse quote"
        }
    }
}

// OpenAI API Response Models
private struct OpenAIResponse: Codable {
    let choices: [Choice]
    
    struct Choice: Codable {
        let message: Message
    }
    
    struct Message: Codable {
        let content: String
    }
}

