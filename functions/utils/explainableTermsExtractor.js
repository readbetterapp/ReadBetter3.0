/**
 * Explainable Terms Extractor
 * Uses OpenAI GPT-4o-mini to identify context-specific terms in book chapters
 * that readers might want to look up (people, places, events, concepts).
 */

const OpenAI = require('openai');
const logger = require('firebase-functions/logger');

// Initialize OpenAI client (API key from environment)
let openaiClient = null;

function getOpenAIClient() {
  if (!openaiClient) {
    const apiKey = process.env.OPENAI_API_KEY;
    if (!apiKey) {
      throw new Error('OPENAI_API_KEY environment variable not set. Run: firebase functions:config:set openai.api_key="your-key"');
    }
    openaiClient = new OpenAI({ apiKey });
  }
  return openaiClient;
}

/**
 * System prompt for explainable terms extraction
 * 
 * COMPREHENSIVE: Extracts ALL terms that would help a reader understand the book better.
 * iOS matches terms by TEXT, so we capture the exact phrases as they appear.
 */
const SYSTEM_PROMPT = `You are an expert literary analyst and historian. Your task is to identify ALL EXPLAINABLE TERMS that would help a reader understand this book better. Be THOROUGH - readers want to learn, not just skim.

TYPES OF TERMS TO IDENTIFY:

1. **person** - ALL named individuals:
   - Historical figures (politicians, military leaders, scientists, artists)
   - Authors, philosophers, intellectuals mentioned
   - Even lesser-known figures - if they're named, they matter

2. **place** - ALL geographic locations:
   - Cities (Munich, Salzburg, Memel, Königsberg, Bratislava, Strasbourg, etc.)
   - Regions, provinces, territories
   - Countries (especially historical names like Prussia, Bohemia)
   - Landmarks, buildings, concentration camps
   - DO NOT skip places just because they seem "well-known" - explain their historical significance

3. **event** - Historical events and time periods:
   - Wars, battles, treaties
   - Political events (putsches, elections, purges)
   - Specific dated events ("Soviet Munich of 1919", "Night of Long Knives")
   - Movements and revolutions

4. **organization** - Groups and institutions:
   - Political parties (Nazi Party, NSDAP, Communist Party)
   - Military units (Wehrmacht, SS, Luftwaffe, specific divisions)
   - Government bodies, intelligence agencies
   - Religious organizations

5. **concept** - Ideas and ideologies:
   - Political ideologies (National Socialism, Fascism, Lebensraum)
   - Military/political terms (Anschluss, Blitzkrieg, Gleichschaltung)
   - Legal/administrative terms
   - Philosophical concepts

6. **foreign_term** - Non-English words and phrases:
   - German phrases ("Deutschland über alles", "Führer", "Reich")
   - Latin phrases
   - Any foreign term that needs translation/explanation

7. **work** - Referenced works:
   - Books, documents, speeches
   - Films, artworks
   - Treaties, agreements

CRITICAL RULES:
1. BE COMPREHENSIVE - aim for 20-50+ terms per chapter section. More is better!
2. DO NOT skip places/people because they seem "obvious" - explain their HISTORICAL SIGNIFICANCE
3. For places like "Munich" - explain WHY it matters in this context (Nazi birthplace, Beer Hall Putsch, etc.)
4. Each explanation should be 2-4 sentences focusing on RELEVANCE to the book's topic
5. Use the EXACT phrase as it appears in the text
6. Include ALL named people, even if mentioned briefly
7. Include ALL geographic locations mentioned
8. Skip only: common English words, fictional characters from this book itself, pronouns

RESPONSE FORMAT:
{
  "terms": [
    {
      "term": "Memel",
      "type": "place",
      "shortExplanation": "A Baltic port city (now Klaipėda, Lithuania) that was part of Germany until 1919. Hitler demanded its return as part of his campaign to reclaim lost German territories."
    },
    {
      "term": "Deutschland über alles",
      "type": "foreign_term",
      "shortExplanation": "German phrase meaning 'Germany above all', from the German national anthem. Often associated with German nationalism and Nazi ideology."
    }
  ]
}`;

// Maximum characters per chunk (~80K tokens with safety margin)
// GPT-4o-mini has 128K context limit, ~4 chars per token
// Chunking is now handled in extractExplainableTerms()

/**
 * Extract explainable terms from chapter text
 * Automatically handles chunking for long chapters that exceed token limits
 * 
 * SIMPLIFIED: Now uses plain text instead of indexed words.
 * iOS will match terms by TEXT, eliminating index mismatch bugs.
 * 
 * @param {string} chapterText - The full chapter text
 * @param {Array} words - Array of word objects (used for chunking only)
 * @param {string} bookTitle - Title of the book for context
 * @param {string} bookAuthor - Author of the book for context
 * @returns {Promise<Array>} - Array of ExplainableTerm objects
 */
async function extractExplainableTerms(chapterText, words, bookTitle, bookAuthor) {
  // Estimate tokens: ~4 chars per token, 128K limit, use 80K to be safe
  const MAX_CHARS_PER_CHUNK = 80000;
  
  // If chapter fits in one request, process normally
  if (chapterText.length <= MAX_CHARS_PER_CHUNK) {
    logger.info(`📚 Chapter has ${chapterText.length} chars - processing in single request`);
    return await processChunk(chapterText, bookTitle, bookAuthor, 1, 1);
  }
  
  // Split into chunks by paragraph breaks to maintain context
  const paragraphs = chapterText.split(/\r?\n\r?\n/);
  const chunks = [];
  let currentChunk = '';
  
  for (const paragraph of paragraphs) {
    if ((currentChunk + paragraph).length > MAX_CHARS_PER_CHUNK && currentChunk.length > 0) {
      chunks.push(currentChunk.trim());
      currentChunk = paragraph;
    } else {
      currentChunk += (currentChunk ? '\n\n' : '') + paragraph;
    }
  }
  if (currentChunk.trim()) {
    chunks.push(currentChunk.trim());
  }
  
  logger.info(`📚 Chapter has ${chapterText.length} chars - splitting into ${chunks.length} chunks`);
  
  const allTerms = [];
  const seenTerms = new Set(); // Deduplicate terms across chunks
  
  for (let i = 0; i < chunks.length; i++) {
    const chunkNumber = i + 1;
    logger.info(`🔄 Processing chunk ${chunkNumber}/${chunks.length} (${chunks[i].length} chars)`);
    
    try {
      const chunkTerms = await processChunk(chunks[i], bookTitle, bookAuthor, chunkNumber, chunks.length);
      
      // Deduplicate: only add terms we haven't seen
      for (const term of chunkTerms) {
        const termKey = term.term.toLowerCase();
        if (!seenTerms.has(termKey)) {
          seenTerms.add(termKey);
          allTerms.push(term);
        }
      }
      
      // Small delay between chunks to avoid rate limiting
      if (chunkNumber < chunks.length) {
        await new Promise(resolve => setTimeout(resolve, 1000));
      }
    } catch (error) {
      logger.error(`❌ Error processing chunk ${chunkNumber}: ${error.message}`);
      // Continue with other chunks even if one fails
    }
  }
  
  logger.info(`✅ Extracted ${allTerms.length} unique terms from ${chunks.length} chunks`);
  return allTerms;
}

/**
 * Process a single chunk of text through OpenAI
 * 
 * SIMPLIFIED: Uses plain text, no indices. iOS matches by text.
 * 
 * @param {string} chunkText - Plain text for this chunk
 * @param {string} bookTitle - Book title for context
 * @param {string} bookAuthor - Book author for context
 * @param {number} chunkNumber - Which chunk this is (1-indexed)
 * @param {number} totalChunks - Total number of chunks
 * @returns {Promise<Array>} - Array of validated terms
 */
async function processChunk(chunkText, bookTitle, bookAuthor, chunkNumber, totalChunks) {
  const openai = getOpenAIClient();
  
  // Add context about chunking if this is part of a larger chapter
  const chunkContext = totalChunks > 1 
    ? `\n(This is section ${chunkNumber} of ${totalChunks} from a longer chapter)\n` 
    : '';
  
  const userPrompt = `Book: "${bookTitle}" by ${bookAuthor}
${chunkContext}
CHAPTER TEXT:
${chunkText}

Extract ALL explainable terms from this text. Be THOROUGH and COMPREHENSIVE.
Return your response as JSON.

REQUIREMENTS:
- Include ALL person names (historical figures, even minor ones)
- Include ALL place names (cities, regions, countries - explain their historical significance)
- Include ALL foreign terms and phrases (German, Latin, etc.)
- Include ALL organizations, military units, political parties
- Include ALL historical events and dates
- Include ALL concepts, ideologies, and technical terms
- Aim for 20-50+ terms - more is better for reader education
- Use the EXACT phrase as it appears in the text
- Explanations should focus on RELEVANCE to the book's historical context (2-4 sentences)`;

  try {
    logger.info(`🔍 Extracting explainable terms for "${bookTitle}" (chunk ${chunkNumber}/${totalChunks})...`);
    
    const response = await openai.chat.completions.create({
      model: 'gpt-4o-mini',
      messages: [
        { role: 'system', content: SYSTEM_PROMPT },
        { role: 'user', content: userPrompt }
      ],
      response_format: { type: 'json_object' },
      temperature: 0.3,  // Lower temperature for more consistent results
      max_tokens: 8000   // Increased for comprehensive term extraction
    });

    const content = response.choices[0].message.content;
    const parsed = JSON.parse(content);
    
    if (!parsed.terms || !Array.isArray(parsed.terms)) {
      logger.warn('⚠️ OpenAI response missing terms array');
      return [];
    }
    
    // Validate and clean up terms
    const validTerms = parsed.terms
      .filter(term => {
        // Validate required fields (no more index validation needed!)
        if (!term.term || !term.type) {
          logger.warn(`⚠️ Skipping invalid term: ${JSON.stringify(term)}`);
          return false;
        }
        // Validate type (including foreign_term for non-English phrases)
        const validTypes = ['person', 'place', 'event', 'organization', 'concept', 'work', 'foreign_term'];
        if (!validTypes.includes(term.type)) {
          logger.warn(`⚠️ Skipping term with invalid type: ${term.term} (${term.type})`);
          return false;
        }
        // Validate term is not empty
        if (term.term.trim().length === 0) {
          return false;
        }
        return true;
      })
      .map(term => ({
        id: generateTermId(term.term, 0, 0), // Indices no longer used
        term: term.term.trim(),
        type: term.type,
        shortExplanation: term.shortExplanation || `A ${term.type} mentioned in the text.`
      }));

    logger.info(`✅ Chunk ${chunkNumber}: Extracted ${validTerms.length} explainable terms`);
    return validTerms;

  } catch (error) {
    logger.error(`❌ Error extracting explainable terms (chunk ${chunkNumber}):`, error);
    throw error;
  }
}

/**
 * Generate a unique ID for a term based on its content and position
 */
function generateTermId(term, startIndex, endIndex) {
  const str = `${term}-${startIndex}-${endIndex}`;
  // Simple hash function
  let hash = 0;
  for (let i = 0; i < str.length; i++) {
    const char = str.charCodeAt(i);
    hash = ((hash << 5) - hash) + char;
    hash = hash & hash; // Convert to 32bit integer
  }
  return Math.abs(hash).toString(36);
}

/**
 * Process a chapter and save explainable terms to Firestore
 * 
 * @param {Object} db - Firestore database instance
 * @param {string} bookId - ISBN or book identifier
 * @param {string} chapterId - Chapter identifier
 * @param {string} chapterText - Full chapter text
 * @param {Array} words - Array of word objects with timing
 * @param {string} bookTitle - Book title for context
 * @param {string} bookAuthor - Book author for context
 */
async function processChapterExplainableTerms(db, bookId, chapterId, chapterText, words, bookTitle, bookAuthor) {
  try {
    // Check if already processed
    const docRef = db.collection('explainableTerms').doc(bookId)
      .collection('chapters').doc(chapterId);
    
    const existing = await docRef.get();
    if (existing.exists) {
      const data = existing.data();
      // Skip if already processed with current version
      if (data.version === '3.0') {
        logger.info(`⏭️ Chapter ${chapterId} already processed with v3.0, skipping`);
        return data.terms;
      }
    }

    // Extract terms using OpenAI
    const terms = await extractExplainableTerms(chapterText, words, bookTitle, bookAuthor);

    // Save to Firestore
    const chapterData = {
      chapterId,
      bookId,
      terms,
      processedAt: new Date(),
      version: '3.0'  // COMPREHENSIVE: 20-50+ terms per chapter, all places/people/events
    };

    await docRef.set(chapterData);
    logger.info(`💾 Saved ${terms.length} explainable terms for ${bookId}/${chapterId}`);

    return terms;

  } catch (error) {
    logger.error(`❌ Error processing chapter ${chapterId}:`, error);
    throw error;
  }
}

module.exports = {
  extractExplainableTerms,
  processChapterExplainableTerms,
  generateTermId
};

