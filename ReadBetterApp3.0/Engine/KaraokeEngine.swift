//
//  KaraokeEngine.swift
//  ReadBetterApp3.0
//
//  High-performance word synchronization engine with:
//  - Binary search O(log n) word lookup
//  - Caching to avoid repeated lookups
//  - Sequential playback optimization
//  - Buffer zones for smooth transitions
//

import Foundation
import Combine

struct IndexedWord: Identifiable {
    let id: Int
    let text: String
    let normalizedText: String
    let start: Double
    let end: Double
    let bufferStart: Double  // 100ms before
    let bufferEnd: Double    // 100ms after
    
    init(index: Int, text: String, start: Double, end: Double) {
        self.id = index
        self.text = text
        self.normalizedText = text.lowercased().trimmingCharacters(in: .punctuationCharacters)
        self.start = start
        self.end = end
        self.bufferStart = max(0, start - 0.1)
        self.bufferEnd = end + 0.1
    }
}

struct PrecomputedSentence: Identifiable {
    let id: UUID
    let text: String
    let wordRanges: [(wordIndex: Int, range: Range<String.Index>)]
    let globalWordIndices: [Int]
    let startTime: Double
    let endTime: Double
    
    init(text: String, wordRanges: [(wordIndex: Int, range: Range<String.Index>)], globalWordIndices: [Int], startTime: Double, endTime: Double) {
        self.id = UUID()
        self.text = text
        self.wordRanges = wordRanges
        self.globalWordIndices = globalWordIndices
        self.startTime = startTime
        self.endTime = endTime
    }
}

class KaraokeEngine: ObservableObject {
    // MARK: - Published State
    @Published private(set) var currentWordIndex: Int? = nil
    @Published private(set) var lastSpokenWordIndex: Int? = nil // Track last word that was spoken
    @Published private(set) var isReady: Bool = false
    @Published private(set) var progress: Double = 0.0
    
    // MARK: - Indexed Data
    private var indexedWords: [IndexedWord] = []
    private var sentences: [PrecomputedSentence] = []
    private var totalWords: Int = 0
    
    // MARK: - O(1) Lookup Dictionary (word ID -> array index)
    private var wordIdToArrayIndex: [Int: Int] = [:]
    
    // MARK: - Caching for O(1) repeated lookups
    private var lastLookupTime: Double = -1
    private var lastLookupResult: Int? = nil // Stores original index (id), not array index
    private var currentWordArrayIndex: Int = 0 // Track current position for sequential fast-forward (Grok's approach)
    
    // MARK: - Sentence-based gating
    private var currentSentenceIndex: Int? = nil
    
    // MARK: - Event-driven word scheduling
    private var wordUpdateTimer: Timer?
    private var nextWordStartTime: Double = 0
    private var lastPublishedWordIndex: Int? = nil // Only publish when actually changes
    private var audioTimeGetter: (() -> Double)? = nil // Callback to get current audio time
    
    // MARK: - Throttling to prevent update overload (only for progress, not words)
    private var lastProgressUpdateTime: Double = -1
    private let progressUpdateInterval: Double = 0.1 // 10fps for progress bar only
    
    // Note: Word sync updates come from AVPlayer's time observer (~30fps) for accurate audio timing
    
    // MARK: - Build Index
    @MainActor
    func buildIndex(from transcriptData: TranscriptData) {
        let startTime = CFAbsoluteTimeGetCurrent()
        
        // Index all words with validation
        indexedWords = transcriptData.words.enumerated().compactMap { index, word in
            // Validate timing before indexing
            guard word.start >= 0,
                  word.end > word.start,
                  word.start.isFinite,
                  word.end.isFinite else {
                print("⚠️ KaraokeEngine: Skipping word '\(word.text)' at index \(index) - invalid timing (start: \(word.start), end: \(word.end))")
                return nil
            }
            
            return IndexedWord(
                index: index,
                text: word.text,
                start: word.start,
                end: word.end
            )
        }
        
        // Sort by start time (should already be sorted, but ensure)
        indexedWords.sort { $0.start < $1.start }
        
        totalWords = indexedWords.count
        
        // Build O(1) lookup dictionary
        wordIdToArrayIndex.removeAll()
        for (arrayIndex, word) in indexedWords.enumerated() {
            wordIdToArrayIndex[word.id] = arrayIndex
        }
        
        // Precompute sentences with word ranges
        sentences = transcriptData.sentences.map { sentence in
            precomputeSentence(sentence, words: indexedWords)
        }
        
        // OPTIMIZATION: Only validate if there are potential issues (skip if all words are valid)
        // Removed redundant validation - words are already validated during indexing
        
        let duration = CFAbsoluteTimeGetCurrent() - startTime
        print("✅ KaraokeEngine: Indexed \(totalWords) words in \(String(format: "%.2f", duration * 1000))ms")
        
        isReady = true
    }
    
    // MARK: - Precompute Sentence Word Ranges
    private func precomputeSentence(_ sentence: TranscriptData.Sentence, words: [IndexedWord]) -> PrecomputedSentence {
        let sentenceText = sentence.text
        var wordRanges: [(wordIndex: Int, range: Range<String.Index>)] = []
        var globalIndices: [Int] = []
        var startTime: Double = Double.infinity
        var endTime: Double = 0
        
        // For each word index in the sentence, find its position in the text
        // IMPORTANT: Find words by original index (id), not array position
        // because some words may have been filtered out
        for wordIndex in sentence.wordIndices {
            // Find word by original index (id), not array position - use O(1) lookup
            guard let word = getWordByOriginalIndex(wordIndex) else {
                print("⚠️ KaraokeEngine: Word at original index \(wordIndex) not found in indexed words (was filtered out)")
                continue
            }
            
            // Update time range
            if word.start < startTime { startTime = word.start }
            if word.end > endTime { endTime = word.end }
            
            globalIndices.append(wordIndex)
            
            // Find word position in sentence text
            let searchText = word.text
            var searchStart = sentenceText.startIndex
            
            // Skip already found words
            if let lastRange = wordRanges.last {
                searchStart = lastRange.range.upperBound
            }
            
            // Search for the word
            if let range = sentenceText.range(of: searchText, options: [.caseInsensitive], range: searchStart..<sentenceText.endIndex) {
                wordRanges.append((wordIndex: wordIndex, range: range))
            }
        }
        
        return PrecomputedSentence(
            text: sentenceText,
            wordRanges: wordRanges,
            globalWordIndices: globalIndices,
            startTime: startTime == Double.infinity ? 0 : startTime,
            endTime: endTime
        )
    }
    
    // MARK: - Get Word at Time (Sequential Fast-Forward - Grok's Approach)
    // Returns original index (id), not array index
    // Uses O(1) sequential fast-forward during playback (much faster than binary search)
    func getWordAtTime(_ time: Double) -> Int? {
        guard isReady, !indexedWords.isEmpty else { return nil }
        
        // Validate time is finite and positive
        guard time.isFinite, time >= 0 else { return nil }
        
        // Cache check: If looking up the same time, return cached result
        if abs(time - lastLookupTime) < 0.001 {
            return lastLookupResult
        }
        
        // DETECT LARGE JUMPS: If time difference is large (>5 seconds), use binary search directly
        // This prevents slow sequential fast-forward when scrubbing to far positions
        let timeDifference = abs(time - lastLookupTime)
        let isLargeJump = timeDifference > 5.0 || lastLookupTime < 0
        
        // Ensure currentWordArrayIndex is within bounds
        if currentWordArrayIndex < 0 || currentWordArrayIndex >= indexedWords.count {
            currentWordArrayIndex = 0
        }
        
        // For large jumps, use binary search directly (skip sequential fast-forward)
        if isLargeJump {
            // Use binary search for entire array (fast for large jumps)
            var left = 0
            var right = indexedWords.count - 1
            var bestMatch: Int? = nil
            
            while left <= right {
                let mid = (left + right) / 2
                let word = indexedWords[mid]
                
                guard word.start.isFinite && word.end.isFinite && word.start < word.end else {
                    if time < word.start {
                        right = mid - 1
                    } else {
                        left = mid + 1
                    }
                    continue
                }
                
                if time >= word.start && time < word.end {
                    currentWordArrayIndex = mid
                    lastLookupTime = time
                    lastLookupResult = word.id
                    return word.id
                }
                
                if time < word.start {
                    right = mid - 1
                } else {
                    bestMatch = mid
                    left = mid + 1
                }
            }
            
            // Update currentWordArrayIndex to best match
            if let best = bestMatch {
                currentWordArrayIndex = best
            } else {
                currentWordArrayIndex = 0
            }
            
            // No word found at this time
            lastLookupTime = time
            lastLookupResult = nil
            return nil
        }
        
        // GROK'S APPROACH: Sequential fast-forward (O(1) during sequential playback)
        // Fast-forward through words until we find the one containing the current time
        while currentWordArrayIndex < indexedWords.count - 1 {
            let nextWord = indexedWords[currentWordArrayIndex + 1]
            
            // Validate next word timing
            guard nextWord.start.isFinite && nextWord.end.isFinite && nextWord.start < nextWord.end else {
                // Invalid word - skip it
                currentWordArrayIndex += 1
                continue
            }
            
            // If time hasn't reached next word yet, stop fast-forwarding
            if time < nextWord.start {
                break
            }
            
            // Time has reached or passed next word - move forward
            currentWordArrayIndex += 1
        }
        
        // Check if current word contains the time
        let currentWord = indexedWords[currentWordArrayIndex]
        
        // Validate current word timing
        guard currentWord.start.isFinite && currentWord.end.isFinite && currentWord.start < currentWord.end else {
            // Invalid word - reset to beginning and return nil
            currentWordArrayIndex = 0
            lastLookupTime = time
            lastLookupResult = nil
            return nil
        }
        
        // Check if time is within current word's range
        if time >= currentWord.start && time < currentWord.end {
            lastLookupTime = time
            lastLookupResult = currentWord.id // Store original index
            return currentWord.id // Return original index
        }
        
        // Time is before current word - need to rewind (shouldn't happen often during playback)
        if time < currentWord.start {
            // Rewind to find correct word (fallback to binary search for seeks)
            var left = 0
            var right = currentWordArrayIndex
            var bestMatch: Int? = nil
            
            while left <= right {
                let mid = (left + right) / 2
                let word = indexedWords[mid]
                
                guard word.start.isFinite && word.end.isFinite && word.start < word.end else {
                    if time < word.start {
                        right = mid - 1
                    } else {
                        left = mid + 1
                    }
                    continue
                }
                
                if time >= word.start && time < word.end {
                    currentWordArrayIndex = mid
                    lastLookupTime = time
                    lastLookupResult = word.id
                    return word.id
                }
                
                if time < word.start {
                    right = mid - 1
                } else {
                    bestMatch = mid
                    left = mid + 1
                }
            }
            
            // Update currentWordArrayIndex to best match
            if let best = bestMatch {
                currentWordArrayIndex = best
            } else {
                currentWordArrayIndex = 0
            }
        }
        
        // No word found at this time
        lastLookupTime = time
        lastLookupResult = nil
        return nil
    }
    
    // MARK: - Get Word at Time within Sentence (for sentence-based gating)
    private func getWordAtTime(_ time: Double, withinSentence sentence: PrecomputedSentence) -> Int? {
        // Validate time is finite and positive
        guard time.isFinite, time >= 0 else { return nil }
        
        // Only search within this sentence's word indices
        // IMPORTANT: Find words by original index (id), not array position
        for wordIndex in sentence.globalWordIndices {
            // Find word by original index (id), not array position - use O(1) lookup
            guard let word = getWordByOriginalIndex(wordIndex) else {
                continue // Word was filtered out, skip it
            }
            
            // Validate word timing before using - skip invalid words
            guard word.start.isFinite && word.end.isFinite && word.start < word.end else {
                continue // Skip this word and try next
            }
            
            if time >= word.start && time < word.end {
                return wordIndex
            }
        }
        
        // No word found in this sentence
        return nil
    }
    
    // MARK: - Find Current Sentence
    private func findCurrentSentence(at time: Double) -> Int? {
        guard !sentences.isEmpty else { return nil }
        
        // Binary search for sentence
        var left = 0
        var right = sentences.count - 1
        
        while left <= right {
            let mid = (left + right) / 2
            let sentence = sentences[mid]
            
            if time >= sentence.startTime && time < sentence.endTime {
                return mid
            }
            
            if time < sentence.startTime {
                right = mid - 1
            } else {
                left = mid + 1
            }
        }
        
        // If we're past all sentences, return last sentence
        if time >= sentences.last?.endTime ?? 0 {
            return sentences.count - 1
        }
        
        // Before first sentence
        if time < sentences.first?.startTime ?? 0 {
            return nil
        }
        
        return nil
    }
    
    // MARK: - Validate Timing Data (silent validation)
    private func validateTimingData() {
        var issueCount = 0
        let maxIssuesToCheck = 10 // Only check first 10 issues to avoid spam
        
        for (i, word) in indexedWords.enumerated() {
            if issueCount >= maxIssuesToCheck { break }
            
            // Check 1: start < end
            if word.start >= word.end {
                issueCount += 1
                if issueCount == 1 {
                    print("⚠️ Timing data validation: Found issues (showing first few)")
                }
                if issueCount <= 3 {
                    print("  - Word \(i) '\(word.text)': start(\(word.start)) >= end(\(word.end))")
                }
            }
            
            // Check 2: Reasonable duration (not suspiciously long)
            let duration = word.end - word.start
            if duration > 5.0 {
                issueCount += 1
                if issueCount == 1 {
                    print("⚠️ Timing data validation: Found issues (showing first few)")
                }
                if issueCount <= 3 {
                    print("  - Word \(i) '\(word.text)': suspiciously long duration (\(String(format: "%.2f", duration))s)")
                }
            }
            
            // Check 3: Sequential ordering (no backward starts)
            if i > 0 {
                let prevWord = indexedWords[i-1]
                if word.start < prevWord.start {
                    issueCount += 1
                    if issueCount == 1 {
                        print("⚠️ Timing data validation: Found issues (showing first few)")
                    }
                    if issueCount <= 3 {
                        print("  - Word \(i) starts before previous word")
                    }
                }
            }
        }
        
        if issueCount > 0 {
            print("⚠️ Timing data has \(issueCount) issue(s) - synchronization may be affected")
        }
    }
    
    // MARK: - Set Audio Time Getter (for event-driven updates)
    func setAudioTimeGetter(_ getter: @escaping () -> Double) {
        audioTimeGetter = getter
    }
    
    // MARK: - Event-driven word update scheduling
    @MainActor
    func scheduleNextWordUpdate(from currentTime: Double) {
        // VALIDATE: Skip invalid time values
        guard currentTime.isFinite && currentTime >= 0 else {
            return
        }
        
        // Cancel existing timer
        wordUpdateTimer?.invalidate()
        wordUpdateTimer = nil
        
        // Find next valid word after current
        guard let currentOriginalIndex = currentWordIndex else { return }
        
        // Find current word's array position first - use O(1) lookup
        guard let currentArrayIndex = getArrayIndexForOriginalIndex(currentOriginalIndex) else {
            print("⚠️ KaraokeEngine: Current word at index \(currentOriginalIndex) not found in array")
            return
        }
        
        // Find next valid word (skip any invalid ones)
        var nextValidOriginalIndex: Int? = nil
        for i in (currentArrayIndex + 1)..<indexedWords.count {
            let word = indexedWords[i]
            // Validate word timing
            if word.start.isFinite && word.end.isFinite && word.start < word.end && word.start >= currentTime {
                nextValidOriginalIndex = word.id
                break
            }
        }
        
        guard let nextOriginalIndex = nextValidOriginalIndex,
              let nextWord = getWordByOriginalIndex(nextOriginalIndex) else { return }
        
        nextWordStartTime = nextWord.start
        let delay = max(0.01, nextWord.start - currentTime) // At least 10ms delay
        
        // Only schedule if delay is reasonable (not too far in future)
        guard delay < 10.0 else { return } // Don't schedule more than 10 seconds ahead
        
        // Schedule timer for exact word start time
        wordUpdateTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.checkAndUpdateWord()
            }
        }
    }
    
    @MainActor
    private func checkAndUpdateWord() {
        // Get current audio time
        guard let getTime = audioTimeGetter else { return }
        let currentTime = getTime()
        
        // Only update if we're past the expected word start time (timer precision check)
        // The audio observer handles regular updates, this is just a precision check
        if currentTime >= nextWordStartTime - 0.1 { // 100ms tolerance
            updateTime(currentTime, duration: 0) // Duration not needed for word sync
        }
    }
    
    // MARK: - Update from Audio Time (REAL-TIME: No throttling for word updates)
    @MainActor
    func updateTime(_ time: Double, duration: Double) {
        // VALIDATE: Skip invalid time values to prevent errors
        guard time.isFinite && time >= 0 else {
            return // Skip invalid time updates
        }
        
        // STEP 1: Search ALL words using sequential fast-forward (O(1) during playback)
        // AVPlayer's time observer calls this at ~30fps during playback for accurate word sync
        let candidateWordIndex = getWordAtTime(time)
        
        // STEP 2: Update word immediately if changed (NO THROTTLING - real-time)
        // Word updates must be immediate to match log timing
        if candidateWordIndex != lastPublishedWordIndex {
            // Word changed - update immediately
            if let candidate = candidateWordIndex {
                // Find word by original index (id), not array position - use O(1) lookup
                // Validate word exists (we don't need the word object, just validation)
                guard getWordByOriginalIndex(candidate) != nil else {
                    return
                }
                
                // Update word index IMMEDIATELY (triggers SwiftUI update)
                currentWordIndex = candidate
                lastPublishedWordIndex = candidate
                
                // Note: AVPlayer's time observer provides continuous updates during playback
            } else {
                // No word found - clear word highlight
                currentWordIndex = nil
                lastPublishedWordIndex = nil
            }
        }
        
        // STEP 2.5: Update lastSpokenWordIndex to track all completed words
        // This should be the last word whose end time has passed (all words up to this are "spoken")
        // This is separate from currentWordIndex which tracks the word currently being spoken
        // Use binary search to efficiently find the last word that has ended
        var newLastSpoken: Int? = nil
        
        // Binary search for the last word whose end time <= current time
        var left = 0
        var right = indexedWords.count - 1
        var bestMatch: Int? = nil
        
        while left <= right {
            let mid = (left + right) / 2
            let word = indexedWords[mid]
            
            // Validate word timing
            guard word.end.isFinite && word.start.isFinite && word.start < word.end else {
                // Invalid word - skip it
                if time < word.start {
                    right = mid - 1
                } else {
                    left = mid + 1
                }
                continue
            }
            
            if word.end <= time {
                // This word has ended - it's a candidate, but check if there's a later one
                bestMatch = word.id
                left = mid + 1 // Look for later words that might also have ended
            } else {
                // This word hasn't ended yet - look earlier
                right = mid - 1
            }
        }
        
        newLastSpoken = bestMatch
        
        // Only update if changed (prevents unnecessary SwiftUI updates)
        if newLastSpoken != lastSpokenWordIndex {
            lastSpokenWordIndex = newLastSpoken
        }
        
        // STEP 3: Throttle ONLY progress updates (not word updates)
        // Progress bar doesn't need to be real-time, but words do
        let now = CFAbsoluteTimeGetCurrent()
        if now - lastProgressUpdateTime >= progressUpdateInterval {
            if duration > 0 {
                progress = time / duration
            }
            lastProgressUpdateTime = now
        }
    }
    
    // MARK: - Load Pre-built Data (no rebuilding needed!)
    @MainActor
    func loadPrebuiltData(indexedWords: [IndexedWord], sentences: [PrecomputedSentence], totalWords: Int) {
        self.indexedWords = indexedWords
        self.sentences = sentences
        self.totalWords = totalWords
        
        // Build O(1) lookup dictionary
        wordIdToArrayIndex.removeAll()
        for (arrayIndex, word) in indexedWords.enumerated() {
            wordIdToArrayIndex[word.id] = arrayIndex
        }
        
        self.isReady = true
        print("✅ KaraokeEngine: Loaded \(totalWords) pre-indexed words instantly")
        
        // Note: Word sync updates come from AVPlayer's time observer (~30fps) for accurate audio timing
    }
    
    // MARK: - O(1) Word Lookup Helper
    private func getWordByOriginalIndex(_ originalIndex: Int) -> IndexedWord? {
        guard let arrayIndex = wordIdToArrayIndex[originalIndex],
              arrayIndex < indexedWords.count else {
            return nil
        }
        return indexedWords[arrayIndex]
    }
    
    // MARK: - O(1) Array Index Lookup Helper
    private func getArrayIndexForOriginalIndex(_ originalIndex: Int) -> Int? {
        return wordIdToArrayIndex[originalIndex]
    }
    
    // MARK: - Accessors
    func getSentences() -> [PrecomputedSentence] {
        return sentences
    }
    
    func getIndexedWords() -> [IndexedWord] {
        return indexedWords
    }
    
    func getWord(at index: Int) -> IndexedWord? {
        guard index >= 0 && index < indexedWords.count else { return nil }
        return indexedWords[index]
    }
    
    func getTotalWords() -> Int {
        return totalWords
    }
    
    // MARK: - Reset
    func reset() {
        // Cancel all timers
        wordUpdateTimer?.invalidate()
        wordUpdateTimer = nil
        
        currentWordIndex = nil
        lastSpokenWordIndex = nil
        lastPublishedWordIndex = nil
        currentSentenceIndex = nil
        lastLookupTime = -1
        lastLookupResult = nil
        currentWordArrayIndex = 0 // Reset to beginning for sequential fast-forward
        lastProgressUpdateTime = -1
        nextWordStartTime = 0
        progress = 0
        // Note: Don't clear wordIdToArrayIndex - it's still valid after reset
    }
    
    // MARK: - Reset Search State (for large jumps)
    /// Resets only the internal search state to force binary search instead of sequential fast-forward
    /// Use this when making large time jumps (e.g., scrubbing) to avoid slow sequential search
    func resetSearchState() {
        lastLookupTime = -1
        lastLookupResult = nil
        currentWordArrayIndex = 0 // Reset to force binary search path
    }
}

