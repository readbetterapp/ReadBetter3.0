/**
 * Transcript Parser
 * Replicates parseTranscript() from TranscriptService.swift
 * 
 * CRITICAL: This must produce the EXACT same output structure as TranscriptService
 * to ensure OptimizedReaderView and KaraokeEngine work without changes
 */

const { estimateTimingForUnalignedWords } = require('./wordTimingEstimator');

/**
 * Normalize word for comparison (remove punctuation, lowercase)
 * Replicates normalizeWord() from TranscriptService.swift line 173
 */
function normalizeWord(word) {
  return word.toLowerCase()
    .replace(/[^\w\s]/g, '') // Remove punctuation
    .trim();
}

/**
 * Check if two normalized words match (handles contractions, etc.)
 * Replicates wordsMatch() from TranscriptService.swift line 180
 */
function wordsMatch(word1, word2) {
  const norm1 = normalizeWord(word1);
  const norm2 = normalizeWord(word2);

  // Exact match
  if (norm1 === norm2) return true;

  // One contains the other (handles "don't" vs "don", "I'm" vs "I")
  if (norm1 && norm2) {
    if (norm1.includes(norm2) || norm2.includes(norm1)) {
      // Only allow if the difference is small (handles contractions)
      const diff = Math.abs(norm1.length - norm2.length);
      if (diff <= 3) return true;
    }
  }

  return false;
}

/**
 * Extract word from JSON object (handles multiple formats)
 * Replicates WordTiming.init(from:json, index:) logic
 */
function extractWordFromJson(wordJson, originalIndex) {
  // FILTER 1: Skip words not found in transcript (filler words like "uh", "um")
  if (wordJson.case === 'not-found-in-transcript') {
    return null;
  }

  // Extract text from various possible fields
  const rawText = wordJson.word || 
                  wordJson.text || 
                  wordJson.alignedWord || 
                  wordJson.value || 
                  wordJson.token || 
                  '';

  if (!rawText || rawText === '<unk>') {
    return null;
  }

  // Check for line breaks
  const hasLineBreak = rawText.includes('\r\n') || 
                       rawText.includes('\n\n') || 
                       rawText.includes('\r') ||
                       rawText.includes('\n') ||
                       rawText === '\\r\\n' ||
                       rawText === '\\n\\n' ||
                       rawText === '\\r' ||
                       rawText === '\\n';

  // Clean text but preserve punctuation and spaces
  let cleanedText = rawText
    .replace(/\r\n/g, ' ')
    .replace(/\n\n/g, ' ')
    .replace(/\r/g, ' ')
    .replace(/\n/g, ' ')
    .replace(/\\r\\n/g, ' ')
    .replace(/\\n\\n/g, ' ')
    .replace(/\\r/g, ' ')
    .replace(/\\n/g, ' ')
    .trim();

  // FILTER 2: Skip punctuation-only tokens (no alphanumeric characters)
  if (!cleanedText) return null;

  // Check if text contains at least one alphanumeric character
  const hasAlphanumeric = /[a-zA-Z0-9]/.test(cleanedText);
  if (!hasAlphanumeric) {
    // This is punctuation-only (like ",", ".", "!", "?", etc.)
    return null;
  }

  // Extract start time
  let start = -1.0;
  if (typeof wordJson.start === 'number') {
    start = wordJson.start;
  } else if (typeof wordJson.startTime === 'number') {
    start = wordJson.startTime;
  } else if (typeof wordJson.begin === 'number') {
    start = wordJson.begin;
  } else if (typeof wordJson.start === 'string') {
    const parsed = parseFloat(wordJson.start);
    if (!isNaN(parsed)) start = parsed;
  }

  // Extract end time
  let end = -1.0;
  if (typeof wordJson.end === 'number') {
    end = wordJson.end;
  } else if (typeof wordJson.endTime === 'number') {
    end = wordJson.endTime;
  } else if (typeof wordJson.finish === 'number') {
    end = wordJson.finish;
  } else if (typeof wordJson.end === 'string') {
    const parsed = parseFloat(wordJson.end);
    if (!isNaN(parsed)) end = parsed;
  }

  // CRITICAL: DO NOT filter out words with case: "not-found-in-audio"
  // These words have start < 0 and will be estimated later

  return {
    text: cleanedText,
    start: start,
    end: end,
    index: originalIndex, // CRITICAL: Preserve original JSON array index
    hasLineBreak: hasLineBreak
  };
}

/**
 * Parse transcript JSON - replicates TranscriptService.parseTranscript() EXACTLY
 * 
 * @param {Object} json - Raw transcript JSON from GCS
 * @returns {Object} - TranscriptData structure matching Swift TranscriptData
 */
function parseTranscript(json) {
  // STEP 1: Get the full transcript text (authoritative source for display)
  const transcriptText = json.transcript || json.text || '';

  if (!transcriptText) {
    throw new Error('No transcript text found in JSON');
  }

  // STEP 2: Extract words with timing data
  let words = [];
  let wordCounter = 0;

  // Try flat words array first (most common format)
  if (Array.isArray(json.words) && json.words.length > 0) {
    if (typeof json.words[0] === 'object' && json.words[0] !== null) {
      // Array of objects
      for (const wordJson of json.words) {
        const word = extractWordFromJson(wordJson, wordCounter);
        if (word) {
          words.push(word);
          wordCounter += 1;
        }
      }
    }
  }
  // Try sentences structure
  else if (Array.isArray(json.sentences)) {
    for (const sentence of json.sentences) {
      if (Array.isArray(sentence.words)) {
        for (const wordJson of sentence.words) {
          const word = extractWordFromJson(wordJson, wordCounter);
          if (word) {
            words.push(word);
            wordCounter += 1;
          }
        }
      }
    }
  }

  if (words.length === 0) {
    throw new Error('No words found in transcript');
  }

  // Sort words by start time (words with -1 will be at the end initially)
  words.sort((word1, word2) => {
    // Words with valid timing first, sorted by time
    if (word1.start >= 0 && word2.start >= 0) {
      return word1.start - word2.start;
    } else if (word1.start >= 0) {
      return -1; // word1 has timing, word2 doesn't
    } else if (word2.start >= 0) {
      return 1; // word2 has timing, word1 doesn't
    } else {
      // Both need estimation - keep original order
      return word1.index - word2.index;
    }
  });

  // STEP 2.5: Estimate timing for words without timing data ("not-found-in-audio")
  words = estimateTimingForUnalignedWords(words);

  // Re-sort after estimation (all should have valid timing now)
  // IMPORTANT: We sort by time for lookup efficiency, but preserve original indices
  words.sort((a, b) => a.start - b.start);

  // DO NOT re-index! Preserve original JSON indices for sentence matching
  // The index represents the position in the original JSON array, not the sorted position

  console.log(`📊 Found ${words.length} timed words`);

  // STEP 3: Split transcript by \r\n\r\n to get sentences
  const sentenceTexts = transcriptText
    .split('\r\n\r\n')
    .map(s => s.trim())
    .filter(s => s.length > 0);

  console.log(`📊 Found ${sentenceTexts.length} sentences`);

  // STEP 4: Match words to sentences by hybrid time-based + text matching
  // This replicates the complex matching logic from TranscriptService.swift lines 199-353

  const sentences = [];
  let currentWordIndex = 0;

  // TIME-BASED MATCHING: More robust approach
  // First, estimate word distribution across sentences based on word count
  const sentenceWordCounts = sentenceTexts.map(sentenceText => {
    return sentenceText.split(/\s+/).filter(w => w.length > 0).length;
  });

  const totalExpectedWords = sentenceWordCounts.reduce((sum, count) => sum + count, 0);

  // Calculate approximate time ranges for each sentence based on word distribution
  const sentenceTimeRanges = [];
  let wordsAssigned = 0;

  for (const wordCount of sentenceWordCounts) {
    const wordStartIndex = wordsAssigned;
    const wordEndIndex = Math.min(wordsAssigned + wordCount, words.length);

    // Get time range from actual word timings
    const timeStart = wordStartIndex < words.length ? words[wordStartIndex].start : 0;
    const timeEnd = wordEndIndex > 0 && wordEndIndex <= words.length 
      ? words[wordEndIndex - 1].end 
      : (words.length > 0 ? words[words.length - 1].end : 0);

    sentenceTimeRanges.push({
      start: timeStart,
      end: timeEnd,
      wordStartIndex: wordStartIndex,
      wordEndIndex: wordEndIndex
    });
    wordsAssigned = wordEndIndex;
  }

  // Now assign words to sentences using hybrid approach: time-based with text validation
  for (let sentenceIndex = 0; sentenceIndex < sentenceTexts.length; sentenceIndex++) {
    const sentenceText = sentenceTexts[sentenceIndex];
    let sentenceWordIndices = [];
    let sentenceStartTime = Infinity;
    let sentenceEndTime = 0;

    const timeRange = sentenceTimeRanges[sentenceIndex];
    const expectedWordCount = sentenceWordCounts[sentenceIndex];

    // Strategy 1: Assign words based on time range (primary method)
    const candidateIndices = [];
    for (let wordIndex = 0; wordIndex < words.length; wordIndex++) {
      const word = words[wordIndex];
      // Word belongs to this sentence if its timing overlaps with sentence time range
      // Use generous overlap: word starts before sentence ends OR word ends after sentence starts
      if (word.start < timeRange.end + 0.5 && word.end > timeRange.start - 0.5) {
        candidateIndices.push(wordIndex);
      }
    }

    // Strategy 2: If we have too few candidates, use sequential assignment
    let finalCandidateIndices = candidateIndices;
    if (candidateIndices.length < expectedWordCount * 0.5) {
      // Fall back to sequential assignment based on word position
      const startIdx = timeRange.wordStartIndex;
      const endIdx = Math.min(timeRange.wordEndIndex, words.length);
      finalCandidateIndices = Array.from({ length: endIdx - startIdx }, (_, i) => startIdx + i);
    }

    // Strategy 3: Try to match by text for better accuracy (optional validation)
    const sentenceWords = sentenceText.split(/\s+/).filter(w => w.length > 0);

    // If we have candidates, try to refine the match using text
    if (finalCandidateIndices.length > 0 && finalCandidateIndices.length <= expectedWordCount * 2) {
      const matchedIndices = [];
      let searchStart = finalCandidateIndices[0] || currentWordIndex;

      for (const sentenceWord of sentenceWords) {
        const normalizedSentenceWord = normalizeWord(sentenceWord);
        if (!normalizedSentenceWord) continue;

        // Search in candidate range with wider window
        const searchEnd = Math.min(searchStart + 15, words.length);
        let bestMatch = null;
        let bestScore = 0;

        for (let i = searchStart; i < searchEnd; i++) {
          // Only consider words in candidate list
          if (!finalCandidateIndices.includes(i) && finalCandidateIndices.length > expectedWordCount) {
            continue;
          }

          const timingWord = words[i];
          const normalizedTimingWord = normalizeWord(timingWord.text);

          // Calculate match score
          let score = 0;

          // Exact match = highest score
          if (normalizedSentenceWord === normalizedTimingWord) {
            score = 100.0;
          }
          // Contains match = medium score
          else if (normalizedSentenceWord.includes(normalizedTimingWord) || 
                   normalizedTimingWord.includes(normalizedSentenceWord)) {
            score = 50.0;
          }
          // Similar length = low score
          else if (Math.abs(normalizedSentenceWord.length - normalizedTimingWord.length) <= 2) {
            const set1 = new Set(normalizedSentenceWord.split(''));
            const set2 = new Set(normalizedTimingWord.split(''));
            const commonChars = [...set1].filter(x => set2.has(x)).length;
            score = (commonChars / Math.max(normalizedSentenceWord.length, normalizedTimingWord.length)) * 30.0;
          }

          // Prefer words closer to expected position
          const positionBonus = Math.max(0, 10.0 - (i - searchStart));
          score += positionBonus;

          if (score > 0 && (bestMatch === null || score > bestScore)) {
            bestMatch = i;
            bestScore = score;
          }
        }

        // Use best match if score is reasonable, otherwise use sequential
        if (bestMatch !== null && bestScore >= 20.0) {
          matchedIndices.push(bestMatch);
          searchStart = bestMatch + 1;
        } else {
          // Use sequential assignment if no good match
          if (searchStart < words.length && !matchedIndices.includes(searchStart)) {
            matchedIndices.push(searchStart);
            searchStart += 1;
          }
        }
      }

      sentenceWordIndices = matchedIndices.length > 0 ? matchedIndices : finalCandidateIndices;
    } else {
      // Too many candidates or no candidates - use sequential assignment
      sentenceWordIndices = finalCandidateIndices.length === 0
        ? Array.from({ length: Math.min(timeRange.wordEndIndex, words.length) - timeRange.wordStartIndex }, 
                     (_, i) => timeRange.wordStartIndex + i)
        : finalCandidateIndices.slice(0, expectedWordCount * 2).sort((a, b) => a - b);
    }

    // Remove duplicates and sort
    sentenceWordIndices = [...new Set(sentenceWordIndices)].sort((a, b) => a - b);

    // Calculate sentence timing from assigned words
    // CRITICAL: sentenceWordIndices contains array indices, we need to convert to original JSON indices
    let originalJsonIndices = [];
    if (sentenceWordIndices.length > 0) {
      // Find words by their array indices and get their original JSON indices
      const wordObjects = sentenceWordIndices.map(idx => words[idx]).filter(w => w);
      if (wordObjects.length > 0) {
        sentenceStartTime = wordObjects[0].start;
        sentenceEndTime = wordObjects[wordObjects.length - 1].end;
        
        // Convert array indices to original JSON indices for sentence wordIndices
        originalJsonIndices = wordObjects.map(w => w.index);
      } else {
        sentenceStartTime = timeRange.start;
        sentenceEndTime = timeRange.end;
      }
    } else {
      sentenceStartTime = timeRange.start;
      sentenceEndTime = timeRange.end;
    }

    // Update currentWordIndex for next sentence (using original JSON indices)
    if (originalJsonIndices.length > 0) {
      const maxOriginalIndex = Math.max(...originalJsonIndices);
      currentWordIndex = Math.max(currentWordIndex, maxOriginalIndex + 1);
    }

    // Create sentence with matched word indices (using original JSON indices)
    sentences.push({
      text: sentenceText,
      wordIndices: originalJsonIndices, // CRITICAL: Original JSON indices
      startTime: sentenceStartTime,
      endTime: sentenceEndTime
    });
  }

  // Handle any remaining timing words (assign to last sentence)
  // Find the maximum original JSON index that we've processed
  const maxProcessedIndex = Math.max(...sentences.flatMap(s => s.wordIndices), -1);
  const allOriginalIndices = new Set(words.map(w => w.index));
  const remainingIndices = [...allOriginalIndices].filter(idx => idx > maxProcessedIndex);
  
  if (remainingIndices.length > 0) {
    console.log(`📊 ${remainingIndices.length} timing words remaining, assigning to last sentence`);

    // Add remaining words to last sentence
    if (sentences.length > 0) {
      const lastSentence = sentences[sentences.length - 1];
      const updatedIndices = [...lastSentence.wordIndices];
      let lastEndTime = lastSentence.endTime;

      // Find remaining words by their original JSON indices
      for (const originalJsonIndex of remainingIndices) {
        // Find word with this original JSON index
        const word = words.find(w => w.index === originalJsonIndex);
        if (word && !updatedIndices.includes(originalJsonIndex)) {
          updatedIndices.push(originalJsonIndex);
          lastEndTime = Math.max(lastEndTime, word.end);
        }
      }

      sentences[sentences.length - 1] = {
        text: lastSentence.text,
        wordIndices: updatedIndices.sort((a, b) => a - b),
        startTime: lastSentence.startTime,
        endTime: lastEndTime
      };
    }
  }

  const matchedWords = sentences.reduce((sum, s) => sum + s.wordIndices.length, 0);
  console.log(`✅ Matched ${matchedWords} of ${words.length} timing words to ${sentences.length} sentences`);

  // Return structure matching TranscriptData
  return {
    fullText: transcriptText,
    sentences: sentences,
    words: words.map(w => ({
      text: w.text,
      start: w.start,
      end: w.end,
      index: w.index, // CRITICAL: Original JSON index
      hasLineBreak: w.hasLineBreak
    }))
  };
}

module.exports = {
  parseTranscript
};

