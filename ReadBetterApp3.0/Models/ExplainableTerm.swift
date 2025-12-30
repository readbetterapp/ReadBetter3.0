//
//  ExplainableTerm.swift
//  ReadBetterApp3.0
//
//  Model for explainable words - context-specific terms that readers
//  might want to look up (people, places, events, concepts).
//  
//  v2.0: TEXT-BASED MATCHING - terms are matched by text, not indices.
//  This eliminates index mismatch bugs between Cloud Function and iOS.
//

import Foundation

/// Type of explainable term
enum ExplainableType: String, Codable, CaseIterable {
    case person
    case place
    case event
    case organization
    case concept
    case work  // Books, films, artworks, etc.
    case foreign_term  // Non-English words and phrases
    
    var displayName: String {
        switch self {
        case .person: return "Person"
        case .place: return "Place"
        case .event: return "Event"
        case .organization: return "Organization"
        case .concept: return "Concept"
        case .work: return "Work"
        case .foreign_term: return "Foreign Term"
        }
    }
    
    var icon: String {
        switch self {
        case .person: return "person.fill"
        case .place: return "mappin.circle.fill"
        case .event: return "calendar.circle.fill"
        case .organization: return "building.2.fill"
        case .concept: return "lightbulb.fill"
        case .work: return "book.fill"
        case .foreign_term: return "globe"
        }
    }
}

/// A term in the text that can be explained to the reader
/// v2.0: Indices are computed at runtime by text matching, not stored
struct ExplainableTerm: Codable, Identifiable, Hashable {
    let id: String  // Unique identifier (hash of term)
    let term: String  // The actual term text (e.g., "Napoleon Bonaparte")
    let type: ExplainableType
    let shortExplanation: String  // 2-4 line explanation
    
    // Legacy fields for backwards compatibility (ignored in v2.0)
    var startWordIndex: Int?
    var endWordIndex: Int?
    
    // Computed property: number of words in the term
    var wordCount: Int {
        return term.components(separatedBy: " ").filter { !$0.isEmpty }.count
    }
    
    // Hashable conformance
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    static func == (lhs: ExplainableTerm, rhs: ExplainableTerm) -> Bool {
        return lhs.id == rhs.id
    }
}

/// Container for all explainable terms in a chapter
struct ChapterExplainableTerms: Codable {
    let chapterId: String
    let bookId: String
    let terms: [ExplainableTerm]
    let processedAt: Date
    let version: String  // For cache invalidation if we update the extraction logic
    
    /// Build a lookup dictionary by matching term TEXT against indexed words
    /// This matches ALL occurrences of each term in the chapter
    /// 
    /// - Parameter indexedWords: The chapter's word array from KaraokeEngine
    /// - Returns: Dictionary mapping word index -> ExplainableTerm
    func buildWordIndexLookup(indexedWords: [IndexedWord]) -> [Int: ExplainableTerm] {
        var lookup: [Int: ExplainableTerm] = [:]
        
        // Sort terms by word count DESCENDING so longer terms match first
        // This ensures "Third Reich" claims its indices before "Reich" alone could
        let sortedTerms = terms.sorted { $0.wordCount > $1.wordCount }
        
        for term in sortedTerms {
            // Split term into words for matching
            let termWords = term.term
                .components(separatedBy: " ")
                .map { normalizeForMatching($0) }
                .filter { !$0.isEmpty }
            
            guard !termWords.isEmpty else { continue }
            
            // Scan ALL words looking for this term (match every occurrence)
            var i = 0
            while i < indexedWords.count {
                let wordText = normalizeForMatching(indexedWords[i].text)
                
                // Check if this word matches the first word of the term
                if wordsMatch(wordText, termWords[0]) {
                    // Verify all words of multi-word term match
                    var allMatch = true
                    for (offset, termWord) in termWords.enumerated() {
                        let checkIndex = i + offset
                        guard checkIndex < indexedWords.count else { 
                            allMatch = false
                            break 
                        }
                        
                        let checkWord = normalizeForMatching(indexedWords[checkIndex].text)
                        if !wordsMatch(checkWord, termWord) {
                            allMatch = false
                            break
                        }
                    }
                    
                    if allMatch {
                        // Found an occurrence! Mark all word indices
                        for offset in 0..<termWords.count {
                            let matchIndex = i + offset
                            // Only add if not already claimed by a longer term
                            if lookup[matchIndex] == nil {
                                lookup[matchIndex] = term
                            }
                        }
                        i += termWords.count // Skip past this match
                        continue
                    }
                }
                i += 1
            }
        }
        
        return lookup
    }
    
    /// Normalize word for matching (lowercase, remove punctuation)
    private func normalizeForMatching(_ word: String) -> String {
        // Remove common punctuation and quotes, lowercase
        // Using Unicode escapes for special quote characters to avoid syntax issues
        let quoteChars = "\u{201C}\u{201D}\u{201E}\u{2018}\u{2019}\u{201A}\u{201B}\u{2039}\u{203A}\u{00AB}\u{00BB}"
        let cleaned = word
            .trimmingCharacters(in: .punctuationCharacters)
            .trimmingCharacters(in: CharacterSet(charactersIn: quoteChars))
            .lowercased()
            .trimmingCharacters(in: .whitespaces)
        return cleaned
    }
    
    /// Check if two normalized words match (STRICT matching to avoid false positives)
    private func wordsMatch(_ word1: String, _ word2: String) -> Bool {
        // Empty check
        guard !word1.isEmpty && !word2.isEmpty else { return false }
        
        // Exact match
        if word1 == word2 { return true }
        
        // Prefix match ONLY for possessives (e.g., "Führer's" vs "Führer", "Hitler's" vs "Hitler")
        // The longer word must start with the shorter word
        // AND the suffix must be possessive-like
        if word1.count != word2.count {
            let (shorter, longer) = word1.count < word2.count ? (word1, word2) : (word2, word1)
            
            // Only check if the difference is small (1-2 chars for 's or s)
            let lengthDiff = longer.count - shorter.count
            if lengthDiff <= 2 && longer.hasPrefix(shorter) {
                let suffix = String(longer.dropFirst(shorter.count))
                // Only allow possessive suffixes: 's, 's, or just s
                if suffix == "s" || suffix == "'s" || suffix == "\u{2019}s" {
                    return true
                }
            }
        }
        
        return false
    }
    
    // Empty placeholder
    static var empty: ChapterExplainableTerms {
        ChapterExplainableTerms(
            chapterId: "",
            bookId: "",
            terms: [],
            processedAt: Date(),
            version: "2.0"
        )
    }
}
