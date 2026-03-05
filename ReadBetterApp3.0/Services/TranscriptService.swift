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

        // Fast path for local (offline) files — skip HTTP entirely
        if url.isFileURL {
            print("📱 TranscriptService: Loading transcript from local file: \(url.lastPathComponent)")
            let data = try Data(contentsOf: url)
            guard !data.isEmpty else {
                throw TranscriptError.emptyFile(urlString)
            }
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw TranscriptError.invalidJSON
            }
            return try parseTranscript(json: json)
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
        // Normalize line endings immediately so offsets and sentence splitting are consistent.
        let rawTranscriptText = json["transcript"] as? String ??
                            json["text"] as? String ??
                            ""
        let transcriptText = rawTranscriptText
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        
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

        // IMPORTANT: Keep `words` in transcript/text order.
        // KaraokeEngine builds its own time-sorted index for playback, but sentence-to-word
        // matching must be done in the same order as the transcript text. Sorting here by
        // timing can reorder words (especially around estimated/unreliable timings) and
        // causes cascading out-of-sync highlighting.

        // STEP 2.5: Estimate timing for words without timing data ("not-found-in-audio")
        estimateTimingForUnalignedWords(&words)

        // KaraokeEngine handles time-based lookup by sorting internally; we do NOT sort here.
        
        print("📊 TranscriptService: Found \(words.count) timed words")
        
        // STEP 3: Split transcript by \r\n\r\n to get sentences
        // Split sentences on double newlines (after normalization above).
        let sentenceTexts = transcriptText.components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        
        print("📊 TranscriptService: Found \(sentenceTexts.count) sentences")
        
        // STEP 4: Match words to sentences by ACTUAL TEXT MATCHING (not count!)
        // This ensures each word timing is matched to the correct word in the transcript
        var sentences: [TranscriptData.Sentence] = []
        var currentWordIndex = 0
        
        // Helper to normalize word for comparison (remove punctuation, lowercase)
        func normalizeWord(_ word: String) -> String {
            // Remove surrounding quotes and punctuation, lowercase, trim whitespace.
            let quoteChars = CharacterSet(charactersIn: "\"“”‘’‚‛‹›«»")
            let punctuation = CharacterSet.punctuationCharacters.union(quoteChars)
            // Include common "invisible" separators found in some transcript sources.
            let extraWhitespace = CharacterSet(charactersIn: "\u{00A0}\u{200B}\u{2028}\u{2029}")
            let whitespace = CharacterSet.whitespacesAndNewlines.union(extraWhitespace)
            return word
                .lowercased()
                .trimmingCharacters(in: punctuation)
                .trimmingCharacters(in: whitespace)
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

        // Split tokens on spaces/newlines + common unicode separators (NBSP, line separators, ZWSP).
        let tokenSeparators = CharacterSet.whitespacesAndNewlines
            .union(CharacterSet(charactersIn: "\u{00A0}\u{200B}\u{2028}\u{2029}"))
        
        for sentenceText in sentenceTexts {
            // Include newlines as separators too; some transcripts contain single line breaks
            // inside a "sentence" block, which would otherwise produce tokens like "fit\nBack".
            let wordCount = sentenceText.components(separatedBy: tokenSeparators)
                .filter { !$0.isEmpty }
                .map { normalizeWord($0) }
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
        
        // Now assign words to sentences using a strict sequential, non-overlapping strategy.
        // Critical constraints to prevent cascading drift:
        // - Never allow a large forward "jump" to match a token (that can swallow future sentences).
        // - Keep each sentence within a small budget: expectedWordCount + slack.
        // KaraokeEngine sorts by time internally for playback, but sentence assignment must remain in text order.
        var wordCursor = 0
        let baseLookahead = 12
        let sentenceSlack = 4     // allow a few extras for odd tokenization (quotes, hyphens, OCR quirks)
        let maxJumpAllowed = 2    // never jump more than this many words ahead to match a token
        
        for (sentenceIndex, sentenceText) in sentenceTexts.enumerated() {
            var sentenceWordIndices: [Int] = []
            let expectedWordCount = sentenceWordCounts[sentenceIndex]
            let maxWordsForSentence = max(0, expectedWordCount + sentenceSlack)
            
            let sentenceWords = sentenceText
                .components(separatedBy: tokenSeparators)
                .filter { !$0.isEmpty }
                .map { normalizeWord($0) }
            
            for sentenceWord in sentenceWords {
                guard !sentenceWord.isEmpty else { continue }
                if wordCursor >= words.count { break }
                if sentenceWordIndices.count >= maxWordsForSentence { break }
                
                // Search in a small lookahead window for the best match
                var bestMatch: Int? = nil
                var bestScore: Double = 0
                
                // Constrain search by remaining budget so we can't match something far ahead
                // and accidentally consume the beginning of the next sentence.
                let remainingBudget = maxWordsForSentence - sentenceWordIndices.count
                let budgetLookahead = min(baseLookahead, max(3, remainingBudget + 1))
                let searchEnd = min(wordCursor + budgetLookahead, words.count)
                
                for i in wordCursor..<searchEnd {
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
                
                // Accept only strong, near-cursor matches. Otherwise consume sequentially to preserve order.
                if let match = bestMatch, bestScore >= 60.0, (match - wordCursor) <= maxJumpAllowed {
                    // Optionally include the tiny skipped gap (<= maxJumpAllowed) if we have room.
                    if match > wordCursor {
                        for _ in wordCursor..<match {
                            if sentenceWordIndices.count >= maxWordsForSentence { break }
                            sentenceWordIndices.append(wordCursor)
                            wordCursor += 1
                        }
                    }
                    if sentenceWordIndices.count < maxWordsForSentence, wordCursor == match {
                        sentenceWordIndices.append(wordCursor)
                        wordCursor += 1
                    }
                } else {
                    // Strict fallback: consume next word to avoid drift.
                    if sentenceWordIndices.count < maxWordsForSentence, wordCursor < words.count {
                        sentenceWordIndices.append(wordCursor)
                        wordCursor += 1
                    }
                }
            }
            
            // If still short, fill sequentially up to expectedWordCount (bounded by maxWordsForSentence).
            while sentenceWordIndices.count < expectedWordCount && sentenceWordIndices.count < maxWordsForSentence && wordCursor < words.count {
                sentenceWordIndices.append(wordCursor)
                wordCursor += 1
            }
            
            // Calculate sentence timing from assigned words.
            // Use min/max across the sentence to stay robust even if a few word timings are jittery/out-of-order.
            let sentenceStartTime: Double
            let sentenceEndTime: Double
            if !sentenceWordIndices.isEmpty {
                var minStart = Double.greatestFiniteMagnitude
                var maxEnd = 0.0
                for idx in sentenceWordIndices {
                    minStart = min(minStart, words[idx].start)
                    maxEnd = max(maxEnd, words[idx].end)
                }
                if minStart.isFinite, maxEnd.isFinite, maxEnd > minStart {
                    sentenceStartTime = minStart
                    sentenceEndTime = maxEnd
                } else {
                    // Fallback to time range estimate if computed bounds are invalid.
                    let timeRange = sentenceTimeRanges[sentenceIndex]
                    sentenceStartTime = timeRange.start
                    sentenceEndTime = timeRange.end
                }
            } else {
                // Fallback to time range estimate
                let timeRange = sentenceTimeRanges[sentenceIndex]
                sentenceStartTime = timeRange.start
                sentenceEndTime = timeRange.end
            }
            
            sentences.append(TranscriptData.Sentence(
                text: sentenceText,
                wordIndices: sentenceWordIndices,
                startTime: sentenceStartTime,
                endTime: sentenceEndTime
            ))
        }
        
        // If any words remain unassigned, append them to the last sentence (without duplicates)
        if wordCursor < words.count, var last = sentences.last {
            var updated = last.wordIndices
            for idx in wordCursor..<words.count { updated.append(idx) }
            if !updated.isEmpty {
                var minStart = last.startTime
                var maxEnd = last.endTime
                for idx in updated {
                    minStart = min(minStart, words[idx].start)
                    maxEnd = max(maxEnd, words[idx].end)
                }
                last = TranscriptData.Sentence(
                    text: last.text,
                    wordIndices: updated,
                    startTime: minStart,
                    endTime: maxEnd
                )
                sentences[sentences.count - 1] = last
            }
        }
        
        // Diagnostics: detect duplicates/missing coverage (pre-recovery).
        func computeCoverage(_ sentences: [TranscriptData.Sentence]) -> (missing: [Int], duplicates: [Int: [Int]]) {
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
            return (missing, duplicates)
        }

        let coverage = computeCoverage(sentences)
        if !coverage.duplicates.isEmpty {
            print("⚠️ TranscriptService: word→sentence duplicates (first 10): \(coverage.duplicates.prefix(10))")
        }
        if !coverage.missing.isEmpty {
            print("❌ TranscriptService: missing word assignments (first 20): \(coverage.missing.prefix(20)), total \(coverage.missing.count)")
            if let first = coverage.missing.first {
                let lo = max(0, first - 5)
                let hi = min(words.count - 1, first + 5)
                let context = (lo...hi).map { i -> String in
                    let w = words[i]
                    return "\(i):\(w.text)@\(String(format: "%.2f", w.start))"
                }.joined(separator: " | ")
                print("🔎 TranscriptService: first missing context: \(context)")
            }
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

