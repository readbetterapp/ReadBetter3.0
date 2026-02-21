//
//  ExplainableTermsService.swift
//  ReadBetterApp3.0
//
//  Service for fetching and caching explainable terms from Firestore.
//  Automatically triggers Cloud Function processing if terms don't exist.
//
//  v2.0: TEXT-BASED MATCHING - terms are matched by text at runtime,
//  eliminating index mismatch bugs between Cloud Function and iOS.
//

import Foundation
import FirebaseFirestore
import OSLog

/// Service for managing explainable terms - singleton pattern
final class ExplainableTermsService {
    static let shared = ExplainableTermsService()
    
    private let db = Firestore.firestore()
    private let logger = Logger(subsystem: "ReadBetterApp", category: "ExplainableTerms")
    
    // Cloud Function URL for processing
    private let processChapterURL = "https://processexplainableterms-iiyc76erma-ts.a.run.app"
    
    // In-memory cache: [chapterId: ChapterExplainableTerms]
    private var cache: [String: ChapterExplainableTerms] = [:]
    
    // Word index lookup cache: [chapterId: [wordIndex: ExplainableTerm]]
    // This is built at runtime by matching term TEXT against indexedWords
    private var wordIndexCache: [String: [Int: ExplainableTerm]] = [:]
    
    // Track chapters currently being processed to avoid duplicate requests
    private var processingChapters: Set<String> = []
    
    // Thread-safe access
    private let cacheQueue = DispatchQueue(label: "com.readbetter.explainableterms.cache")
    
    private init() {}
    
    // MARK: - Public API
    
    /// Fetch explainable terms for a chapter
    /// Returns cached data if available, otherwise fetches from Firestore
    /// If terms don't exist, triggers Cloud Function to process them in background
    @MainActor
    func getTerms(for bookId: String, chapterId: String) async -> ChapterExplainableTerms {
        // Check cache first
        if let cached = cacheQueue.sync(execute: { cache[chapterId] }) {
            return cached
        }
        
        // Fetch from Firestore
        do {
            let docRef = db.collection("explainableTerms")
                .document(bookId)
                .collection("chapters")
                .document(chapterId)
            
            let document = try await docRef.getDocument()
            
            guard document.exists, let data = document.data() else {
                logger.info("📚 No explainable terms found for \(chapterId) - triggering auto-processing")
                // Trigger processing in background (fire-and-forget)
                triggerProcessing(for: bookId, chapterId: chapterId)
                return .empty
            }
            
            let terms = parseTermsFromFirestore(data)
            
            // Cache the terms (but NOT the word index lookup - that's built per-chapter with indexedWords)
            cacheQueue.sync {
                cache[chapterId] = terms
            }
            
            logger.info("📚 Loaded \(terms.terms.count) explainable terms for \(chapterId)")
            return terms
            
        } catch {
            logger.error("❌ Error fetching explainable terms: \(error.localizedDescription)")
            return .empty
        }
    }
    
    /// Build word index lookup by matching term TEXT against the chapter's indexed words
    /// This must be called AFTER loading terms and AFTER KaraokeEngine has indexed words
    /// 
    /// - Parameters:
    ///   - chapterId: The chapter ID
    ///   - indexedWords: The chapter's word array from KaraokeEngine
    /// - Returns: Set of word indices that have explainable terms
    func buildLookup(for chapterId: String, indexedWords: [IndexedWord]) -> Set<Int> {
        guard let terms = cacheQueue.sync(execute: { cache[chapterId] }) else {
            logger.warning("⚠️ No cached terms for \(chapterId), cannot build lookup")
            return []
        }
        
        // Build the lookup using text matching
        let lookup = terms.buildWordIndexLookup(indexedWords: indexedWords)
        
        // Cache the lookup
        cacheQueue.sync {
            wordIndexCache[chapterId] = lookup
        }
        
        return Set(lookup.keys)
    }
    
    /// Trigger Cloud Function to process explainable terms for a chapter
    /// This is fire-and-forget - the terms will be available on next chapter load
    private func triggerProcessing(for bookId: String, chapterId: String) {
        // Avoid duplicate processing requests
        let processingKey = "\(bookId)/\(chapterId)"
        let alreadyProcessing = cacheQueue.sync { processingChapters.contains(processingKey) }
        
        if alreadyProcessing {
            logger.info("⏳ Already processing \(chapterId), skipping duplicate request")
            return
        }
        
        cacheQueue.sync { processingChapters.insert(processingKey) }
        
        // Fire-and-forget request to Cloud Function
        Task.detached { [weak self] in
            guard let self = self else { return }
            
            let urlString = "\(self.processChapterURL)/\(bookId)/\(chapterId)"
            guard let url = URL(string: urlString) else {
                self.logger.error("❌ Invalid URL for processing: \(urlString)")
                return
            }
            
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.timeoutInterval = 300 // 5 minutes for processing
            
            do {
                self.logger.info("🚀 Triggering explainable terms processing for \(chapterId)")
                let (data, response) = try await URLSession.shared.data(for: request)
                
                if let httpResponse = response as? HTTPURLResponse {
                    if httpResponse.statusCode == 200 {
                        self.logger.info("✅ Successfully triggered processing for \(chapterId)")
                        // Try to parse response to log term count
                        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                           let termCount = json["termCount"] as? Int {
                            self.logger.info("📚 Processed \(termCount) terms for \(chapterId)")
                        }
                    } else {
                        self.logger.warning("⚠️ Processing returned status \(httpResponse.statusCode) for \(chapterId)")
                    }
                }
            } catch {
                self.logger.error("❌ Failed to trigger processing for \(chapterId): \(error.localizedDescription)")
            }
            
            // Remove from processing set
            self.cacheQueue.sync { self.processingChapters.remove(processingKey) }
        }
    }
    
    /// Get the explainable term at a specific word index (O(1) lookup)
    func getTerm(at wordIndex: Int, chapterId: String) -> ExplainableTerm? {
        return cacheQueue.sync { wordIndexCache[chapterId]?[wordIndex] }
    }
    
    /// Check if a word index has an explainable term
    func hasExplainableTerm(at wordIndex: Int, chapterId: String) -> Bool {
        return cacheQueue.sync { wordIndexCache[chapterId]?[wordIndex] != nil }
    }
    
    /// Get all word indices that have explainable terms for a chapter
    /// NOTE: This returns cached lookup. Call buildLookup() first!
    func getExplainableWordIndices(for chapterId: String) -> Set<Int> {
        return cacheQueue.sync {
            guard let lookup = wordIndexCache[chapterId] else {
                return []
            }
            return Set(lookup.keys)
        }
    }
    
    /// Preload terms for a chapter (call during chapter loading)
    func preloadTerms(for bookId: String, chapterId: String) {
        Task { @MainActor in
            _ = await getTerms(for: bookId, chapterId: chapterId)
        }
    }
    
    /// Clear cache for a specific chapter
    func clearCache(for chapterId: String) {
        cacheQueue.sync {
            cache.removeValue(forKey: chapterId)
            wordIndexCache.removeValue(forKey: chapterId)
        }
    }
    
    /// Clear all caches
    func clearAllCaches() {
        cacheQueue.sync {
            cache.removeAll()
            wordIndexCache.removeAll()
        }
    }
    
    // MARK: - Private Helpers
    
    private func parseTermsFromFirestore(_ data: [String: Any]) -> ChapterExplainableTerms {
        let chapterId = data["chapterId"] as? String ?? ""
        let bookId = data["bookId"] as? String ?? ""
        let version = data["version"] as? String ?? "1.0"
        
        // Parse processedAt timestamp
        let processedAt: Date
        if let timestamp = data["processedAt"] as? Timestamp {
            processedAt = timestamp.dateValue()
        } else {
            processedAt = Date()
        }
        
        // Parse terms array
        var terms: [ExplainableTerm] = []
        if let termsArray = data["terms"] as? [[String: Any]] {
            for termData in termsArray {
                if let term = parseTermFromFirestore(termData) {
                    terms.append(term)
                }
            }
        }
        
        return ChapterExplainableTerms(
            chapterId: chapterId,
            bookId: bookId,
            terms: terms,
            processedAt: processedAt,
            version: version
        )
    }
    
    private func parseTermFromFirestore(_ data: [String: Any]) -> ExplainableTerm? {
        guard let id = data["id"] as? String,
              let term = data["term"] as? String,
              let typeString = data["type"] as? String,
              let shortExplanation = data["shortExplanation"] as? String else {
            return nil
        }
        
        guard let type = ExplainableType(rawValue: typeString) else {
            return nil
        }
        
        // v2.0: Indices are optional (legacy support)
        let startWordIndex = data["startWordIndex"] as? Int
        let endWordIndex = data["endWordIndex"] as? Int
        
        return ExplainableTerm(
            id: id,
            term: term,
            type: type,
            shortExplanation: shortExplanation,
            startWordIndex: startWordIndex,
            endWordIndex: endWordIndex
        )
    }
}
