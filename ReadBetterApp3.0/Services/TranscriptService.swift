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
        
        // Now assign words to sentences using hybrid approach: time-based with text validation
        // CRITICAL: Track which word indices have been assigned to prevent duplicates
        var assignedWordIndices: Set<Int> = []
        
        for (sentenceIndex, sentenceText) in sentenceTexts.enumerated() {
            var sentenceWordIndices: [Int] = []
            var sentenceStartTime: Double = Double.infinity
            var sentenceEndTime: Double = 0
            
            let timeRange = sentenceTimeRanges[sentenceIndex]
            let expectedWordCount = sentenceWordCounts[sentenceIndex]
            
            // Strategy 1: Assign words based on time range (primary method)
            // BUT: Filter out words that are already assigned to previous sentences
            var candidateIndices: [Int] = []
            for (wordIndex, word) in words.enumerated() {
                // Skip words already assigned to another sentence
                if assignedWordIndices.contains(wordIndex) {
                    continue
                }
                
                // Word belongs to this sentence if its timing overlaps with sentence time range
                // Use generous overlap: word starts before sentence ends OR word ends after sentence starts
                if word.start < timeRange.end + 0.5 && word.end > timeRange.start - 0.5 {
                    candidateIndices.append(wordIndex)
                }
            }
            
            // Strategy 2: If we have too few candidates, use sequential assignment
            if candidateIndices.count < Int(Double(expectedWordCount) * 0.5) {
                // Fall back to sequential assignment based on word position
                let startIdx = timeRange.wordStartIndex
                let endIdx = min(timeRange.wordEndIndex, words.count)
                candidateIndices = Array(startIdx..<endIdx)
            }
            
            // Strategy 3: Try to match by text for better accuracy (optional validation)
            let sentenceWords = sentenceText.components(separatedBy: .whitespaces)
                .filter { !$0.isEmpty }
            
            // If we have candidates, try to refine the match using text
            if !candidateIndices.isEmpty && candidateIndices.count <= expectedWordCount * 2 {
                var matchedIndices: [Int] = []
                var searchStart = candidateIndices.first ?? currentWordIndex
                
                for sentenceWord in sentenceWords {
                    let normalizedSentenceWord = normalizeWord(sentenceWord)
                    guard !normalizedSentenceWord.isEmpty else { continue }
                    
                    // Search in candidate range with wider window
                    let searchEnd = min(searchStart + 15, words.count)
                    var bestMatch: (index: Int, score: Double)? = nil
                    
                    for i in searchStart..<searchEnd {
                        // Skip words already assigned to another sentence
                        if assignedWordIndices.contains(i) {
                            continue
                        }
                        
                        // Only consider words in candidate list
                        if !candidateIndices.contains(i) && candidateIndices.count > expectedWordCount {
                            continue
                        }
                        
                        let timingWord = words[i]
                        let normalizedTimingWord = normalizeWord(timingWord.text)
                        
                        // Calculate match score
                        var score = 0.0
                        
                        // Exact match = highest score
                        if normalizedSentenceWord == normalizedTimingWord {
                            score = 100.0
                        }
                        // Contains match = medium score
                        else if normalizedSentenceWord.contains(normalizedTimingWord) || 
                                normalizedTimingWord.contains(normalizedSentenceWord) {
                            score = 50.0
                        }
                        // Similar length = low score
                        else if abs(normalizedSentenceWord.count - normalizedTimingWord.count) <= 2 {
                            let commonChars = Set(normalizedSentenceWord).intersection(Set(normalizedTimingWord)).count
                            score = Double(commonChars) / Double(max(normalizedSentenceWord.count, normalizedTimingWord.count)) * 30.0
                        }
                        
                        // Prefer words closer to expected position
                        let positionBonus = max(0, 10.0 - Double(i - searchStart))
                        score += positionBonus
                        
                        if score > 0 && (bestMatch == nil || score > bestMatch!.score) {
                            bestMatch = (i, score)
                        }
                    }
                    
                    // Use best match if score is reasonable, otherwise use sequential
                    if let match = bestMatch, match.score >= 20.0 {
                        matchedIndices.append(match.index)
                        searchStart = match.index + 1
                    } else {
                        // Use sequential assignment if no good match
                        // But skip words already assigned
                        while searchStart < words.count {
                            if !assignedWordIndices.contains(searchStart) && !matchedIndices.contains(searchStart) {
                                matchedIndices.append(searchStart)
                                searchStart += 1
                                break
                            }
                            searchStart += 1
                        }
                    }
                }
                
                sentenceWordIndices = matchedIndices.isEmpty ? candidateIndices : matchedIndices
            } else {
                // Too many candidates or no candidates - use sequential assignment
                // But filter out already-assigned words
                if candidateIndices.isEmpty {
                    let sequentialRange = Array(timeRange.wordStartIndex..<min(timeRange.wordEndIndex, words.count))
                    sentenceWordIndices = sequentialRange.filter { !assignedWordIndices.contains($0) }
                } else {
                    sentenceWordIndices = candidateIndices
                        .filter { !assignedWordIndices.contains($0) }
                        .prefix(expectedWordCount * 2)
                        .sorted()
                }
            }
            
            // Remove duplicates and sort
            sentenceWordIndices = Array(Set(sentenceWordIndices)).sorted()
            
            // CRITICAL: Mark these words as assigned so they can't be assigned to other sentences
            for wordIndex in sentenceWordIndices {
                assignedWordIndices.insert(wordIndex)
            }
            
            // Calculate sentence timing from assigned words
            if !sentenceWordIndices.isEmpty {
                sentenceStartTime = words[sentenceWordIndices.first!].start
                sentenceEndTime = words[sentenceWordIndices.last!].end
            } else {
                sentenceStartTime = timeRange.start
                sentenceEndTime = timeRange.end
            }
            
            // Update currentWordIndex for next sentence
            if !sentenceWordIndices.isEmpty {
                currentWordIndex = max(currentWordIndex, sentenceWordIndices.last! + 1)
            }
            
            // Create sentence with matched word indices
            sentences.append(TranscriptData.Sentence(
                text: sentenceText,
                wordIndices: sentenceWordIndices,
                startTime: sentenceStartTime,
                endTime: sentenceEndTime
            ))
        }
        
        // Handle any remaining timing words (assign to last sentence)
        if currentWordIndex < words.count {
            let remainingWords = words.count - currentWordIndex
            if remainingWords > 0 {
                print("📊 TranscriptService: \(remainingWords) timing words remaining, assigning to last sentence")
                
                // Add remaining words to last sentence
                // But only add words that haven't been assigned yet
                if let lastSentence = sentences.last {
                    var updatedIndices = lastSentence.wordIndices
                    var lastEndTime = lastSentence.endTime
                    
                    for i in 0..<remainingWords {
                        let wordIndex = currentWordIndex + i
                        // Only add if not already assigned to this or another sentence
                        if !assignedWordIndices.contains(wordIndex) && !updatedIndices.contains(wordIndex) {
                            updatedIndices.append(wordIndex)
                            assignedWordIndices.insert(wordIndex) // Mark as assigned
                        }
                        // Update end time even if word was already assigned (for timing accuracy)
                        if wordIndex < words.count {
                            lastEndTime = max(lastEndTime, words[wordIndex].end)
                        }
                    }
                    
                    sentences[sentences.count - 1] = TranscriptData.Sentence(
                        text: lastSentence.text,
                        wordIndices: updatedIndices.sorted(),
                        startTime: lastSentence.startTime,
                        endTime: lastEndTime
                    )
                }
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

