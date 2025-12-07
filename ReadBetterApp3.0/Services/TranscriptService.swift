//
//  TranscriptService.swift
//  ReadBetterApp3.0
//
//  Created by Ermin on 30/11/2025.
//

import Foundation
import OSLog

class TranscriptService {
    static let shared = TranscriptService()
    
    private let logger = Logger(subsystem: "com.readbetter", category: "TranscriptService")
    
    // Create URLSession with NO HTTP caching (always fetch fresh from Firebase)
    private lazy var noCacheSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.urlCache = nil
        return URLSession(configuration: config)
    }()
    
    private init() {}
    
    /// Load transcript directly from GCS and parse on-device
    /// Always loads fresh data (no caching) to ensure correct word highlighting
    func loadTranscript(from urlString: String, bookId: String? = nil, chapterId: String? = nil) async throws -> TranscriptData {
        // Always load fresh data directly from GCS (no caching)
        // This ensures word highlighting works correctly with fresh transcript data
        let transcriptData = try await loadTranscriptDirect(from: urlString)
        
        return transcriptData
    }
    
    /// Load and parse transcript JSON directly from URL (fallback method)
    /// This is the original method that does heavy processing on-device
    private func loadTranscriptDirect(from urlString: String) async throws -> TranscriptData {
        guard let url = URL(string: urlString) else {
            print("❌ TranscriptService: Invalid URL - \(urlString)")
            throw TranscriptError.invalidURL
        }
        
        print("📥 TranscriptService: Loading transcript directly from GCS (NO CACHE): \(urlString)")
        
        // Use noCacheSession instead of URLSession.shared to bypass HTTP cache
        let (data, response) = try await noCacheSession.data(from: url)
        
        // Check HTTP response
        if let httpResponse = response as? HTTPURLResponse {
            print("📡 TranscriptService: HTTP \(httpResponse.statusCode) for \(urlString)")
            
            if httpResponse.statusCode == 404 {
                print("❌ TranscriptService: File not found (404)")
                throw TranscriptError.fileNotFound(urlString)
            }
            
            if httpResponse.statusCode != 200 {
                print("❌ TranscriptService: HTTP error \(httpResponse.statusCode)")
                throw TranscriptError.httpError(httpResponse.statusCode)
            }
        }
        
        // Check if data is empty
        if data.isEmpty {
            print("❌ TranscriptService: Empty file")
            throw TranscriptError.emptyFile(urlString)
        }
        
        // Try to parse JSON
        do {
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                // Print first 500 chars of data to see what we got
                if let dataString = String(data: data, encoding: .utf8) {
                    print("❌ TranscriptService: Invalid JSON structure. First 500 chars:")
                    print(String(dataString.prefix(500)))
                }
                throw TranscriptError.invalidJSON
            }
            
            print("✅ TranscriptService: JSON parsed successfully")
            let transcriptData = try parseTranscript(json: json)
            
            print("✅ TranscriptService: Loaded transcript from GCS (parsed on-device)")
            
            return transcriptData
            
        } catch let jsonError as NSError {
            // Print what we received to help debug
            if let dataString = String(data: data, encoding: .utf8) {
                print("❌ TranscriptService: JSON parse error. First 500 chars of response:")
                print(String(dataString.prefix(500)))
            }
            print("❌ TranscriptService: JSON Error: \(jsonError.localizedDescription)")
            throw TranscriptError.jsonParseError(jsonError.localizedDescription)
        }
    }
    
    /// Parse transcript JSON - TIME-BASED word matching (more robust than text matching)
    private func parseTranscript(json: [String: Any]) throws -> TranscriptData {
        // STEP 1: Get the full transcript text (authoritative source for display)
        let transcriptText = json["transcript"] as? String ??
                            json["text"] as? String ??
                            ""
        
        guard !transcriptText.isEmpty else {
            throw TranscriptError.noWordsFound
        }
        
        // STEP 2: Extract words with timing data
        var words: [WordTiming] = []
        var wordCounter = 0
        
        // Try flat words array first (most common format)
        if let wordsArray = json["words"] as? [[String: Any]] {
            for wordJson in wordsArray {
                if let word = WordTiming(from: wordJson, index: wordCounter) {
                    words.append(word)
                    wordCounter += 1
                }
            }
        }
        // Try sentences structure
        else if let sentences = json["sentences"] as? [[String: Any]] {
            for sentence in sentences {
                if let sentenceWords = sentence["words"] as? [[String: Any]] {
                    for wordJson in sentenceWords {
                        if let word = WordTiming(from: wordJson, index: wordCounter) {
                            words.append(word)
                            wordCounter += 1
                        }
                    }
                }
            }
        }
        // Try direct words array at root
        else if let wordsArray = json["words"] as? [Any] {
            for item in wordsArray {
                if let wordJson = item as? [String: Any],
                   let word = WordTiming(from: wordJson, index: wordCounter) {
                    words.append(word)
                    wordCounter += 1
                }
            }
        }
        
        // Sort words by start time (words with -1 will be at the end initially)
        words.sort { word1, word2 in
            // Words with valid timing first, sorted by time
            if word1.start >= 0 && word2.start >= 0 {
                return word1.start < word2.start
            } else if word1.start >= 0 {
                return true // word1 has timing, word2 doesn't
            } else if word2.start >= 0 {
                return false // word2 has timing, word1 doesn't
            } else {
                // Both need estimation - keep original order
                return word1.index < word2.index
            }
        }
        
        // STEP 2.5: Estimate timing for words without timing data ("not-found-in-audio")
        estimateTimingForUnalignedWords(&words)
        
        // Re-sort after estimation (all should have valid timing now)
        // IMPORTANT: We sort by time for lookup efficiency, but preserve original indices
        words.sort { $0.start < $1.start }
        
        // DO NOT re-index! Preserve original JSON indices for sentence matching
        // The index represents the position in the original JSON array, not the sorted position
        
        print("📊 TranscriptService: Found \(words.count) timed words")
        
        // STEP 3: Split transcript by \r\n\r\n to get sentences
        let sentenceTexts = transcriptText.components(separatedBy: "\r\n\r\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        
        print("📊 TranscriptService: Found \(sentenceTexts.count) sentences")
        
        // STEP 4: Match words to sentences by ACTUAL TEXT MATCHING (not count!)
        // This ensures each word timing is matched to the correct word in the transcript
        var sentences: [TranscriptData.Sentence] = []
        var currentWordIndex = 0
        
        // Helper to normalize word for comparison (remove punctuation, lowercase)
        func normalizeWord(_ word: String) -> String {
            return word.lowercased()
                .trimmingCharacters(in: CharacterSet.punctuationCharacters)
                .trimmingCharacters(in: .whitespaces)
        }
        
        // Helper to check if two normalized words match (handles contractions, etc.)
        func wordsMatch(_ word1: String, _ word2: String) -> Bool {
            let norm1 = normalizeWord(word1)
            let norm2 = normalizeWord(word2)
            
            // Exact match
            if norm1 == norm2 { return true }
            
            // One contains the other (handles "don't" vs "don", "I'm" vs "I")
            if !norm1.isEmpty && !norm2.isEmpty {
                if norm1.contains(norm2) || norm2.contains(norm1) {
                    // Only allow if the difference is small (handles contractions)
                    let diff = abs(norm1.count - norm2.count)
                    if diff <= 3 { return true }
                }
            }
            
            return false
        }
        
        // TIME-BASED MATCHING: More robust approach
        // First, estimate word distribution across sentences based on word count
        var sentenceWordCounts: [Int] = []
        var totalExpectedWords = 0
        
        for sentenceText in sentenceTexts {
            let wordCount = sentenceText.components(separatedBy: .whitespaces)
                .filter { !$0.isEmpty }
                .count
            sentenceWordCounts.append(wordCount)
            totalExpectedWords += wordCount
        }
        
        // Calculate approximate time ranges for each sentence based on word distribution
        var sentenceTimeRanges: [(start: Double, end: Double, wordStartIndex: Int, wordEndIndex: Int)] = []
        var wordsAssigned = 0
        
        for (_, wordCount) in sentenceWordCounts.enumerated() {
            let wordStartIndex = wordsAssigned
            let wordEndIndex = min(wordsAssigned + wordCount, words.count)
            
            // Get time range from actual word timings
            let timeStart = wordStartIndex < words.count ? words[wordStartIndex].start : 0
            let timeEnd = wordEndIndex > 0 && wordEndIndex <= words.count ? words[wordEndIndex - 1].end : (words.last?.end ?? 0)
            
            sentenceTimeRanges.append((timeStart, timeEnd, wordStartIndex, wordEndIndex))
            wordsAssigned = wordEndIndex
        }
        
        // Now assign words to sentences using a strict sequential, non-overlapping strategy
        // Once a word is assigned, it is never reused by another sentence
        var assignedWordIndices: Set<Int> = []
        var wordCursor = 0
        let lookahead = 10
        
        for (sentenceIndex, sentenceText) in sentenceTexts.enumerated() {
            var sentenceWordIndices: [Int] = []
            let expectedWordCount = sentenceWordCounts[sentenceIndex]
            
            let sentenceWords = sentenceText
                .components(separatedBy: .whitespaces)
                .filter { !$0.isEmpty }
                .map { normalizeWord($0) }
            
            for sentenceWord in sentenceWords {
                guard !sentenceWord.isEmpty else { continue }
                
                // Search in a small lookahead window for the best match
                var bestMatch: Int? = nil
                var bestScore: Double = 0
                let searchEnd = min(wordCursor + lookahead, words.count)
                
                for i in wordCursor..<searchEnd {
                    if assignedWordIndices.contains(i) { continue }
                    let timingWord = normalizeWord(words[i].text)
                    
                    var score = 0.0
                    if timingWord == sentenceWord {
                        score = 100.0
                    } else if sentenceWord.contains(timingWord) || timingWord.contains(sentenceWord) {
                        score = 50.0
                    } else if abs(sentenceWord.count - timingWord.count) <= 2 {
                        let commonChars = Set(sentenceWord).intersection(Set(timingWord)).count
                        score = Double(commonChars) / Double(max(sentenceWord.count, timingWord.count)) * 30.0
                    }
                    
                    // Position bonus (closer to cursor is better)
                    let positionBonus = max(0, 10 - (i - wordCursor))
                    score += Double(positionBonus)
                    
                    if score > bestScore {
                        bestScore = score
                        bestMatch = i
                    }
                }
                
                if let match = bestMatch, bestScore >= 20.0 {
                    sentenceWordIndices.append(match)
                    assignedWordIndices.insert(match)
                    wordCursor = match + 1
                } else {
                    // Fallback: take the next unassigned word at cursor if available
                    while wordCursor < words.count && assignedWordIndices.contains(wordCursor) {
                        wordCursor += 1
                    }
                    if wordCursor < words.count {
                        sentenceWordIndices.append(wordCursor)
                        assignedWordIndices.insert(wordCursor)
                        wordCursor += 1
                    }
                }
            }
            
            // If still short, fill sequentially without overlap up to expectedWordCount
            while sentenceWordIndices.count < expectedWordCount && wordCursor < words.count {
                if !assignedWordIndices.contains(wordCursor) {
                    sentenceWordIndices.append(wordCursor)
                    assignedWordIndices.insert(wordCursor)
                }
                wordCursor += 1
            }
            
            // Trim any overshoot to avoid excessive assignments
            if sentenceWordIndices.count > expectedWordCount + 5 {
                sentenceWordIndices = Array(sentenceWordIndices.prefix(expectedWordCount + 5))
            }
            
            // Calculate sentence timing from assigned words
            let sentenceStartTime: Double
            let sentenceEndTime: Double
            if let firstIdx = sentenceWordIndices.first, let lastIdx = sentenceWordIndices.last {
                sentenceStartTime = words[firstIdx].start
                sentenceEndTime = words[lastIdx].end
            } else {
                // Fallback to time range estimate
                let timeRange = sentenceTimeRanges[sentenceIndex]
                sentenceStartTime = timeRange.start
                sentenceEndTime = timeRange.end
            }
            
            sentences.append(TranscriptData.Sentence(
                text: sentenceText,
                wordIndices: Array(Set(sentenceWordIndices)).sorted(),
                startTime: sentenceStartTime,
                endTime: sentenceEndTime
            ))
        }
        
        // If any words remain unassigned, append them to the last sentence (without duplicates)
        if wordCursor < words.count, var last = sentences.last {
            var updated = last.wordIndices
            for idx in wordCursor..<words.count where !assignedWordIndices.contains(idx) {
                updated.append(idx)
                assignedWordIndices.insert(idx)
            }
            if let firstIdx = updated.first, let lastIdx = updated.last {
                last = TranscriptData.Sentence(
                    text: last.text,
                    wordIndices: Array(Set(updated)).sorted(),
                    startTime: words[firstIdx].start,
                    endTime: words[lastIdx].end
                )
                sentences[sentences.count - 1] = last
            }
        }
        
        // Diagnostics: detect duplicates/missing coverage
        var wordToSentence: [Int: Int] = [:]
        var duplicates: [Int: [Int]] = [:]
        for (sIdx, sentence) in sentences.enumerated() {
            for wIdx in sentence.wordIndices {
                if let existing = wordToSentence[wIdx] {
                    duplicates[wIdx, default: []].append(contentsOf: [existing, sIdx])
                } else {
                    wordToSentence[wIdx] = sIdx
                }
            }
        }
        let missing = (0..<words.count).filter { wordToSentence[$0] == nil }
        if !duplicates.isEmpty {
            print("⚠️ TranscriptService: word→sentence duplicates (showing first 10): \(duplicates.prefix(10))")
        }
        if !missing.isEmpty {
            print("⚠️ TranscriptService: missing word assignments (showing first 20): \(missing.prefix(20)), total \(missing.count)")
        }
        
        let matchedWords = sentences.reduce(0) { $0 + $1.wordIndices.count }
        print("✅ TranscriptService: Matched \(matchedWords) of \(words.count) timing words to \(sentences.count) sentences")
        
        return TranscriptData(
            fullText: transcriptText,
            sentences: sentences,
            words: words
        )
    }
    
    // MARK: - Estimate Timing for Unaligned Words
    private func estimateTimingForUnalignedWords(_ words: inout [WordTiming]) {
        // Find all words that need timing estimation (start < 0)
        let wordsNeedingEstimation = words.enumerated().filter { $0.element.start < 0 }
        
        guard !wordsNeedingEstimation.isEmpty else { return }
        
        print("📊 TranscriptService: Estimating timing for \(wordsNeedingEstimation.count) unaligned words")
        
        // Create a map: original JSON index -> sorted array index
        // This allows us to find words by their original JSON position even after sorting
        let sortedIndexByJsonIndex = Dictionary(uniqueKeysWithValues: 
            words.enumerated().map { ($0.element.index, $0.offset) }
        )
        
        for (sortedArrayIndex, word) in wordsNeedingEstimation {
            let originalJsonIndex = word.index  // This is the REAL original JSON position
            var estimatedStart: Double = 0
            var estimatedEnd: Double = 0
            
            // Find previous word with valid timing IN ORIGINAL JSON ORDER
            // We search by original JSON index, then look up its sorted position
            var prevWord: WordTiming? = nil
            var prevSortedIndex: Int? = nil
            for j in stride(from: originalJsonIndex - 1, through: 0, by: -1) {
                if let candidateSortedIdx = sortedIndexByJsonIndex[j],
                   candidateSortedIdx < words.count,
                   words[candidateSortedIdx].start >= 0 && words[candidateSortedIdx].end > words[candidateSortedIdx].start {
                    prevWord = words[candidateSortedIdx]
                    prevSortedIndex = candidateSortedIdx
                    break
                }
            }
            
            // Find next word with valid timing IN ORIGINAL JSON ORDER
            var nextWord: WordTiming? = nil
            var nextSortedIndex: Int? = nil
            let maxJsonIndex = words.map { $0.index }.max() ?? originalJsonIndex
            // Fix: Check if range is valid before using it to prevent crash
            if (originalJsonIndex + 1) <= maxJsonIndex {
                for j in (originalJsonIndex + 1)...maxJsonIndex {
                    if let candidateSortedIdx = sortedIndexByJsonIndex[j],
                       candidateSortedIdx < words.count,
                       words[candidateSortedIdx].start >= 0 && words[candidateSortedIdx].end > words[candidateSortedIdx].start {
                        nextWord = words[candidateSortedIdx]
                        nextSortedIndex = candidateSortedIdx
                        break
                    }
                }
            }
            
            // Estimate timing based on surrounding words
            if let prev = prevWord, let next = nextWord, let _ = prevSortedIndex, let _ = nextSortedIndex {
                // Interpolate between previous and next word
                let timeGap = next.start - prev.end
                
                // Ensure we have a positive gap (if words overlap, use minimum gap)
                let safeTimeGap = max(0.05, timeGap) // Minimum 50ms gap
                
                // Count how many words need estimation in this gap (in original JSON order)
                var wordsNeedingEstimationInGap = 0
                for j in (prev.index + 1)..<next.index {
                    if let candidateSortedIdx = sortedIndexByJsonIndex[j],
                       candidateSortedIdx < words.count,
                       words[candidateSortedIdx].start < 0 {
                        wordsNeedingEstimationInGap += 1
                    }
                }
                let totalWordsInGap = max(1, wordsNeedingEstimationInGap)
                
                // Distribute time evenly, but make each word VERY SHORT to prevent lag
                let timePerWord = safeTimeGap / Double(totalWordsInGap + 1)
                let positionInGap = Double(originalJsonIndex - prev.index - 1)
                
                estimatedStart = prev.end + (timePerWord * (positionInGap + 1))
                
                // KEY FIX: Make estimated words VERY SHORT (50-100ms max) to prevent lag
                // This ensures they don't linger and cause timing issues
                let estimatedDuration = min(0.1, timePerWord * 0.3) // Max 100ms, or 30% of gap
                estimatedEnd = estimatedStart + estimatedDuration
                
                // Ensure end doesn't exceed next word's start (with safety margin)
                estimatedEnd = min(estimatedEnd, next.start - 0.02) // 20ms safety margin
                estimatedStart = min(estimatedStart, estimatedEnd - 0.05) // Ensure at least 50ms duration
                
                // Final validation: ensure start < end
                if estimatedStart >= estimatedEnd {
                    estimatedEnd = estimatedStart + 0.05 // Minimum 50ms duration
                }
            } else if let prev = prevWord {
                // Only previous word - estimate with SHORT duration to prevent lag
                estimatedStart = max(prev.end, prev.end + 0.05) // At least 50ms gap
                estimatedEnd = estimatedStart + 0.1 // 100ms duration (short to prevent lag)
            } else if let next = nextWord {
                // Only next word - estimate backwards with SHORT duration
                estimatedEnd = max(0.1, next.start - 0.05) // At least 50ms before next
                estimatedStart = max(0, estimatedEnd - 0.1) // 100ms duration (short to prevent lag)
            } else {
                // No timing at all - use defaults (shouldn't happen, but handle it)
                estimatedStart = 0.0
                estimatedEnd = 0.1 // Short duration even for defaults
            }
            
            // Final validation: ensure values are valid
            if !(estimatedStart >= 0 && estimatedEnd > estimatedStart && estimatedStart.isFinite && estimatedEnd.isFinite) {
                // Fallback to safe defaults with SHORT duration
                print("⚠️ TranscriptService: Invalid estimated timing for word '\(word.text)' at JSON index \(originalJsonIndex), using safe defaults")
                estimatedStart = max(0, (prevWord?.end ?? 0) + 0.05)
                estimatedEnd = estimatedStart + 0.1 // Short duration to prevent lag
            }
            
            // Update word with estimated timing (use sortedArrayIndex to update the correct position in the sorted array)
            words[sortedArrayIndex] = WordTiming(
                text: word.text,
                start: estimatedStart,
                end: estimatedEnd,
                index: word.index,  // Preserve original JSON index
                hasLineBreak: word.hasLineBreak
            )
        }
        
        print("✅ TranscriptService: Completed timing estimation")
    }
}

enum TranscriptError: LocalizedError {
    case invalidURL
    case invalidJSON
    case noWordsFound
    case networkError(Error)
    case fileNotFound(String)
    case httpError(Int)
    case emptyFile(String)
    case jsonParseError(String)
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid transcript URL"
        case .invalidJSON:
            return "Invalid JSON structure"
        case .noWordsFound:
            return "No transcript text found in JSON"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .fileNotFound(let url):
            return "Transcript file not found: \(url)"
        case .httpError(let code):
            return "HTTP error \(code)"
        case .emptyFile(let url):
            return "Transcript file is empty: \(url)"
        case .jsonParseError(let message):
            return "JSON parse error: \(message)"
        }
    }
}

