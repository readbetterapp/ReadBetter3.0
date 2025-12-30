/**
 * Word Timing Estimator
 * Replicates estimateTimingForUnalignedWords() from TranscriptService.swift
 * 
 * CRITICAL: This must preserve original JSON indices and search in original JSON order
 */

/**
 * Estimate timing for words without timing data (start < 0)
 * This replicates the exact logic from TranscriptService.swift lines 395-516
 * 
 * @param {Array} words - Array of word objects with {text, start, end, index, hasLineBreak}
 * @returns {Array} - Updated words array with estimated timing
 */
function estimateTimingForUnalignedWords(words) {
  // Find all words that need timing estimation (start < 0)
  const wordsNeedingEstimation = words
    .map((word, sortedIndex) => ({ word, sortedIndex }))
    .filter(({ word }) => word.start < 0);

  if (wordsNeedingEstimation.length === 0) {
    return words;
  }

  console.log(`📊 Estimating timing for ${wordsNeedingEstimation.length} unaligned words`);

  // Create a map: original JSON index -> sorted array index
  // This allows us to find words by their original JSON position even after sorting
  const sortedIndexByJsonIndex = new Map();
  words.forEach((word, sortedIndex) => {
    sortedIndexByJsonIndex.set(word.index, sortedIndex);
  });

  // Process each word needing estimation
  for (const { word, sortedIndex } of wordsNeedingEstimation) {
    const originalJsonIndex = word.index; // This is the REAL original JSON position
    let estimatedStart = 0;
    let estimatedEnd = 0;

    // Find previous word with valid timing IN ORIGINAL JSON ORDER
    // We search by original JSON index, then look up its sorted position
    let prevWord = null;
    let prevSortedIndex = null;
    for (let j = originalJsonIndex - 1; j >= 0; j--) {
      const candidateSortedIdx = sortedIndexByJsonIndex.get(j);
      if (candidateSortedIdx !== undefined && 
          candidateSortedIdx < words.length &&
          words[candidateSortedIdx].start >= 0 && 
          words[candidateSortedIdx].end > words[candidateSortedIdx].start) {
        prevWord = words[candidateSortedIdx];
        prevSortedIndex = candidateSortedIdx;
        break;
      }
    }

    // Find next word with valid timing IN ORIGINAL JSON ORDER
    let nextWord = null;
    let nextSortedIndex = null;
    const maxJsonIndex = Math.max(...words.map(w => w.index), originalJsonIndex);
    if (originalJsonIndex + 1 <= maxJsonIndex) {
      for (let j = originalJsonIndex + 1; j <= maxJsonIndex; j++) {
        const candidateSortedIdx = sortedIndexByJsonIndex.get(j);
        if (candidateSortedIdx !== undefined &&
            candidateSortedIdx < words.length &&
            words[candidateSortedIdx].start >= 0 &&
            words[candidateSortedIdx].end > words[candidateSortedIdx].start) {
          nextWord = words[candidateSortedIdx];
          nextSortedIndex = candidateSortedIdx;
          break;
        }
      }
    }

    // Estimate timing based on surrounding words
    if (prevWord && nextWord && prevSortedIndex !== null && nextSortedIndex !== null) {
      // Interpolate between previous and next word
      const timeGap = nextWord.start - prevWord.end;

      // Ensure we have a positive gap (if words overlap, use minimum gap)
      const safeTimeGap = Math.max(0.05, timeGap); // Minimum 50ms gap

      // Count how many words need estimation in this gap (in original JSON order)
      let wordsNeedingEstimationInGap = 0;
      for (let j = prevWord.index + 1; j < nextWord.index; j++) {
        const candidateSortedIdx = sortedIndexByJsonIndex.get(j);
        if (candidateSortedIdx !== undefined &&
            candidateSortedIdx < words.length &&
            words[candidateSortedIdx].start < 0) {
          wordsNeedingEstimationInGap += 1;
        }
      }
      const totalWordsInGap = Math.max(1, wordsNeedingEstimationInGap);

      // Distribute time evenly, but make each word VERY SHORT to prevent lag
      const timePerWord = safeTimeGap / (totalWordsInGap + 1);
      const positionInGap = originalJsonIndex - prevWord.index - 1;

      estimatedStart = prevWord.end + (timePerWord * (positionInGap + 1));

      // KEY FIX: Make estimated words VERY SHORT (50-100ms max) to prevent lag
      // This ensures they don't linger and cause timing issues
      const estimatedDuration = Math.min(0.1, timePerWord * 0.3); // Max 100ms, or 30% of gap
      estimatedEnd = estimatedStart + estimatedDuration;

      // Ensure end doesn't exceed next word's start (with safety margin)
      estimatedEnd = Math.min(estimatedEnd, nextWord.start - 0.02); // 20ms safety margin
      estimatedStart = Math.min(estimatedStart, estimatedEnd - 0.05); // Ensure at least 50ms duration

      // Final validation: ensure start < end
      if (estimatedStart >= estimatedEnd) {
        estimatedEnd = estimatedStart + 0.05; // Minimum 50ms duration
      }
    } else if (prevWord) {
      // Only previous word - estimate with SHORT duration to prevent lag
      estimatedStart = Math.max(prevWord.end, prevWord.end + 0.05); // At least 50ms gap
      estimatedEnd = estimatedStart + 0.1; // 100ms duration (short to prevent lag)
    } else if (nextWord) {
      // Only next word - estimate backwards with SHORT duration
      estimatedEnd = Math.max(0.1, nextWord.start - 0.05); // At least 50ms before next
      estimatedStart = Math.max(0, estimatedEnd - 0.1); // 100ms duration (short to prevent lag)
    } else {
      // No timing at all - use defaults (shouldn't happen, but handle it)
      estimatedStart = 0.0;
      estimatedEnd = 0.1; // Short duration even for defaults
    }

    // Final validation: ensure values are valid
    if (!(estimatedStart >= 0 && estimatedEnd > estimatedStart && 
          isFinite(estimatedStart) && isFinite(estimatedEnd))) {
      // Fallback to safe defaults with SHORT duration
      console.warn(`⚠️ Invalid estimated timing for word '${word.text}' at JSON index ${originalJsonIndex}, using safe defaults`);
      estimatedStart = Math.max(0, (prevWord?.end || 0) + 0.05);
      estimatedEnd = estimatedStart + 0.1; // Short duration to prevent lag
    }

    // Update word with estimated timing (use sortedIndex to update the correct position in the sorted array)
    // CRITICAL: Preserve original JSON index
    words[sortedIndex] = {
      text: word.text,
      start: estimatedStart,
      end: estimatedEnd,
      index: word.index, // Preserve original JSON index
      hasLineBreak: word.hasLineBreak
    };
  }

  console.log(`✅ Completed timing estimation`);
  return words;
}

module.exports = {
  estimateTimingForUnalignedWords
};
















