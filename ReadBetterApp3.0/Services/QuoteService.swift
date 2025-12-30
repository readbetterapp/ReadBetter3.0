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
    
    // OpenAI API Configuration
    private let openAIAPIKey: String
    private let apiEndpoint = "https://api.openai.com/v1/chat/completions"
    
    init(apiKey: String = "") {
        self.openAIAPIKey = apiKey
        loadCachedQuote()
    }
    
    // MARK: - Public Methods
    
    func fetchDailyQuote() async {
        // Check if we have a valid cached quote from today
        if let cachedQuote = currentQuote, isCachedQuoteValid() {
            print("📖 QuoteService: Using cached quote from today")
            return
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
            print("✅ QuoteService: Successfully fetched and cached quote")
            isLoading = false
        } catch {
            lastError = error.localizedDescription
            print("❌ QuoteService: Failed to fetch quote - \(error.localizedDescription)")
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
        return calendar.isDate(quote.date, inSameDayAs: now)
    }
    
    private func cacheQuote(_ quote: DailyQuote) {
        userDefaults.set(quote.text, forKey: quoteKey)
        userDefaults.set(quote.author, forKey: quoteAuthorKey)
        userDefaults.set(ISO8601DateFormatter().string(from: quote.date), forKey: quoteDateKey)
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
        let prompt = """
        Generate an inspiring quote about reading or books from a famous author or literary figure. 
        Format your response as JSON with two fields: "quote" and "author".
        Keep the quote under 150 characters.
        Use this seed for consistency: \(dailySeed)
        Example: {"quote": "A reader lives a thousand lives before he dies.", "author": "George R.R. Martin"}
        """
        
        let requestBody: [String: Any] = [
            "model": "gpt-3.5-turbo",
            "messages": [
                ["role": "system", "content": "You are a helpful assistant that provides inspiring quotes about reading and books. Always provide the same quote for the same seed value."],
                ["role": "user", "content": prompt]
            ],
            "temperature": 0.0,  // Set to 0 for deterministic output
            "max_tokens": 150,
            "seed": dailySeed  // Use seed for consistency across users
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw QuoteError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            throw QuoteError.apiError(statusCode: httpResponse.statusCode)
        }
        
        let openAIResponse = try JSONDecoder().decode(OpenAIResponse.self, from: data)
        
        guard let content = openAIResponse.choices.first?.message.content else {
            throw QuoteError.noContent
        }
        
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

