/**
 * Cloud Functions for ReadBetter App
 * Automatically processes books from GCS bucket
 */

const {onRequest} = require("firebase-functions/v2/https");
const {onSchedule} = require("firebase-functions/v2/scheduler");
const {setGlobalOptions} = require("firebase-functions/v2");
const {defineSecret} = require("firebase-functions/params");
const admin = require("firebase-admin");
const axios = require("axios");
const logger = require("firebase-functions/logger");
const { libraryCache, chapterIndexCache } = require('./utils/cache');
const { parseTranscript } = require('./utils/transcriptParser');
const { processChapterExplainableTerms } = require('./utils/explainableTermsExtractor');
const { parseStream } = require('music-metadata');

// Define OpenAI API key as a secret
const openaiApiKey = defineSecret("OPENAI_API_KEY");

admin.initializeApp();

setGlobalOptions({ maxInstances: 10 });

const BUCKET_NAME = 'myapp-readeraudio';
const BUCKET_PROJECT_ID = 'createxyz-readbetter';
const BASE_URL = 'https://storage.googleapis.com';

/**
 * Set CORS headers for API responses
 */
function setCorsHeaders(res) {
  res.set('Access-Control-Allow-Origin', '*');
  res.set('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  res.set('Access-Control-Allow-Headers', 'Content-Type, Authorization');
}

/**
 * Handle OPTIONS request for CORS preflight
 */
function handleOptions(req, res) {
  setCorsHeaders(res);
  res.status(204).send('');
}

/**
 * Extract path parameters from Firebase Functions v2 request
 * URL format: /functionName/{param1}/{param2}
 */
function extractPathParams(req, expectedParams = 2) {
  // Try req.path first, fallback to parsing req.url
  let path = req.path;
  
  // If req.path is empty or doesn't have params, parse from req.url
  if (!path || path === '/' || path.split('/').filter(p => p).length < expectedParams) {
    try {
      // Parse from req.url (full URL or path)
      if (req.url.startsWith('http')) {
        const url = new URL(req.url);
        path = url.pathname;
      } else {
        // req.url is just the path
        const urlMatch = req.url.match(/^\/[^?]+/);
        if (urlMatch) {
          path = urlMatch[0];
        } else {
          path = req.url;
        }
      }
    } catch (e) {
      // Fallback: use req.url as-is if it looks like a path
      if (req.url && req.url.startsWith('/')) {
        path = req.url.split('?')[0]; // Remove query string
      }
    }
  }
  
  const pathParts = path.split('/').filter(p => p);
  
  // Remove function name (first part) if it exists
  // In Firebase Functions v2, path might be: /getChapterIndex/param1/param2
  // Or just: /param1/param2
  if (pathParts.length > 0) {
    // Check if first part is a function name (contains letters, not just numbers)
    const firstPart = pathParts[0];
    if (firstPart && /^[a-zA-Z]/.test(firstPart)) {
      pathParts.shift(); // Remove function name
    }
  }
  
  // CRITICAL FIX: Decode URL-encoded parameters
  // This converts "part%20two" → "part two" and "Get%20Rich%20Or%20Die%20Trying" → "Get Rich Or Die Trying"
  // Handles all URL-encoded characters (spaces, special chars, etc.)
  return pathParts.map(part => {
    try {
      return decodeURIComponent(part);
    } catch (e) {
      // If decoding fails (already decoded or invalid), use as-is
      logger.warn(`Failed to decode path part: ${part}, using as-is`);
      return part;
    }
  });
}

/**
 * Extract ISBN from GCS file path
 */
function extractISBN(path) {
  const parts = path.split('/');
  if (parts.length > 0) {
    const isbn = parts[0];
    if (/^\d{10,13}$/.test(isbn)) {
      return isbn;
    }
  }
  return null;
}

/**
 * Check if this is a book folder (has cover.jpg)
 */
async function isBookFolder(isbn) {
  const coverUrl = `${BASE_URL}/${BUCKET_NAME}/${isbn}/cover.jpg`;
  try {
    const response = await axios.head(coverUrl, { timeout: 5000 });
    return response.status === 200;
  } catch (error) {
    return false;
  }
}

/**
 * Discover chapters for a book by actually listing files in GCS
 * Excludes description files (description.json and description.mp3) from chapters
 */
/**
 * Extract audio duration from a URL using music-metadata
 * @param {string} audioUrl - URL to the audio file
 * @returns {Promise<number|null>} Duration in seconds, or null if failed
 */
async function getAudioDuration(audioUrl) {
  try {
    // Fetch audio file as a stream
    const response = await axios({
      method: 'get',
      url: audioUrl,
      responseType: 'stream',
      timeout: 30000 // 30 second timeout
    });
    
    // Parse metadata from stream
    const metadata = await parseStream(response.data, {
      mimeType: 'audio/m4a'
    });
    
    // Return duration in seconds
    if (metadata.format && metadata.format.duration) {
      return metadata.format.duration;
    }
    
    logger.warn(`No duration found in metadata for ${audioUrl}`);
    return null;
  } catch (error) {
    logger.error(`Failed to extract duration for ${audioUrl}:`, error.message);
    return null;
  }
}

async function discoverChapters(isbn, bucket) {
  // List all files in the ISBN folder
  const [files] = await bucket.getFiles({ prefix: `${isbn}/` });
  
  // Find all .m4a files (these are our chapter audio files)
  // Exclude description.mp3 (description audio file)
  const audioFiles = files
    .map(f => f.name)
    .filter(name => name.endsWith('.m4a'))
    .map(name => {
      // Extract chapter name from path like "0061122416/prologue.m4a"
      const parts = name.split('/');
      const filename = parts[parts.length - 1];
      return filename.replace('.m4a', '');
    });
  
  // Find all .json files
  // Exclude description.json (description transcript file)
  const jsonFiles = files
    .map(f => f.name)
    .filter(name => name.endsWith('.json') && !name.endsWith('description.json'))
    .map(name => {
      const parts = name.split('/');
      const filename = parts[parts.length - 1];
      return filename.replace('.json', '');
    });
  
  // Only include chapters that have BOTH audio and json files
  const validChapters = audioFiles.filter(name => jsonFiles.includes(name));
  
  logger.info(`Found ${validChapters.length} valid chapters for ${isbn}: ${validChapters.join(', ')}`);
  
  // Sort chapters intelligently
  const sortedChapters = sortChapters(validChapters);
  
  // Build chapter objects with duration extraction
  const chapters = [];
  for (let index = 0; index < sortedChapters.length; index++) {
    const name = sortedChapters[index];
    const audioUrl = `${BASE_URL}/${BUCKET_NAME}/${isbn}/${name}.m4a`;
    
    // Extract duration for this chapter
    logger.info(`Extracting duration for chapter: ${name}`);
    const duration = await getAudioDuration(audioUrl);
    
    const chapter = {
      id: `${isbn}-${name}`,
      title: formatChapterTitle(name),
      audioUrl: audioUrl,
      jsonUrl: `${BASE_URL}/${BUCKET_NAME}/${isbn}/${name}.json`,
      order: index
    };
    
    // Only add duration if successfully extracted
    if (duration !== null) {
      chapter.duration = duration;
      logger.info(`Chapter ${name} duration: ${Math.round(duration / 60)} minutes`);
    }
    
    chapters.push(chapter);
  }
  
  return chapters;
}

/**
 * Discover description files for a book (description.json + description.mp3)
 * @param {string} isbn - The book ISBN
 * @param {object} bucket - GCS bucket object
 * @returns {object|null} Description info or null if not found
 */
async function discoverDescription(isbn, bucket) {
  // List all files in the ISBN folder
  const [files] = await bucket.getFiles({ prefix: `${isbn}/` });
  
  // Check for description.json
  const hasDescriptionJson = files.some(f => f.name.endsWith('description.json'));
  
  // Check for description.mp3 (description audio file)
  const hasDescriptionAudio = files.some(f => f.name.endsWith('description.mp3'));
  
  if (hasDescriptionJson && hasDescriptionAudio) {
    logger.info(`Found description files for ${isbn}`);
    return {
      hasDescription: true,
      descriptionAudioUrl: `${BASE_URL}/${BUCKET_NAME}/${isbn}/description.mp3`,
      descriptionJsonUrl: `${BASE_URL}/${BUCKET_NAME}/${isbn}/description.json`
    };
  }
  
  return null;
}

/**
 * Smart chapter sorting that handles various naming conventions
 */
function sortChapters(chapterNames) {
  // Define priority for special chapter types (lower = earlier)
  const getChapterPriority = (name) => {
    const lower = name.toLowerCase().replace(/[-_\s]/g, '');
    
    // Front matter (comes first)
    if (lower.includes('foreword') || lower === 'foreward') return { priority: 0, subOrder: 0 };
    if (lower.includes('preface')) return { priority: 0, subOrder: 1 };
    if (lower.includes('introduction') || lower === 'intro') return { priority: 0, subOrder: 2 };
    if (lower.includes('prologue')) return { priority: 0, subOrder: 3 };
    
    // Back matter (comes last)
    if (lower.includes('epilogue')) return { priority: 1000, subOrder: 0 };
    if (lower.includes('afterword')) return { priority: 1000, subOrder: 1 };
    if (lower.includes('conclusion')) return { priority: 1000, subOrder: 2 };
    if (lower.includes('appendix')) return { priority: 1000, subOrder: 3 };
    
    // Check for explicit ordering suffix like (1), (2), (3) at the end
    // This is used for chapters with arbitrary names that need manual ordering
    // e.g., "The Beginning (1)", "A New World (2)", "TheNugget(1)"
    const orderMatch = name.match(/\((\d+)\)$/);
    if (orderMatch) {
      return { priority: 100, subOrder: parseInt(orderMatch[1], 10) };
    }
    
    // Main content - extract numbers
    const numbers = extractNumbers(name);
    if (numbers.length > 0) {
      // Handle "book1part1" format - primary sort by book, secondary by part/chapter
      if (numbers.length >= 2) {
        return { priority: 100 + numbers[0], subOrder: numbers[1] };
      }
      // Single number - "chapter-1", "part-1", etc.
      return { priority: 100, subOrder: numbers[0] };
    }
    
    // Check for Roman numerals
    const romanValue = parseRomanNumeral(name);
    if (romanValue > 0) {
      return { priority: 100, subOrder: romanValue };
    }
    
    // Check for word numbers (one, two, three, etc.)
    const wordNumber = parseWordNumber(name);
    if (wordNumber > 0) {
      return { priority: 100, subOrder: wordNumber };
    }
    
    // Unknown format - put in middle
    return { priority: 500, subOrder: 0 };
  };
  
  return chapterNames.sort((a, b) => {
    const aPriority = getChapterPriority(a);
    const bPriority = getChapterPriority(b);
    
    if (aPriority.priority !== bPriority.priority) {
      return aPriority.priority - bPriority.priority;
    }
    return aPriority.subOrder - bPriority.subOrder;
  });
}

/**
 * Extract all numbers from a string
 */
function extractNumbers(str) {
  const matches = str.match(/\d+/g);
  return matches ? matches.map(n => parseInt(n, 10)) : [];
}

/**
 * Parse Roman numerals from a string
 */
function parseRomanNumeral(str) {
  // Extract potential Roman numeral from the string
  const romanMatch = str.toUpperCase().match(/\b(M{0,3})(CM|CD|D?C{0,3})(XC|XL|L?X{0,3})(IX|IV|V?I{0,3})\b/);
  
  if (!romanMatch || romanMatch[0] === '') return 0;
  
  const roman = romanMatch[0];
  const romanMap = {
    'I': 1, 'V': 5, 'X': 10, 'L': 50,
    'C': 100, 'D': 500, 'M': 1000
  };
  
  let value = 0;
  for (let i = 0; i < roman.length; i++) {
    const current = romanMap[roman[i]];
    const next = romanMap[roman[i + 1]];
    if (next && current < next) {
      value -= current;
    } else {
      value += current;
    }
  }
  
  return value;
}

/**
 * Parse word numbers (one, two, three, etc.)
 */
function parseWordNumber(str) {
  const lower = str.toLowerCase();
  const wordNumbers = {
    'one': 1, 'two': 2, 'three': 3, 'four': 4, 'five': 5,
    'six': 6, 'seven': 7, 'eight': 8, 'nine': 9, 'ten': 10,
    'eleven': 11, 'twelve': 12, 'thirteen': 13, 'fourteen': 14, 'fifteen': 15,
    'sixteen': 16, 'seventeen': 17, 'eighteen': 18, 'nineteen': 19, 'twenty': 20,
    'first': 1, 'second': 2, 'third': 3, 'fourth': 4, 'fifth': 5,
    'sixth': 6, 'seventh': 7, 'eighth': 8, 'ninth': 9, 'tenth': 10
  };
  
  for (const [word, num] of Object.entries(wordNumbers)) {
    if (lower.includes(word)) {
      return num;
    }
  }
  
  return 0;
}

/**
 * Format chapter name into a readable title
 */
function formatChapterTitle(name) {
  // Strip explicit ordering suffix like (1), (2), (3) - used for ordering, not display
  // Handles both "Name (1)" and "Name(1)" formats
  name = name.replace(/\s*\(\d+\)$/, '');
  
  const lower = name.toLowerCase().replace(/[-_]/g, ' ');
  
  // Handle special names
  if (lower.includes('prologue')) return 'Prologue';
  if (lower.includes('epilogue')) return 'Epilogue';
  if (lower.includes('foreword') || lower.includes('foreward')) return 'Foreword';
  if (lower.includes('preface')) return 'Preface';
  if (lower.includes('introduction')) return 'Introduction';
  if (lower.includes('afterword')) return 'Afterword';
  if (lower.includes('conclusion')) return 'Conclusion';
  
  // Handle "book1part1" or "book-1-part-1" format
  const bookPartMatch = name.match(/book\s*[-_]?\s*(\d+)\s*[-_]?\s*part\s*[-_]?\s*(\d+)/i);
  if (bookPartMatch) {
    return `Book ${bookPartMatch[1]}, Part ${bookPartMatch[2]}`;
  }
  
  // Handle "part-one" or "part-1" format
  const partMatch = name.match(/part\s*[-_]?\s*(\w+)/i);
  if (partMatch) {
    const partNum = parseWordNumber(partMatch[1]) || partMatch[1];
    return `Part ${typeof partNum === 'number' ? partNum : partNum.charAt(0).toUpperCase() + partNum.slice(1)}`;
  }
  
  // Handle "chapter-1" or "chapter-one" format
  const chapterMatch = name.match(/chapter\s*[-_]?\s*(\w+)/i);
  if (chapterMatch) {
    const chapterNum = parseWordNumber(chapterMatch[1]) || chapterMatch[1];
    return `Chapter ${typeof chapterNum === 'number' ? chapterNum : chapterNum.charAt(0).toUpperCase() + chapterNum.slice(1)}`;
  }
  
  // Handle Roman numerals standalone (like "I", "II", "III")
  const romanValue = parseRomanNumeral(name);
  if (romanValue > 0 && name.match(/^[IVXLCDM]+$/i)) {
    return `Chapter ${romanValue}`;
  }
  
  // Default: capitalize each word
  return name
    .replace(/[-_]/g, ' ')
    .replace(/\b\w/g, l => l.toUpperCase())
    .trim();
}

/**
 * Fetch book metadata from Google Books API
 */
async function fetchBookMetadata(isbn) {
  try {
    const response = await axios.get(
      `https://www.googleapis.com/books/v1/volumes?q=isbn:${isbn}`,
      { timeout: 10000 }
    );
    
    if (!response.data.items || response.data.items.length === 0) {
      throw new Error('Book not found in Google Books API');
    }
    
    const item = response.data.items[0];
    const volumeInfo = item.volumeInfo;
    
    let isbn10 = isbn;
    let isbn13 = null;
    if (volumeInfo.industryIdentifiers) {
      const isbn10Obj = volumeInfo.industryIdentifiers.find(id => id.type === 'ISBN_10');
      const isbn13Obj = volumeInfo.industryIdentifiers.find(id => id.type === 'ISBN_13');
      if (isbn10Obj) isbn10 = isbn10Obj.identifier;
      if (isbn13Obj) isbn13 = isbn13Obj.identifier;
    }
    
    return {
      title: volumeInfo.title || 'Unknown Title',
      author: volumeInfo.authors?.[0] || 'Unknown Author',
      description: volumeInfo.description || null,
      coverUrl: volumeInfo.imageLinks?.thumbnail?.replace('http://', 'https://') || null,
      publisher: volumeInfo.publisher || null,
      publishedDate: volumeInfo.publishedDate || null,
      isbn10: isbn10,
      isbn13: isbn13
    };
  } catch (error) {
    logger.error(`Error fetching metadata for ${isbn}:`, error);
    throw error;
  }
}

/**
 * Process a book: fetch metadata and save to Firestore
 * @param {string} isbn - The book ISBN
 * @param {object} bucket - GCS bucket object
 * @param {boolean} forceUpdate - If true, update even if book exists
 */
async function processBook(isbn, bucket, forceUpdate = false) {
  const db = admin.firestore();
  const bookRef = db.collection('books').doc(isbn);
  
  const existing = await bookRef.get();
  if (existing.exists && !forceUpdate) {
    logger.info(`Book ${isbn} already exists, skipping...`);
    return { status: 'skipped', reason: 'exists' };
  }
  
  logger.info(`Processing book: ${isbn}`);
  
  const isBook = await isBookFolder(isbn);
  if (!isBook) {
    logger.info(`Folder ${isbn} doesn't appear to be a book (no cover.jpg), skipping...`);
    return { status: 'skipped', reason: 'no_cover' };
  }
  
  // Dynamically discover chapters from GCS
  const chapters = await discoverChapters(isbn, bucket);
  
  // Discover description files (description.json + description.mp3)
  const descriptionInfo = await discoverDescription(isbn, bucket);
  
  // Allow books with either chapters OR description (or both)
  // If neither is present, still create a metadata-only entry so the book
  // shows up in the app and can be filled in later.
  if (chapters.length === 0 && !descriptionInfo) {
    logger.info(`No chapters or description found for ${isbn}; creating metadata-only entry.`);
  }
  
  const metadata = await fetchBookMetadata(isbn);
  const coverURL = `${BASE_URL}/${BUCKET_NAME}/${isbn}/cover.jpg`;
  
  const bookData = {
    id: isbn,
    title: metadata.title,
    author: metadata.author,
    isbn10: metadata.isbn10,
    coverUrl: coverURL,
    chapters: chapters,
    createdAt: admin.firestore.FieldValue.serverTimestamp()
  };
  
  // Add description fields if found
  if (descriptionInfo) {
    bookData.hasDescription = descriptionInfo.hasDescription;
    bookData.descriptionAudioUrl = descriptionInfo.descriptionAudioUrl;
    bookData.descriptionJsonUrl = descriptionInfo.descriptionJsonUrl;
  }
  
  if (metadata.description) bookData.description = metadata.description;
  if (metadata.publisher) bookData.publisher = metadata.publisher;
  if (metadata.publishedDate) bookData.publishedDate = metadata.publishedDate;
  if (metadata.isbn13) bookData.isbn13 = metadata.isbn13;
  
  await bookRef.set(bookData);
  const descriptionText = descriptionInfo ? ' (with description)' : '';
  logger.info(`✅ Successfully processed book: ${isbn} - ${metadata.title} (${chapters.length} chapters${descriptionText})`);
  return { status: 'processed', chapters: chapters.length, hasDescription: !!descriptionInfo };
}

/**
 * Core function to scan and process all books
 * @param {boolean} forceUpdate - If true, re-process books even if they exist
 */
async function scanAndProcessAllBooks(forceUpdate = false) {
  try {
    const {Storage} = require('@google-cloud/storage');
    const storage = new Storage({
      projectId: BUCKET_PROJECT_ID
    });
    const bucket = storage.bucket(BUCKET_NAME);
    
    logger.info('Listing all files in bucket...');
    
    // List all files in the bucket
    const [allFiles] = await bucket.getFiles();
    logger.info(`Found ${allFiles.length} total files in bucket`);
    
    // Extract unique ISBNs from file paths
    const isbnSet = new Set();
    
    for (const file of allFiles) {
      const path = file.name;
      const isbn = extractISBN(path);
      if (isbn) {
        isbnSet.add(isbn);
      }
    }
    
    const isbns = Array.from(isbnSet);
    logger.info(`Found ${isbns.length} unique ISBN folders: ${isbns.join(', ')}`);
    
    const processed = [];
    const skipped = [];
    const errors = [];
    const details = {};
    
    for (const isbn of isbns) {
      if (!/^\d{10,13}$/.test(isbn)) {
        logger.info(`Skipping invalid ISBN: ${isbn}`);
        skipped.push(isbn);
        details[isbn] = { status: 'skipped', reason: 'invalid_isbn' };
        continue;
      }
      
      try {
        const result = await processBook(isbn, bucket, forceUpdate);
        if (result.status === 'processed') {
          processed.push(isbn);
          details[isbn] = result;
        } else {
          skipped.push(isbn);
          details[isbn] = result;
        }
      } catch (error) {
        logger.error(`Error processing ${isbn}:`, error);
        errors.push(isbn);
        details[isbn] = { status: 'error', message: error.message };
      }
      
      // Small delay to avoid rate limiting
      await new Promise(resolve => setTimeout(resolve, 500));
    }
    
    return {
      success: true,
      processed: processed.length,
      skipped: skipped.length,
      errors: errors.length,
      totalFiles: allFiles.length,
      uniqueISBNs: isbns.length,
      forceUpdate: forceUpdate,
      details: details
    };
  } catch (error) {
    logger.error('Error scanning books:', error);
    throw error;
  }
}

/**
 * Cloud Function: Manually trigger processing of all books
 * Call via: https://scanallbooks-iiyc76erma-ts.a.run.app
 *
 * Query parameters:
 * - forceUpdate=true : Re-process books even if they already exist (updates chapters)
 */
exports.scanAllBooks = onRequest(
  { region: 'australia-southeast1' },
  async (req, res) => {
    try {
      // Check for forceUpdate query parameter
      const forceUpdate = req.query.forceUpdate === 'true';
      
      if (forceUpdate) {
        logger.info('Force update enabled - will re-process all books');
      }
      
      const result = await scanAndProcessAllBooks(forceUpdate);
      res.json(result);
    } catch (error) {
      logger.error('Error in scanAllBooks:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  }
);

/**
 * Cloud Function: Auto-scan every hour
 * Automatically checks for new books and processes them
 */
exports.autoScanBooks = onSchedule(
  {
    schedule: 'every 1 hours',
    region: 'australia-southeast1',
    timeZone: 'Australia/Sydney'
  },
  async (event) => {
    logger.info('Starting scheduled book scan...');
    try {
      const result = await scanAndProcessAllBooks();
      logger.info('Scheduled scan complete:', result);
    } catch (error) {
      logger.error('Error in scheduled scan:', error);
    }
  }
);

// ============================================================================
// Explainable Terms Processing
// ============================================================================

/**
 * HTTP Trigger: Manually process explainable terms for a chapter
 * POST /processExplainableTerms/{bookId}/{chapterId}
 */
exports.processExplainableTerms = onRequest(
  {
    region: 'australia-southeast1',
    secrets: [openaiApiKey],
    timeoutSeconds: 300,
    memory: '512MiB'
  },
  async (req, res) => {
    // Handle CORS preflight
    if (req.method === 'OPTIONS') {
      return handleOptions(req, res);
    }
    
    setCorsHeaders(res);
    
    try {
      const pathParts = extractPathParams(req);
      const bookId = pathParts[0];
      const chapterId = pathParts[1];
      
      if (!bookId || !chapterId) {
        return res.status(400).json({
          success: false,
          error: 'Missing bookId or chapterId. URL format: /processExplainableTerms/{bookId}/{chapterId}'
        });
      }
      
      logger.info(`📖 Manual trigger: Processing explainable terms for ${bookId}/${chapterId}`);
      
      // Set OpenAI API key from secret
      process.env.OPENAI_API_KEY = openaiApiKey.value();
      
      const db = admin.firestore();
      
      // Get book data
      const bookDoc = await db.collection('books').doc(bookId).get();
      if (!bookDoc.exists) {
        return res.status(404).json({
          success: false,
          error: `Book ${bookId} not found`
        });
      }
      
      const bookData = bookDoc.data();
      const chapters = bookData.chapters || [];
      
      // Find the chapter
      const chapter = chapters.find(ch => ch.id === chapterId);
      if (!chapter) {
        return res.status(404).json({
          success: false,
          error: `Chapter ${chapterId} not found in book ${bookId}`
        });
      }
      
      // Fetch the JSON file content
      const jsonResponse = await axios.get(chapter.jsonUrl, { timeout: 30000 });
      if (!jsonResponse.data) {
        return res.status(500).json({
          success: false,
          error: 'Failed to fetch chapter JSON'
        });
      }
      
      // Parse transcript
      const transcriptData = parseTranscript(jsonResponse.data);
      
      // Process explainable terms
      const terms = await processChapterExplainableTerms(
        db,
        bookId,
        chapterId,
        transcriptData.fullText,
        transcriptData.words,
        bookData.title || 'Unknown Book',
        bookData.author || 'Unknown Author'
      );
      
      res.json({
        success: true,
        message: `Processed ${terms.length} explainable terms`,
        terms: terms
      });
      
    } catch (error) {
      logger.error('Error in processExplainableTerms:', error);
      res.status(500).json({
        success: false,
        error: error.message
      });
    }
  }
);

/**
 * HTTP Trigger: Get explainable terms for a chapter
 * GET /getExplainableTerms/{bookId}/{chapterId}
 */
exports.getExplainableTerms = onRequest(
  { region: 'australia-southeast1' },
  async (req, res) => {
    // Handle CORS preflight
    if (req.method === 'OPTIONS') {
      return handleOptions(req, res);
    }
    
    setCorsHeaders(res);
    
    try {
      const pathParts = extractPathParams(req);
      const bookId = pathParts[0];
      const chapterId = pathParts[1];
      
      if (!bookId || !chapterId) {
        return res.status(400).json({
          success: false,
          error: 'Missing bookId or chapterId. URL format: /getExplainableTerms/{bookId}/{chapterId}'
        });
      }
      
      const db = admin.firestore();
      const docRef = db.collection('explainableTerms').doc(bookId)
        .collection('chapters').doc(chapterId);
      
      const doc = await docRef.get();
      
      if (!doc.exists) {
        return res.json({
          success: true,
          chapterId: chapterId,
          bookId: bookId,
          terms: [],
          message: 'No explainable terms found. Terms are processed automatically when chapters are uploaded.'
        });
      }
      
      const data = doc.data();
      res.json({
        success: true,
        chapterId: data.chapterId,
        bookId: data.bookId,
        terms: data.terms || [],
        processedAt: data.processedAt?.toDate?.() || data.processedAt,
        version: data.version
      });
      
    } catch (error) {
      logger.error('Error in getExplainableTerms:', error);
      res.status(500).json({
        success: false,
        error: error.message
      });
    }
  }
);

/**
 * HTTP Trigger: Process explainable terms for ALL chapters in a book
 * POST /processBookExplainableTerms/{bookId}
 */
exports.processBookExplainableTerms = onRequest(
  {
    region: 'australia-southeast1',
    secrets: [openaiApiKey],
    timeoutSeconds: 540, // 9 minutes max
    memory: '512MiB'
  },
  async (req, res) => {
    // Handle CORS preflight
    if (req.method === 'OPTIONS') {
      return handleOptions(req, res);
    }
    
    setCorsHeaders(res);
    
    try {
      const pathParts = extractPathParams(req, 1);
      const bookId = pathParts[0];
      
      if (!bookId) {
        return res.status(400).json({
          success: false,
          error: 'Missing bookId. URL format: /processBookExplainableTerms/{bookId}'
        });
      }
      
      logger.info(`📚 Processing explainable terms for all chapters in book ${bookId}`);
      
      // Set OpenAI API key from secret
      process.env.OPENAI_API_KEY = openaiApiKey.value();
      
      const db = admin.firestore();
      
      // Get book data
      const bookDoc = await db.collection('books').doc(bookId).get();
      if (!bookDoc.exists) {
        return res.status(404).json({
          success: false,
          error: `Book ${bookId} not found`
        });
      }
      
      const bookData = bookDoc.data();
      const chapters = bookData.chapters || [];
      
      if (chapters.length === 0) {
        return res.json({
          success: true,
          message: 'No chapters found in book',
          processed: 0
        });
      }
      
      const results = [];
      
      for (const chapter of chapters) {
        try {
          logger.info(`Processing chapter: ${chapter.id}`);
          
          // Fetch the JSON file content
          const jsonResponse = await axios.get(chapter.jsonUrl, { timeout: 30000 });
          if (!jsonResponse.data) {
            results.push({ chapterId: chapter.id, status: 'error', error: 'Empty JSON' });
            continue;
          }
          
          // Parse transcript
          const transcriptData = parseTranscript(jsonResponse.data);
          
          // Process explainable terms
          const terms = await processChapterExplainableTerms(
            db,
            bookId,
            chapter.id,
            transcriptData.fullText,
            transcriptData.words,
            bookData.title || 'Unknown Book',
            bookData.author || 'Unknown Author'
          );
          
          results.push({ chapterId: chapter.id, status: 'success', termCount: terms.length });
          
          // Small delay to avoid rate limiting
          await new Promise(resolve => setTimeout(resolve, 1000));
          
        } catch (error) {
          logger.error(`Error processing chapter ${chapter.id}:`, error);
          results.push({ chapterId: chapter.id, status: 'error', error: error.message });
        }
      }
      
      const successCount = results.filter(r => r.status === 'success').length;
      
      res.json({
        success: true,
        message: `Processed ${successCount}/${chapters.length} chapters`,
        results: results
      });
      
    } catch (error) {
      logger.error('Error in processBookExplainableTerms:', error);
      res.status(500).json({
        success: false,
        error: error.message
      });
    }
  }
);

// ============================================================================
// Explainable Terms Dashboard (Web UI)
// ============================================================================

/**
 * Web Dashboard: View and manage explainable terms processing
 * GET /explainableTermsDashboard
 * 
 * Shows all books/chapters and their processing status.
 * Allows triggering processing for unprocessed chapters.
 */
exports.explainableTermsDashboard = onRequest(
  {
    region: 'australia-southeast1',
    secrets: [openaiApiKey],
    timeoutSeconds: 540,
    memory: '512MiB'
  },
  async (req, res) => {
    const db = admin.firestore();
    
    // Handle POST requests (trigger processing)
    if (req.method === 'POST') {
      setCorsHeaders(res);
      
      const action = req.body?.action || req.query.action;
      const bookId = req.body?.bookId || req.query.bookId;
      const chapterId = req.body?.chapterId || req.query.chapterId;
      
      // Set OpenAI API key from secret
      process.env.OPENAI_API_KEY = openaiApiKey.value();
      
      if (action === 'processChapter' && bookId && chapterId) {
        try {
          // Get book data
          const bookDoc = await db.collection('books').doc(bookId).get();
          if (!bookDoc.exists) {
            return res.status(404).json({ success: false, error: 'Book not found' });
          }
          
          const bookData = bookDoc.data();
          const chapter = (bookData.chapters || []).find(ch => ch.id === chapterId);
          if (!chapter) {
            return res.status(404).json({ success: false, error: 'Chapter not found' });
          }
          
          // Fetch JSON and process
          const jsonResponse = await axios.get(chapter.jsonUrl, { timeout: 30000 });
          const transcriptData = parseTranscript(jsonResponse.data);
          
          const terms = await processChapterExplainableTerms(
            db, bookId, chapterId, transcriptData.fullText, transcriptData.words,
            bookData.title || 'Unknown', bookData.author || 'Unknown'
          );
          
          return res.json({ success: true, termCount: terms.length });
        } catch (error) {
          return res.status(500).json({ success: false, error: error.message });
        }
      }
      
      if (action === 'processBook' && bookId) {
        try {
          const bookDoc = await db.collection('books').doc(bookId).get();
          if (!bookDoc.exists) {
            return res.status(404).json({ success: false, error: 'Book not found' });
          }
          
          const bookData = bookDoc.data();
          const chapters = bookData.chapters || [];
          const results = [];
          
          for (const chapter of chapters) {
            try {
              const jsonResponse = await axios.get(chapter.jsonUrl, { timeout: 30000 });
              const transcriptData = parseTranscript(jsonResponse.data);
              
              const terms = await processChapterExplainableTerms(
                db, bookId, chapter.id, transcriptData.fullText, transcriptData.words,
                bookData.title || 'Unknown', bookData.author || 'Unknown'
              );
              
              results.push({ chapterId: chapter.id, status: 'success', termCount: terms.length });
              await new Promise(resolve => setTimeout(resolve, 1000));
            } catch (error) {
              results.push({ chapterId: chapter.id, status: 'error', error: error.message });
            }
          }
          
          return res.json({ success: true, results });
        } catch (error) {
          return res.status(500).json({ success: false, error: error.message });
        }
      }
      
      if (action === 'processAll') {
        try {
          const booksSnapshot = await db.collection('books').get();
          const allResults = [];
          
          for (const bookDoc of booksSnapshot.docs) {
            const bookData = bookDoc.data();
            const bookId = bookDoc.id;
            const chapters = bookData.chapters || [];
            
            for (const chapter of chapters) {
              // Check if already processed with current version
              const termsDoc = await db.collection('explainableTerms').doc(bookId)
                .collection('chapters').doc(chapter.id).get();
              
              if (termsDoc.exists && termsDoc.data()?.version === '3.0') {
                allResults.push({ bookId, chapterId: chapter.id, status: 'skipped', reason: 'already v3.0' });
                continue;
              }
              
              try {
                const jsonResponse = await axios.get(chapter.jsonUrl, { timeout: 30000 });
                const transcriptData = parseTranscript(jsonResponse.data);
                
                const terms = await processChapterExplainableTerms(
                  db, bookId, chapter.id, transcriptData.fullText, transcriptData.words,
                  bookData.title || 'Unknown', bookData.author || 'Unknown'
                );
                
                allResults.push({ bookId, chapterId: chapter.id, status: 'success', termCount: terms.length });
                await new Promise(resolve => setTimeout(resolve, 1500));
              } catch (error) {
                allResults.push({ bookId, chapterId: chapter.id, status: 'error', error: error.message });
              }
            }
          }
          
          return res.json({ success: true, results: allResults });
        } catch (error) {
          return res.status(500).json({ success: false, error: error.message });
        }
      }
      
      return res.status(400).json({ success: false, error: 'Invalid action' });
    }
    
    // GET request - show dashboard HTML
    try {
      // Get all books
      const booksSnapshot = await db.collection('books').get();
      const books = [];
      
      for (const bookDoc of booksSnapshot.docs) {
        const bookData = bookDoc.data();
        const bookId = bookDoc.id;
        const chapters = bookData.chapters || [];
        
        // Get explainable terms status for each chapter
        const chapterStatuses = [];
        for (const chapter of chapters) {
          const termsDoc = await db.collection('explainableTerms').doc(bookId)
            .collection('chapters').doc(chapter.id).get();
          
          chapterStatuses.push({
            id: chapter.id,
            title: chapter.title,
            processed: termsDoc.exists,
            termCount: termsDoc.exists ? (termsDoc.data()?.terms?.length || 0) : 0,
            version: termsDoc.exists ? (termsDoc.data()?.version || '?') : null,
            processedAt: termsDoc.exists ? termsDoc.data()?.processedAt?.toDate?.()?.toISOString?.() : null
          });
        }
        
        books.push({
          id: bookId,
          title: bookData.title || 'Unknown',
          author: bookData.author || 'Unknown',
          chapters: chapterStatuses
        });
      }
      
      // Sort books by title
      books.sort((a, b) => a.title.localeCompare(b.title));
      
      // Generate HTML
      const html = `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Explainable Terms Dashboard</title>
  <style>
    * { box-sizing: border-box; margin: 0; padding: 0; }
    body { 
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
      background: linear-gradient(135deg, #1a1a2e 0%, #16213e 100%);
      color: #e0e0e0;
      min-height: 100vh;
      padding: 20px;
    }
    .container { max-width: 1200px; margin: 0 auto; }
    h1 { 
      text-align: center; 
      margin-bottom: 30px; 
      color: #ffd700;
      font-size: 2.5em;
      text-shadow: 2px 2px 4px rgba(0,0,0,0.3);
    }
    .stats {
      display: flex;
      gap: 20px;
      justify-content: center;
      margin-bottom: 30px;
      flex-wrap: wrap;
    }
    .stat-card {
      background: rgba(255,255,255,0.1);
      border-radius: 12px;
      padding: 20px 30px;
      text-align: center;
      backdrop-filter: blur(10px);
    }
    .stat-card h3 { color: #ffd700; font-size: 2em; }
    .stat-card p { color: #aaa; margin-top: 5px; }
    .actions {
      text-align: center;
      margin-bottom: 30px;
    }
    button {
      background: linear-gradient(135deg, #ffd700 0%, #ff8c00 100%);
      color: #1a1a2e;
      border: none;
      padding: 12px 24px;
      border-radius: 8px;
      font-weight: bold;
      cursor: pointer;
      margin: 5px;
      transition: transform 0.2s, box-shadow 0.2s;
    }
    button:hover { transform: translateY(-2px); box-shadow: 0 4px 12px rgba(255,215,0,0.3); }
    button:disabled { opacity: 0.5; cursor: not-allowed; transform: none; }
    button.small { padding: 6px 12px; font-size: 0.85em; }
    button.danger { background: linear-gradient(135deg, #ff4444 0%, #cc0000 100%); }
    .book {
      background: rgba(255,255,255,0.05);
      border-radius: 12px;
      margin-bottom: 20px;
      overflow: hidden;
      border: 1px solid rgba(255,255,255,0.1);
    }
    .book-header {
      background: rgba(255,255,255,0.1);
      padding: 15px 20px;
      display: flex;
      justify-content: space-between;
      align-items: center;
      cursor: pointer;
    }
    .book-header:hover { background: rgba(255,255,255,0.15); }
    .book-title { font-weight: bold; font-size: 1.1em; }
    .book-author { color: #aaa; font-size: 0.9em; }
    .book-stats { color: #ffd700; font-size: 0.9em; }
    .chapters { padding: 0 20px 20px; display: none; }
    .chapters.open { display: block; }
    .chapter {
      display: flex;
      justify-content: space-between;
      align-items: center;
      padding: 12px 15px;
      background: rgba(0,0,0,0.2);
      border-radius: 8px;
      margin-top: 10px;
    }
    .chapter-info { flex: 1; }
    .chapter-title { font-weight: 500; }
    .chapter-meta { font-size: 0.85em; color: #888; margin-top: 3px; }
    .status { 
      padding: 4px 10px; 
      border-radius: 20px; 
      font-size: 0.8em; 
      font-weight: bold;
      margin-right: 10px;
    }
    .status.processed { background: #2ecc71; color: #000; }
    .status.pending { background: #e74c3c; color: #fff; }
    .status.outdated { background: #f39c12; color: #000; }
    .loading { display: none; margin-left: 10px; }
    .loading.show { display: inline; }
    #toast {
      position: fixed;
      bottom: 20px;
      right: 20px;
      background: #2ecc71;
      color: #fff;
      padding: 15px 25px;
      border-radius: 8px;
      display: none;
      z-index: 1000;
      box-shadow: 0 4px 12px rgba(0,0,0,0.3);
    }
    #toast.error { background: #e74c3c; }
    #toast.show { display: block; animation: slideIn 0.3s ease; }
    @keyframes slideIn { from { transform: translateX(100%); } to { transform: translateX(0); } }
  </style>
</head>
<body>
  <div class="container">
    <h1>📚 Explainable Terms Dashboard</h1>
    
    <div class="stats">
      <div class="stat-card">
        <h3>${books.length}</h3>
        <p>Books</p>
      </div>
      <div class="stat-card">
        <h3>${books.reduce((sum, b) => sum + b.chapters.length, 0)}</h3>
        <p>Total Chapters</p>
      </div>
      <div class="stat-card">
        <h3>${books.reduce((sum, b) => sum + b.chapters.filter(c => c.processed && c.version === '3.0').length, 0)}</h3>
        <p>Processed (v3.0)</p>
      </div>
      <div class="stat-card">
        <h3>${books.reduce((sum, b) => sum + b.chapters.filter(c => !c.processed || c.version !== '3.0').length, 0)}</h3>
        <p>Pending/Outdated</p>
      </div>
    </div>
    
    <div class="actions">
      <button onclick="processAllUnprocessed()">🚀 Process All Unprocessed</button>
      <button onclick="location.reload()">🔄 Refresh</button>
    </div>
    
    ${books.map(book => {
      const processedCount = book.chapters.filter(c => c.processed && c.version === '3.0').length;
      const totalCount = book.chapters.length;
      return `
      <div class="book">
        <div class="book-header" onclick="toggleBook('${book.id}')">
          <div>
            <div class="book-title">${escapeHtml(book.title)}</div>
            <div class="book-author">by ${escapeHtml(book.author)}</div>
          </div>
          <div style="display: flex; align-items: center;">
            <div class="book-stats">${processedCount}/${totalCount} processed</div>
            <button class="small" onclick="event.stopPropagation(); processBook('${book.id}')">Process Book</button>
          </div>
        </div>
        <div class="chapters" id="chapters-${book.id}">
          ${book.chapters.map(ch => {
            const statusClass = !ch.processed ? 'pending' : (ch.version === '3.0' ? 'processed' : 'outdated');
            const statusText = !ch.processed ? 'Pending' : (ch.version === '3.0' ? `v${ch.version} (${ch.termCount} terms)` : `v${ch.version} - needs update`);
            return `
            <div class="chapter" id="chapter-${ch.id.replace(/[^a-zA-Z0-9]/g, '_')}">
              <div class="chapter-info">
                <div class="chapter-title">${escapeHtml(ch.title || ch.id)}</div>
                <div class="chapter-meta">${ch.processedAt ? 'Processed: ' + new Date(ch.processedAt).toLocaleString() : 'Not processed'}</div>
              </div>
              <span class="status ${statusClass}">${statusText}</span>
              <button class="small" onclick="processChapter('${book.id}', '${ch.id}')">Process</button>
              <span class="loading" id="loading-${ch.id.replace(/[^a-zA-Z0-9]/g, '_')}">⏳</span>
            </div>`;
          }).join('')}
        </div>
      </div>`;
    }).join('')}
  </div>
  
  <div id="toast"></div>
  
  <script>
    function toggleBook(bookId) {
      const el = document.getElementById('chapters-' + bookId);
      el.classList.toggle('open');
    }
    
    function showToast(message, isError = false) {
      const toast = document.getElementById('toast');
      toast.textContent = message;
      toast.className = isError ? 'error show' : 'show';
      setTimeout(() => toast.className = '', 3000);
    }
    
    async function processChapter(bookId, chapterId) {
      const loadingId = 'loading-' + chapterId.replace(/[^a-zA-Z0-9]/g, '_');
      const loading = document.getElementById(loadingId);
      if (loading) loading.classList.add('show');
      
      try {
        const response = await fetch(window.location.href, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ action: 'processChapter', bookId, chapterId })
        });
        const data = await response.json();
        
        if (data.success) {
          showToast('✅ Processed ' + data.termCount + ' terms');
          setTimeout(() => location.reload(), 1500);
        } else {
          showToast('❌ Error: ' + data.error, true);
        }
      } catch (error) {
        showToast('❌ Error: ' + error.message, true);
      } finally {
        if (loading) loading.classList.remove('show');
      }
    }
    
    async function processBook(bookId) {
      if (!confirm('Process all chapters in this book?')) return;
      
      showToast('⏳ Processing book... this may take a few minutes');
      
      try {
        const response = await fetch(window.location.href, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ action: 'processBook', bookId })
        });
        const data = await response.json();
        
        if (data.success) {
          const successCount = data.results.filter(r => r.status === 'success').length;
          showToast('✅ Processed ' + successCount + '/' + data.results.length + ' chapters');
          setTimeout(() => location.reload(), 1500);
        } else {
          showToast('❌ Error: ' + data.error, true);
        }
      } catch (error) {
        showToast('❌ Error: ' + error.message, true);
      }
    }
    
    async function processAllUnprocessed() {
      if (!confirm('Process ALL unprocessed/outdated chapters across ALL books? This may take a while.')) return;
      
      showToast('⏳ Processing all books... this may take several minutes');
      
      try {
        const response = await fetch(window.location.href, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ action: 'processAll' })
        });
        const data = await response.json();
        
        if (data.success) {
          const successCount = data.results.filter(r => r.status === 'success').length;
          const skippedCount = data.results.filter(r => r.status === 'skipped').length;
          showToast('✅ Processed ' + successCount + ', skipped ' + skippedCount);
          setTimeout(() => location.reload(), 2000);
        } else {
          showToast('❌ Error: ' + data.error, true);
        }
      } catch (error) {
        showToast('❌ Error: ' + error.message, true);
      }
    }
  </script>
</body>
</html>`;

      res.set('Content-Type', 'text/html');
      res.send(html);
      
    } catch (error) {
      logger.error('Error in explainableTermsDashboard:', error);
      res.status(500).send('Error loading dashboard: ' + error.message);
    }
  }
);

/**
 * Helper function to escape HTML
 */
function escapeHtml(text) {
  if (!text) return '';
  return text
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#039;');
}

// ============================================================================
// API A: Library / Search API
// ============================================================================

/**
 * GET /api/library
 * Returns paginated list of books with search support
 *
 * Query params:
 * - page (default: 1)
 * - pageSize (default: 20, max: 100)
 * - query (optional, searches title/author)
 * - userId (optional, for future user filtering)
 */
exports.getLibrary = onRequest(
  { region: 'australia-southeast1' },
  async (req, res) => {
    // Handle CORS preflight
    if (req.method === 'OPTIONS') {
      return handleOptions(req, res);
    }
    
    setCorsHeaders(res);
    
    try {
      const page = parseInt(req.query.page) || 1;
      const pageSize = Math.min(parseInt(req.query.pageSize) || 20, 100);
      const searchQuery = req.query.query ? req.query.query.trim().toLowerCase() : null;
      const userId = req.query.userId || null;

      // Create cache key
      const cacheKey = `library_${page}_${pageSize}_${searchQuery || ''}_${userId || ''}`;
      
      // Check cache
      const cached = libraryCache.get(cacheKey);
      if (cached) {
        logger.info(`Cache hit for library API: ${cacheKey}`);
        return res.json(cached);
      }

      const db = admin.firestore();
      let query = db.collection('books').orderBy('title');

      // Apply search filter if provided
      if (searchQuery) {
        // Firestore doesn't support full-text search natively
        // We'll fetch all and filter client-side (or use Algolia/Elasticsearch in production)
        // For now, we'll do a simple prefix match on title/author
        query = db.collection('books');
      }

      // Get total count for pagination
      const allSnapshot = await db.collection('books').get();
      let allBooks = [];
      
      allSnapshot.forEach(doc => {
        const data = doc.data();
        allBooks.push({
          id: data.id || doc.id,
          title: data.title || 'Unknown',
          author: data.author || 'Unknown',
          description: data.description || null,
          coverUrl: data.coverUrl || null,
          chapters: data.chapters || [],
          hasDescription: data.hasDescription || false
        });
      });

      // Apply search filter
      if (searchQuery) {
        allBooks = allBooks.filter(book => {
          const titleMatch = book.title.toLowerCase().includes(searchQuery);
          const authorMatch = book.author.toLowerCase().includes(searchQuery);
          return titleMatch || authorMatch;
        });
      }

      // Sort by title
      allBooks.sort((a, b) => a.title.localeCompare(b.title));

      // Calculate pagination
      const total = allBooks.length;
      const startIndex = (page - 1) * pageSize;
      const endIndex = startIndex + pageSize;
      const paginatedBooks = allBooks.slice(startIndex, endIndex);

      // Build response with minimal payload
      const response = {
        books: paginatedBooks.map(book => ({
          id: book.id,
          title: book.title,
          author: book.author,
          coverUrl: book.coverUrl,
          shortDescription: book.description
            ? book.description.substring(0, 150) + (book.description.length > 150 ? '...' : '')
            : null,
          chapterCount: book.chapters ? book.chapters.length : 0,
          hasDescription: book.hasDescription
        })),
        pagination: {
          page: page,
          pageSize: pageSize,
          total: total,
          hasMore: endIndex < total
        }
      };

      // Cache for 5 minutes
      libraryCache.set(cacheKey, response, 5 * 60 * 1000);

      res.json(response);
    } catch (error) {
      logger.error('Error in getLibrary:', error);
      res.status(500).json({
        success: false,
        error: error.message
      });
    }
  }
);

// ============================================================================
// API B: Chapter Index API
// ============================================================================

/**
 * POST /api/books/:bookId/chapters/:chapterId/prep
 * Trigger processing of chapter word-timing data
 *
 * This fetches the raw JSON from GCS, processes it, and stores the index in Firestore
 */
exports.prepChapterIndex = onRequest(
  { region: 'australia-southeast1' },
  async (req, res) => {
    // Handle CORS preflight
    if (req.method === 'OPTIONS') {
      return handleOptions(req, res);
    }
    
    setCorsHeaders(res);
    
    try {
      // Parse path parameters manually (Firebase Functions v2 doesn't do this automatically)
      const pathParts = extractPathParams(req);
      logger.info(`DEBUG prepChapterIndex: req.path = "${req.path}", req.url = "${req.url}", pathParts = [${pathParts.join(', ')}]`);
      const bookId = pathParts[0];
      const chapterId = pathParts[1];

      if (!bookId || !chapterId) {
        logger.error(`DEBUG prepChapterIndex: Missing params - bookId: "${bookId}", chapterId: "${chapterId}"`);
        return res.status(400).json({
          success: false,
          error: 'Missing bookId or chapterId'
        });
      }

      logger.info(`Processing chapter index for book ${bookId}, chapter ${chapterId}`);

      const db = admin.firestore();
      
      // Try to get chapter from Firestore first
      let jsonUrl = null;
      const bookDoc = await db.collection('books').doc(bookId).get();
      
      if (bookDoc.exists) {
        const bookData = bookDoc.data();
        const chapters = bookData.chapters || [];
        
        // Try exact match first
        let chapter = chapters.find(ch => ch.id === chapterId);
        
        // If not found, try normalized comparison (handle URL encoding, spaces, etc.)
        if (!chapter) {
          logger.warn(`Exact match not found for chapterId: ${chapterId}`);
          logger.info(`Available chapter IDs: ${chapters.map(ch => ch.id).join(', ')}`);
          
          // Try to find by normalizing both IDs (lowercase, replace spaces/hyphens)
          const normalizeId = (id) => id.toLowerCase().replace(/[\s\-_]/g, '');
          const normalizedChapterId = normalizeId(chapterId);
          
          chapter = chapters.find(ch => {
            const normalizedChId = normalizeId(ch.id);
            return normalizedChId === normalizedChapterId;
          });
          
          if (chapter) {
            logger.info(`Found chapter using normalized comparison: ${chapter.id}`);
          }
        }
        
        if (chapter && chapter.jsonUrl) {
          jsonUrl = chapter.jsonUrl;
          logger.info(`Found chapter in Firestore: ${chapter.id}, jsonUrl: ${jsonUrl}`);
        }
      }
      
      // Fallback: Construct JSON URL from chapterId pattern if not found in Firestore
      // Chapter ID format: {bookId}-{chapterName}
      // Example: "9780062315007-part two" -> chapterName = "part two"
      if (!jsonUrl) {
        logger.info(`Chapter not found in Firestore, constructing URL from chapterId pattern...`);
        const chapterNameMatch = chapterId.match(new RegExp(`^${bookId.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}-(.+)$`));
        
        if (!chapterNameMatch) {
          logger.error(`Invalid chapterId format: ${chapterId}. Expected: ${bookId}-{chapterName}`);
          return res.status(400).json({
            success: false,
            error: `Invalid chapterId format. Expected: ${bookId}-{chapterName}`
          });
        }
        
        const chapterName = chapterNameMatch[1]; // e.g., "part two"
        jsonUrl = `${BASE_URL}/${BUCKET_NAME}/${bookId}/${chapterName}.json`;
        logger.info(`Constructed JSON URL from chapterId: ${jsonUrl}`);
      }

      // Fetch raw JSON from GCS with retry logic
      logger.info(`Fetching JSON from: ${jsonUrl}`);
      let jsonResponse;
      let retries = 3;
      let lastError;
      
      while (retries > 0) {
        try {
          jsonResponse = await axios.get(jsonUrl, {
            timeout: 30000,
            responseType: 'json'
          });
          break; // Success, exit retry loop
        } catch (error) {
          lastError = error;
          retries--;
          if (retries > 0) {
            logger.warn(`Retry ${3 - retries}/3 for GCS fetch: ${jsonUrl}`);
            await new Promise(resolve => setTimeout(resolve, 1000)); // Wait 1s before retry
          }
        }
      }

      if (!jsonResponse || !jsonResponse.data) {
        logger.error(`Failed to fetch JSON after retries: ${jsonUrl}, error: ${lastError?.message || 'Unknown error'}`);
        return res.status(404).json({
          success: false,
          error: `Chapter JSON not found at ${jsonUrl}: ${lastError?.message || 'Unknown error'}`
        });
      }

      // Parse transcript using our parser (replicates TranscriptService.parseTranscript)
      logger.info('Parsing transcript...');
      const transcriptData = parseTranscript(jsonResponse.data);

      // Build time buckets for fast scrubbing (optional optimization)
      const timeBuckets = {};
      const bucketSize = 1.0; // 1 second buckets
      
      transcriptData.words.forEach(word => {
        const bucket = Math.floor(word.start / bucketSize);
        if (!timeBuckets[bucket]) {
          timeBuckets[bucket] = [];
        }
        // Store original JSON index in bucket
        timeBuckets[bucket].push(word.index);
      });

      // Store processed index in GCS (not Firestore - avoids index limit errors)
      const {Storage} = require('@google-cloud/storage');
      const storage = new Storage({ projectId: BUCKET_PROJECT_ID });
      const bucket = storage.bucket(BUCKET_NAME);

      // Create processed index file name (sanitize chapterId for filename)
      const sanitizedChapterId = chapterId.replace(/[^a-zA-Z0-9\-_]/g, '_');
      const processedIndexFileName = `${bookId}/${sanitizedChapterId}-index.json`;
      const file = bucket.file(processedIndexFileName);

      // Prepare data for storage (without Firestore metadata)
      const indexDataToStore = {
        fullText: transcriptData.fullText,
        sentences: transcriptData.sentences,
        words: transcriptData.words,
        timeBuckets: timeBuckets,
        processedAt: new Date().toISOString(),
        chapterId: chapterId,
        bookId: bookId
      };

      // Upload to GCS
      await file.save(JSON.stringify(indexDataToStore), {
        contentType: 'application/json',
        metadata: {
          cacheControl: 'public, max-age=31536000', // Cache for 1 year
        }
      });

      // Make file publicly readable
      await file.makePublic();

      // Store only metadata in Firestore (not the full data - avoids index limit)
      const indexRef = db
        .collection('books')
        .doc(bookId)
        .collection('chapterIndexes')
        .doc(chapterId);

      const processedIndexUrl = `${BASE_URL}/${BUCKET_NAME}/${processedIndexFileName}`;
      await indexRef.set({
        processedIndexUrl: processedIndexUrl,
        processedAt: admin.firestore.FieldValue.serverTimestamp(),
        chapterId: chapterId,
        bookId: bookId,
        wordCount: transcriptData.words.length,
        sentenceCount: transcriptData.sentences.length
      });

      // Cache in memory
      const cacheKey = `chapter_index_${bookId}_${chapterId}`;
      chapterIndexCache.set(cacheKey, {
        fullText: indexDataToStore.fullText,
        sentences: indexDataToStore.sentences,
        words: indexDataToStore.words,
        timeBuckets: indexDataToStore.timeBuckets
      }, 60 * 60 * 1000); // 1 hour

      logger.info(`✅ Successfully processed chapter index for ${bookId}/${chapterId}`);

      res.json({
        success: true,
        message: 'Chapter index processed successfully',
        wordCount: transcriptData.words.length,
        sentenceCount: transcriptData.sentences.length
      });

    } catch (error) {
      logger.error('Error in prepChapterIndex:', error);
      res.status(500).json({
        success: false,
        error: error.message
      });
    }
  }
);

/**
 * GET /api/books/:bookId/chapters/:chapterId/index
 * Get precomputed chapter index
 *
 * If index doesn't exist, triggers processing and returns when ready
 */
exports.getChapterIndex = onRequest(
  { region: 'australia-southeast1' },
  async (req, res) => {
    // Handle CORS preflight
    if (req.method === 'OPTIONS') {
      return handleOptions(req, res);
    }
    
    setCorsHeaders(res);
    
    try {
      // Parse path parameters manually (Firebase Functions v2 doesn't do this automatically)
      const pathParts = extractPathParams(req);
      logger.info(`DEBUG getChapterIndex: req.path = "${req.path}", req.url = "${req.url}", pathParts = [${pathParts.join(', ')}]`);
      const bookId = pathParts[0];
      const chapterId = pathParts[1];

      if (!bookId || !chapterId) {
        logger.error(`DEBUG getChapterIndex: Missing params - bookId: "${bookId}", chapterId: "${chapterId}"`);
        return res.status(400).json({
          success: false,
          error: 'Missing bookId or chapterId'
        });
      }

      const cacheKey = `chapter_index_${bookId}_${chapterId}`;
      
      // Check memory cache first
      const cached = chapterIndexCache.get(cacheKey);
      if (cached) {
        logger.info(`Cache hit for chapter index: ${cacheKey}`);
        return res.json(cached);
      }

      const db = admin.firestore();
      
      // Check Firestore
      const indexRef = db
        .collection('books')
        .doc(bookId)
        .collection('chapterIndexes')
        .doc(chapterId);

      const indexDoc = await indexRef.get();

      if (indexDoc.exists) {
        const indexData = indexDoc.data();
        
        // If we have a processedIndexUrl, fetch from GCS (new format)
        if (indexData.processedIndexUrl) {
          logger.info(`Fetching processed index from GCS: ${indexData.processedIndexUrl}`);
          try {
            const gcsResponse = await axios.get(indexData.processedIndexUrl, {
              timeout: 30000,
              responseType: 'json'
            });
            
            const response = {
              fullText: gcsResponse.data.fullText,
              sentences: gcsResponse.data.sentences,
              words: gcsResponse.data.words,
              timeBuckets: gcsResponse.data.timeBuckets || {}
            };
            
            // Cache in memory
            chapterIndexCache.set(cacheKey, response, 60 * 60 * 1000);
            
            return res.json(response);
          } catch (gcsError) {
            logger.error(`Failed to fetch from GCS, will reprocess: ${gcsError.message}`);
            // Fall through to processing (file might be missing, reprocess it)
          }
        } else {
          // Legacy format - data stored directly in Firestore (shouldn't happen for new chapters)
          logger.warn('Legacy Firestore format detected, will reprocess and store in GCS');
          // Fall through to processing
        }
      }

      // Index doesn't exist - trigger processing
      logger.info(`Chapter index not found, triggering processing for ${bookId}/${chapterId}`);
      
      // Try to get chapter from Firestore first
      let jsonUrl = null;
      const bookDoc = await db.collection('books').doc(bookId).get();
      
      if (bookDoc.exists) {
        const bookData = bookDoc.data();
        const chapters = bookData.chapters || [];
        
        // Try exact match first
        let chapter = chapters.find(ch => ch.id === chapterId);
        
        // If not found, try normalized comparison (handle URL encoding, spaces, etc.)
        if (!chapter) {
          logger.warn(`Exact match not found for chapterId: ${chapterId}`);
          logger.info(`Available chapter IDs: ${chapters.map(ch => ch.id).join(', ')}`);
          
          // Try to find by normalizing both IDs (lowercase, replace spaces/hyphens)
          const normalizeId = (id) => id.toLowerCase().replace(/[\s\-_]/g, '');
          const normalizedChapterId = normalizeId(chapterId);
          
          chapter = chapters.find(ch => {
            const normalizedChId = normalizeId(ch.id);
            return normalizedChId === normalizedChapterId;
          });
          
          if (chapter) {
            logger.info(`Found chapter using normalized comparison: ${chapter.id}`);
          }
        }
        
        if (chapter && chapter.jsonUrl) {
          jsonUrl = chapter.jsonUrl;
          logger.info(`Found chapter in Firestore: ${chapter.id}, jsonUrl: ${jsonUrl}`);
        }
      }
      
      // Fallback: Construct JSON URL from chapterId pattern if not found in Firestore
      // Chapter ID format: {bookId}-{chapterName}
      // Example: "9780062315007-part two" -> chapterName = "part two"
      if (!jsonUrl) {
        logger.info(`Chapter not found in Firestore, constructing URL from chapterId pattern...`);
        const chapterNameMatch = chapterId.match(new RegExp(`^${bookId.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}-(.+)$`));
        
        if (!chapterNameMatch) {
          logger.error(`Invalid chapterId format: ${chapterId}. Expected: ${bookId}-{chapterName}`);
          return res.status(400).json({
            success: false,
            error: `Invalid chapterId format. Expected: ${bookId}-{chapterName}`
          });
        }
        
        const chapterName = chapterNameMatch[1]; // e.g., "part two"
        jsonUrl = `${BASE_URL}/${BUCKET_NAME}/${bookId}/${chapterName}.json`;
        logger.info(`Constructed JSON URL from chapterId: ${jsonUrl}`);
      }

      // Fetch and process with retry logic
      let jsonResponse;
      let retries = 3;
      let lastError;
      
      while (retries > 0) {
        try {
          jsonResponse = await axios.get(jsonUrl, {
            timeout: 30000,
            responseType: 'json'
          });
          break; // Success, exit retry loop
        } catch (error) {
          lastError = error;
          retries--;
          if (retries > 0) {
            logger.warn(`Retry ${3 - retries}/3 for GCS fetch: ${jsonUrl}`);
            await new Promise(resolve => setTimeout(resolve, 1000)); // Wait 1s before retry
          }
        }
      }

      if (!jsonResponse || !jsonResponse.data) {
        logger.error(`Failed to fetch JSON after retries: ${jsonUrl}, error: ${lastError?.message || 'Unknown error'}`);
        return res.status(404).json({
          success: false,
          error: `Chapter JSON not found at ${jsonUrl}: ${lastError?.message || 'Unknown error'}`
        });
      }

      const transcriptData = parseTranscript(jsonResponse.data);

      // Build time buckets
      const timeBuckets = {};
      const bucketSize = 1.0;
      transcriptData.words.forEach(word => {
        const bucket = Math.floor(word.start / bucketSize);
        if (!timeBuckets[bucket]) {
          timeBuckets[bucket] = [];
        }
        timeBuckets[bucket].push(word.index);
      });

      // Store processed index in GCS (not Firestore - avoids index limit errors)
      const {Storage} = require('@google-cloud/storage');
      const storage = new Storage({ projectId: BUCKET_PROJECT_ID });
      const bucket = storage.bucket(BUCKET_NAME);

      // Create processed index file name (sanitize chapterId for filename)
      const sanitizedChapterId = chapterId.replace(/[^a-zA-Z0-9\-_]/g, '_');
      const processedIndexFileName = `${bookId}/${sanitizedChapterId}-index.json`;
      const file = bucket.file(processedIndexFileName);

      // Prepare data for storage
      const indexDataToStore = {
        fullText: transcriptData.fullText,
        sentences: transcriptData.sentences,
        words: transcriptData.words,
        timeBuckets: timeBuckets,
        processedAt: new Date().toISOString(),
        chapterId: chapterId,
        bookId: bookId
      };

      // Upload to GCS
      await file.save(JSON.stringify(indexDataToStore), {
        contentType: 'application/json',
        metadata: {
          cacheControl: 'public, max-age=31536000', // Cache for 1 year
        }
      });

      // Make file publicly readable
      await file.makePublic();

      // Store only metadata in Firestore (not the full data - avoids index limit)
      const processedIndexUrl = `${BASE_URL}/${BUCKET_NAME}/${processedIndexFileName}`;
      await indexRef.set({
        processedIndexUrl: processedIndexUrl,
        processedAt: admin.firestore.FieldValue.serverTimestamp(),
        chapterId: chapterId,
        bookId: bookId,
        wordCount: transcriptData.words.length,
        sentenceCount: transcriptData.sentences.length
      });

      // Cache in memory
      chapterIndexCache.set(cacheKey, {
        fullText: indexDataToStore.fullText,
        sentences: indexDataToStore.sentences,
        words: indexDataToStore.words,
        timeBuckets: indexDataToStore.timeBuckets
      }, 60 * 60 * 1000);

      // Return response (without Firestore metadata)
      res.json({
        fullText: transcriptData.fullText,
        sentences: transcriptData.sentences,
        words: transcriptData.words,
        timeBuckets: timeBuckets
      });

    } catch (error) {
      logger.error('Error in getChapterIndex:', error);
      res.status(500).json({
        success: false,
        error: error.message
      });
    }
  }
);

// ============================================================================
// API C: Vocabulary API (Future - Scaffolded)
// ============================================================================

/**
 * POST /api/books/:bookId/chapters/:chapterId/vocab-prep
 * Trigger vocabulary processing for a chapter
 *
 * TODO: Future implementation
 * - Read the precomputed chapter index
 * - Identify candidate words worth explaining (non-stopwords, less frequent, etc.)
 * - Integrate with OpenAI/LLM to generate short explanations/definitions
 * - Store vocab data in Firestore: books/{bookId}/vocab/{chapterId}
 */
exports.prepVocab = onRequest(
  { region: 'australia-southeast1' },
  async (req, res) => {
    // Handle CORS preflight
    if (req.method === 'OPTIONS') {
      return handleOptions(req, res);
    }
    
    setCorsHeaders(res);
    
    try {
      // Parse path parameters manually (Firebase Functions v2 doesn't do this automatically)
      const pathParts = extractPathParams(req);
      logger.info(`DEBUG prepVocab: req.path = "${req.path}", req.url = "${req.url}", pathParts = [${pathParts.join(', ')}]`);
      const bookId = pathParts[0];
      const chapterId = pathParts[1];

      if (!bookId || !chapterId) {
        logger.error(`DEBUG prepVocab: Missing params - bookId: "${bookId}", chapterId: "${chapterId}"`);
        return res.status(400).json({
          success: false,
          error: 'Missing bookId or chapterId'
        });
      }

      // TODO: Implement vocabulary processing
      // 1. Get chapter index from Firestore
      // 2. Analyze words for frequency, difficulty, etc.
      // 3. Filter to candidate words (non-stopwords, less common)
      // 4. Call OpenAI/LLM API to generate explanations
      // 5. Store in Firestore: books/{bookId}/vocab/{chapterId}

      res.json({
        success: false,
        message: 'Vocabulary processing not yet implemented',
        todo: [
          'Read precomputed chapter index',
          'Identify candidate words (non-stopwords, less frequent)',
          'Integrate with OpenAI/LLM for explanations',
          'Store vocab data in Firestore'
        ]
      });

    } catch (error) {
      logger.error('Error in prepVocab:', error);
      res.status(500).json({
        success: false,
        error: error.message
      });
    }
  }
);

/**
 * GET /api/books/:bookId/chapters/:chapterId/vocab
 * Get vocabulary data for a chapter
 *
 * TODO: Future implementation
 * - Read vocab data from Firestore: books/{bookId}/vocab/{chapterId}
 * - Return list of explainable words with definitions
 */
exports.getVocab = onRequest(
  { region: 'australia-southeast1' },
  async (req, res) => {
    // Handle CORS preflight
    if (req.method === 'OPTIONS') {
      return handleOptions(req, res);
    }
    
    setCorsHeaders(res);
    
    try {
      // Parse path parameters manually (Firebase Functions v2 doesn't do this automatically)
      const pathParts = extractPathParams(req);
      logger.info(`DEBUG getVocab: req.path = "${req.path}", req.url = "${req.url}", pathParts = [${pathParts.join(', ')}]`);
      const bookId = pathParts[0];
      const chapterId = pathParts[1];

      if (!bookId || !chapterId) {
        logger.error(`DEBUG getVocab: Missing params - bookId: "${bookId}", chapterId: "${chapterId}"`);
        return res.status(400).json({
          success: false,
          error: 'Missing bookId or chapterId'
        });
      }

      const db = admin.firestore();
      const vocabRef = db
        .collection('books')
        .doc(bookId)
        .collection('vocab')
        .doc(chapterId);

      const vocabDoc = await vocabRef.get();

      if (!vocabDoc.exists) {
        return res.status(404).json({
          success: false,
          error: 'Vocabulary data not found. Call /vocab-prep first.'
        });
      }

      // TODO: Return vocab data when implemented
      res.json({
        success: false,
        message: 'Vocabulary API not yet implemented',
        vocab: []
      });

    } catch (error) {
      logger.error('Error in getVocab:', error);
      res.status(500).json({
        success: false,
        error: error.message
      });
    }
  }
);

// ============================================================================
// Learning Path: Book Enrichment API
// ============================================================================

/**
 * Initialize OpenAI client
 */
function getOpenAIClient() {
  const OpenAI = require('openai');
  return new OpenAI({
    apiKey: process.env.OPENAI_API_KEY
  });
}

/**
 * POST /enrichBookMetadata/{isbn}
 * Uses OpenAI to analyze a book and generate series/genre/theme data
 * 
 * This enriches a single book with:
 * - Series information (name, position, total books, all ISBNs)
 * - Genre tags (3-5 genres)
 * - Theme tags (3-5 themes)
 * - Related book ISBNs (similar books)
 */
exports.enrichBookMetadata = onRequest(
  {
    region: 'australia-southeast1',
    secrets: [openaiApiKey],
    timeoutSeconds: 120,
    memory: '512MiB'
  },
  async (req, res) => {
    // Handle CORS preflight
    if (req.method === 'OPTIONS') {
      return handleOptions(req, res);
    }
    
    setCorsHeaders(res);
    
    try {
      const pathParts = extractPathParams(req, 1);
      const isbn = pathParts[0];
      
      if (!isbn) {
        return res.status(400).json({
          success: false,
          error: 'Missing ISBN. URL format: /enrichBookMetadata/{isbn}'
        });
      }
      
      logger.info(`📚 Enriching book metadata for ISBN: ${isbn}`);
      
      // Set OpenAI API key from secret
      process.env.OPENAI_API_KEY = openaiApiKey.value();
      
      const db = admin.firestore();
      
      // Get book from Firestore
      const bookDoc = await db.collection('books').doc(isbn).get();
      if (!bookDoc.exists) {
        return res.status(404).json({
          success: false,
          error: `Book ${isbn} not found in catalogue`
        });
      }
      
      const bookData = bookDoc.data();
      const title = bookData.title || 'Unknown Title';
      const author = bookData.author || 'Unknown Author';
      const description = bookData.description || '';
      
      // Call OpenAI to analyze the book
      const openai = getOpenAIClient();
      
      const prompt = `Analyze this book and provide detailed metadata in JSON format.

BOOK INFORMATION:
- Title: ${title}
- Author: ${author}
- ISBN: ${isbn}
- Description: ${description || 'No description available'}

INSTRUCTIONS:
1. Determine if this book is part of a series. If yes, provide the series name, this book's position (1-indexed), total number of books in the series, and ISBNs of ALL books in the series in order.
2. Identify 3-5 relevant genre tags (lowercase, hyphenated for multi-word, e.g., "self-help", "young-adult", "science-fiction")
3. Identify 3-5 thematic tags that describe the book's themes (lowercase, e.g., "survival", "personal-growth", "leadership")
4. Suggest 3-5 ISBNs of similar/related books that readers might enjoy

IMPORTANT:
- For series detection, be thorough. Look for common series patterns in the title.
- ISBNs should be ISBN-10 format (10 digits) when possible.
- If you're not certain about series information, set series to null.
- Only include genres and themes you're confident about.

Return ONLY valid JSON in this exact format:
{
  "series": {
    "name": "Series Name or null",
    "position": 1,
    "totalBooks": 3,
    "allIsbns": ["isbn1", "isbn2", "isbn3"]
  },
  "genres": ["genre1", "genre2", "genre3"],
  "themes": ["theme1", "theme2", "theme3"],
  "relatedIsbns": ["isbn1", "isbn2", "isbn3"]
}

If the book is NOT part of a series, set "series" to null.`;

      const completion = await openai.chat.completions.create({
        model: 'gpt-4o',
        messages: [
          {
            role: 'system',
            content: 'You are a book metadata expert. You analyze books and provide accurate series information, genre tags, themes, and related book recommendations. Always return valid JSON.'
          },
          {
            role: 'user',
            content: prompt
          }
        ],
        temperature: 0.3,
        max_tokens: 1000
      });
      
      const responseText = completion.choices[0]?.message?.content || '';
      
      // Parse the JSON response
      let enrichedData;
      try {
        // Extract JSON from response (handle markdown code blocks)
        let jsonStr = responseText;
        const jsonMatch = responseText.match(/```(?:json)?\s*([\s\S]*?)```/);
        if (jsonMatch) {
          jsonStr = jsonMatch[1].trim();
        }
        enrichedData = JSON.parse(jsonStr);
      } catch (parseError) {
        logger.error(`Failed to parse OpenAI response: ${responseText}`);
        return res.status(500).json({
          success: false,
          error: 'Failed to parse AI response',
          rawResponse: responseText
        });
      }
      
      // Build the enrichedData object for Firestore
      const firestoreEnrichedData = {
        genres: enrichedData.genres || [],
        themes: enrichedData.themes || [],
        relatedIsbns: enrichedData.relatedIsbns || [],
        enrichedAt: admin.firestore.FieldValue.serverTimestamp()
      };
      
      // Add series if present and valid
      if (enrichedData.series && enrichedData.series.name) {
        firestoreEnrichedData.series = {
          name: enrichedData.series.name,
          position: enrichedData.series.position || 1,
          totalBooks: enrichedData.series.totalBooks || 1,
          allIsbns: enrichedData.series.allIsbns || [isbn]
        };
      }
      
      // Update book document with enrichedData
      await db.collection('books').doc(isbn).update({
        enrichedData: firestoreEnrichedData
      });
      
      logger.info(`✅ Successfully enriched book: ${isbn} - ${title}`);
      
      res.json({
        success: true,
        isbn: isbn,
        title: title,
        enrichedData: firestoreEnrichedData
      });
      
    } catch (error) {
      logger.error('Error in enrichBookMetadata:', error);
      res.status(500).json({
        success: false,
        error: error.message
      });
    }
  }
);

/**
 * POST /enrichAllBooks
 * Batch process all books in the catalogue with AI enrichment
 * 
 * Query parameters:
 * - forceUpdate=true : Re-enrich books even if they already have enrichedData
 */
exports.enrichAllBooks = onRequest(
  {
    region: 'australia-southeast1',
    secrets: [openaiApiKey],
    timeoutSeconds: 540, // 9 minutes max
    memory: '1GiB'
  },
  async (req, res) => {
    // Handle CORS preflight
    if (req.method === 'OPTIONS') {
      return handleOptions(req, res);
    }
    
    setCorsHeaders(res);
    
    try {
      const forceUpdate = req.query.forceUpdate === 'true';
      
      logger.info(`📚 Starting batch book enrichment (forceUpdate: ${forceUpdate})`);
      
      // Set OpenAI API key from secret
      process.env.OPENAI_API_KEY = openaiApiKey.value();
      
      const db = admin.firestore();
      const openai = getOpenAIClient();
      
      // Get all books
      const booksSnapshot = await db.collection('books').get();
      
      const results = [];
      let processed = 0;
      let skipped = 0;
      let errors = 0;
      
      for (const bookDoc of booksSnapshot.docs) {
        const bookData = bookDoc.data();
        const isbn = bookDoc.id;
        const title = bookData.title || 'Unknown';
        const author = bookData.author || 'Unknown';
        const description = bookData.description || '';
        
        // Skip if already enriched (unless forceUpdate)
        if (bookData.enrichedData && !forceUpdate) {
          results.push({ isbn, title, status: 'skipped', reason: 'already enriched' });
          skipped++;
          continue;
        }
        
        try {
          logger.info(`Processing: ${isbn} - ${title}`);
          
          // Call OpenAI
          const prompt = `Analyze this book and provide metadata in JSON format.

BOOK: "${title}" by ${author}
ISBN: ${isbn}
Description: ${description || 'No description'}

Return JSON with:
- series: {name, position, totalBooks, allIsbns} or null if standalone
- genres: array of 3-5 genre tags (lowercase, hyphenated)
- themes: array of 3-5 theme tags (lowercase)
- relatedIsbns: array of 3-5 similar book ISBNs

Return ONLY valid JSON.`;

          const completion = await openai.chat.completions.create({
            model: 'gpt-4o',
            messages: [
              { role: 'system', content: 'You are a book metadata expert. Return only valid JSON.' },
              { role: 'user', content: prompt }
            ],
            temperature: 0.3,
            max_tokens: 800
          });
          
          const responseText = completion.choices[0]?.message?.content || '';
          
          // Parse response
          let enrichedData;
          try {
            let jsonStr = responseText;
            const jsonMatch = responseText.match(/```(?:json)?\s*([\s\S]*?)```/);
            if (jsonMatch) jsonStr = jsonMatch[1].trim();
            enrichedData = JSON.parse(jsonStr);
          } catch (parseError) {
            throw new Error(`JSON parse failed: ${responseText.substring(0, 200)}`);
          }
          
          // Build Firestore data
          const firestoreData = {
            genres: enrichedData.genres || [],
            themes: enrichedData.themes || [],
            relatedIsbns: enrichedData.relatedIsbns || [],
            enrichedAt: admin.firestore.FieldValue.serverTimestamp()
          };
          
          if (enrichedData.series && enrichedData.series.name) {
            firestoreData.series = {
              name: enrichedData.series.name,
              position: enrichedData.series.position || 1,
              totalBooks: enrichedData.series.totalBooks || 1,
              allIsbns: enrichedData.series.allIsbns || [isbn]
            };
          }
          
          // Update book
          await db.collection('books').doc(isbn).update({
            enrichedData: firestoreData
          });
          
          results.push({ 
            isbn, 
            title, 
            status: 'success',
            hasSeries: !!firestoreData.series,
            genreCount: firestoreData.genres.length
          });
          processed++;
          
          // Rate limiting delay (OpenAI has rate limits)
          await new Promise(resolve => setTimeout(resolve, 1500));
          
        } catch (bookError) {
          logger.error(`Error enriching ${isbn}:`, bookError);
          results.push({ isbn, title, status: 'error', error: bookError.message });
          errors++;
        }
      }
      
      logger.info(`✅ Batch enrichment complete: ${processed} processed, ${skipped} skipped, ${errors} errors`);
      
      res.json({
        success: true,
        summary: {
          total: booksSnapshot.docs.length,
          processed,
          skipped,
          errors
        },
        results
      });
      
    } catch (error) {
      logger.error('Error in enrichAllBooks:', error);
      res.status(500).json({
        success: false,
        error: error.message
      });
    }
  }
);

// ============================================================================
// Learning Path: Path Generation API
// ============================================================================

/**
 * Search Google Books API for book information
 * @param {string} query - Search query (title, author, or ISBN)
 * @returns {object|null} - Book info or null if not found
 */
async function searchGoogleBooks(query) {
  try {
    const response = await axios.get(
      `https://www.googleapis.com/books/v1/volumes?q=${encodeURIComponent(query)}&maxResults=5`,
      { timeout: 10000 }
    );
    
    if (!response.data.items || response.data.items.length === 0) {
      return null;
    }
    
    // Return the first result
    const item = response.data.items[0];
    const volumeInfo = item.volumeInfo;
    
    // Extract ISBN
    let isbn10 = null;
    let isbn13 = null;
    if (volumeInfo.industryIdentifiers) {
      const isbn10Obj = volumeInfo.industryIdentifiers.find(id => id.type === 'ISBN_10');
      const isbn13Obj = volumeInfo.industryIdentifiers.find(id => id.type === 'ISBN_13');
      if (isbn10Obj) isbn10 = isbn10Obj.identifier;
      if (isbn13Obj) isbn13 = isbn13Obj.identifier;
    }
    
    return {
      isbn: isbn10 || isbn13 || null,
      isbn10,
      isbn13,
      title: volumeInfo.title || 'Unknown Title',
      author: volumeInfo.authors?.[0] || 'Unknown Author',
      description: volumeInfo.description || null,
      coverUrl: volumeInfo.imageLinks?.thumbnail?.replace('http://', 'https://') || null,
      publisher: volumeInfo.publisher || null,
      publishedDate: volumeInfo.publishedDate || null
    };
  } catch (error) {
    logger.error(`Google Books search error for "${query}":`, error.message);
    return null;
  }
}

/**
 * Search Google Books by ISBN specifically
 */
async function searchGoogleBooksByIsbn(isbn) {
  return searchGoogleBooks(`isbn:${isbn}`);
}

/**
 * Get or create a phantom book entry
 */
async function getOrCreatePhantomBook(db, isbn, bookInfo, seriesInfo = null) {
  const phantomRef = db.collection('phantomBooks').doc(isbn);
  const existing = await phantomRef.get();
  
  if (existing.exists) {
    return existing.data();
  }
  
  // Create new phantom book
  const phantomData = {
    isbn,
    title: bookInfo.title,
    author: bookInfo.author,
    description: bookInfo.description || null,
    coverUrl: bookInfo.coverUrl || null,
    source: 'google-books',
    available: false,
    estimatedAvailability: '2026',
    publisher: bookInfo.publisher || null,
    publishedDate: bookInfo.publishedDate || null,
    createdAt: admin.firestore.FieldValue.serverTimestamp()
  };
  
  if (seriesInfo) {
    phantomData.series = seriesInfo;
  }
  
  await phantomRef.set(phantomData);
  logger.info(`Created phantom book: ${isbn} - ${bookInfo.title}`);
  
  return phantomData;
}

/**
 * POST /generateLearningPath
 * Creates a personalized 5-book reading path for a user
 * 
 * Request body:
 * {
 *   "userId": "firebase-uid",
 *   "startingBookIsbn": "0123456789",
 *   "preferences": {
 *     "genres": ["self-help", "business"],
 *     "booksPerMonth": 2
 *   }
 * }
 */
exports.generateLearningPath = onRequest(
  {
    region: 'australia-southeast1',
    secrets: [openaiApiKey],
    timeoutSeconds: 180,
    memory: '1GiB'
  },
  async (req, res) => {
    // Handle CORS preflight
    if (req.method === 'OPTIONS') {
      return handleOptions(req, res);
    }
    
    setCorsHeaders(res);
    
    try {
      // Parse request body
      const { userId, startingBookIsbn, preferences } = req.body;
      
      if (!userId || !startingBookIsbn) {
        return res.status(400).json({
          success: false,
          error: 'Missing required fields: userId, startingBookIsbn'
        });
      }
      
      logger.info(`🎯 Generating Learning Path for user ${userId}, starting with ${startingBookIsbn}`);
      
      // Set OpenAI API key from secret
      process.env.OPENAI_API_KEY = openaiApiKey.value();
      
      const db = admin.firestore();
      const openai = getOpenAIClient();
      
      // Get the starting book from catalogue
      const startingBookDoc = await db.collection('books').doc(startingBookIsbn).get();
      
      let startingBook;
      let isStartingBookAvailable = true;
      
      if (startingBookDoc.exists) {
        startingBook = startingBookDoc.data();
      } else {
        // Starting book not in catalogue - search Google Books
        const googleBookInfo = await searchGoogleBooksByIsbn(startingBookIsbn);
        if (!googleBookInfo) {
          return res.status(404).json({
            success: false,
            error: `Book ${startingBookIsbn} not found in catalogue or Google Books`
          });
        }
        startingBook = googleBookInfo;
        isStartingBookAvailable = false;
        
        // Create phantom book entry
        await getOrCreatePhantomBook(db, startingBookIsbn, startingBook);
      }
      
      // Initialize path books array
      const pathBooks = [];
      const usedIsbns = new Set([startingBookIsbn]);
      
      // Position 1: Starting book
      pathBooks.push({
        isbn: startingBookIsbn,
        title: startingBook.title,
        author: startingBook.author,
        coverUrl: startingBook.coverUrl || null,
        position: 1,
        status: 'reading',
        available: isStartingBookAvailable,
        reason: 'Your chosen starting book',
        seriesInfo: startingBook.enrichedData?.series || null
      });
      
      // Get all books in our catalogue for availability checking
      const catalogueSnapshot = await db.collection('books').get();
      const catalogueIsbns = new Set(catalogueSnapshot.docs.map(doc => doc.id));
      
      // Check if starting book is part of a series
      const seriesInfo = startingBook.enrichedData?.series;
      
      // PRIORITY 1: Add remaining series books (if applicable)
      if (seriesInfo && seriesInfo.allIsbns && seriesInfo.allIsbns.length > 1) {
        logger.info(`📖 Book is part of series: ${seriesInfo.name} (position ${seriesInfo.position} of ${seriesInfo.totalBooks})`);
        
        // Get remaining books in series order
        const remainingSeriesIsbns = seriesInfo.allIsbns.filter(
          (isbn, index) => index >= seriesInfo.position && !usedIsbns.has(isbn)
        );
        
        for (const seriesIsbn of remainingSeriesIsbns) {
          if (pathBooks.length >= 5) break;
          
          // Check if in catalogue
          const inCatalogue = catalogueIsbns.has(seriesIsbn);
          let bookInfo;
          
          if (inCatalogue) {
            const bookDoc = await db.collection('books').doc(seriesIsbn).get();
            bookInfo = bookDoc.data();
          } else {
            // Fetch from Google Books
            bookInfo = await searchGoogleBooksByIsbn(seriesIsbn);
            if (bookInfo) {
              await getOrCreatePhantomBook(db, seriesIsbn, bookInfo, {
                name: seriesInfo.name,
                position: seriesInfo.allIsbns.indexOf(seriesIsbn) + 1,
                totalBooks: seriesInfo.totalBooks,
                allIsbns: seriesInfo.allIsbns
              });
            }
          }
          
          if (bookInfo) {
            const position = seriesInfo.allIsbns.indexOf(seriesIsbn) + 1;
            pathBooks.push({
              isbn: seriesIsbn,
              title: bookInfo.title,
              author: bookInfo.author,
              coverUrl: bookInfo.coverUrl || null,
              position: pathBooks.length + 1,
              status: 'upcoming',
              available: inCatalogue,
              reason: `Book ${position} in the ${seriesInfo.name} series`,
              seriesInfo: {
                name: seriesInfo.name,
                position,
                totalBooks: seriesInfo.totalBooks,
                allIsbns: seriesInfo.allIsbns
              }
            });
            usedIsbns.add(seriesIsbn);
          }
        }
      }
      
      // PRIORITY 2: Same author books (if we need more books)
      if (pathBooks.length < 5) {
        // Find other books by same author in catalogue
        const authorBooks = catalogueSnapshot.docs
          .filter(doc => {
            const data = doc.data();
            return data.author === startingBook.author && !usedIsbns.has(doc.id);
          })
          .slice(0, 5 - pathBooks.length);
        
        for (const authorBookDoc of authorBooks) {
          if (pathBooks.length >= 5) break;
          
          const bookData = authorBookDoc.data();
          pathBooks.push({
            isbn: authorBookDoc.id,
            title: bookData.title,
            author: bookData.author,
            coverUrl: bookData.coverUrl || null,
            position: pathBooks.length + 1,
            status: 'upcoming',
            available: true,
            reason: `Another book by ${startingBook.author}`,
            seriesInfo: bookData.enrichedData?.series || null
          });
          usedIsbns.add(authorBookDoc.id);
        }
      }
      
      // PRIORITY 3: Use AI to recommend remaining books
      if (pathBooks.length < 5) {
        const slotsNeeded = 5 - pathBooks.length;
        const userGenres = preferences?.genres || [];
        
        logger.info(`🤖 Using AI to fill ${slotsNeeded} remaining slots`);
        
        // Build context for AI
        const currentBooks = pathBooks.map(b => `"${b.title}" by ${b.author}`).join(', ');
        const availableBooksInCatalogue = catalogueSnapshot.docs
          .filter(doc => !usedIsbns.has(doc.id))
          .map(doc => {
            const data = doc.data();
            return `ISBN: ${doc.id}, Title: "${data.title}", Author: ${data.author}, Genres: ${data.enrichedData?.genres?.join(', ') || 'unknown'}`;
          })
          .join('\n');
        
        const aiPrompt = `You are a book recommendation expert. A user is building a reading path.

CURRENT READING PATH:
${currentBooks}

USER'S PREFERRED GENRES: ${userGenres.join(', ') || 'Not specified'}

BOOKS AVAILABLE IN OUR CATALOGUE (prefer these):
${availableBooksInCatalogue || 'No additional books available'}

TASK: Recommend exactly ${slotsNeeded} more book(s) that would complement this reading path. 
- Prioritize books from the catalogue list above
- If catalogue books don't fit well, suggest other books (we'll mark them as "coming soon")
- Focus on similar themes, genres, or books that readers of the current path would enjoy
- For each book, explain why it's a good fit in 1 sentence

Return JSON array:
[
  {
    "isbn": "book-isbn-or-search-term",
    "title": "Book Title",
    "author": "Author Name",
    "reason": "Why this book fits the path",
    "inCatalogue": true/false
  }
]`;

        try {
          const completion = await openai.chat.completions.create({
            model: 'gpt-4o',
            messages: [
              { role: 'system', content: 'You are a book recommendation expert. Return only valid JSON arrays.' },
              { role: 'user', content: aiPrompt }
            ],
            temperature: 0.5,
            max_tokens: 1000
          });
          
          const responseText = completion.choices[0]?.message?.content || '[]';
          
          // Parse AI response
          let recommendations;
          try {
            let jsonStr = responseText;
            const jsonMatch = responseText.match(/```(?:json)?\s*([\s\S]*?)```/);
            if (jsonMatch) jsonStr = jsonMatch[1].trim();
            recommendations = JSON.parse(jsonStr);
          } catch (parseError) {
            logger.error(`Failed to parse AI recommendations: ${responseText}`);
            recommendations = [];
          }
          
          // Process each recommendation
          for (const rec of recommendations) {
            if (pathBooks.length >= 5) break;
            
            let isbn = rec.isbn;
            let bookInfo = null;
            let inCatalogue = rec.inCatalogue;
            
            // Check if in catalogue
            if (catalogueIsbns.has(isbn)) {
              const bookDoc = await db.collection('books').doc(isbn).get();
              bookInfo = bookDoc.data();
              inCatalogue = true;
            } else if (!inCatalogue) {
              // Search Google Books
              bookInfo = await searchGoogleBooksByIsbn(isbn);
              if (!bookInfo) {
                // Try searching by title
                bookInfo = await searchGoogleBooks(`${rec.title} ${rec.author}`);
                if (bookInfo && bookInfo.isbn) {
                  isbn = bookInfo.isbn;
                }
              }
              
              if (bookInfo) {
                await getOrCreatePhantomBook(db, isbn, bookInfo);
                inCatalogue = false;
              }
            }
            
            if (bookInfo && !usedIsbns.has(isbn)) {
              pathBooks.push({
                isbn,
                title: bookInfo.title || rec.title,
                author: bookInfo.author || rec.author,
                coverUrl: bookInfo.coverUrl || null,
                position: pathBooks.length + 1,
                status: 'upcoming',
                available: inCatalogue,
                reason: rec.reason || 'Recommended based on your reading preferences',
                seriesInfo: bookInfo.enrichedData?.series || null
              });
              usedIsbns.add(isbn);
            }
          }
        } catch (aiError) {
          logger.error('AI recommendation error:', aiError);
        }
      }
      
      // Build the final learning path
      const learningPath = {
        books: pathBooks,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        startingBookIsbn
      };
      
      // Save to user's Firestore document
      await db.collection('users').doc(userId).collection('learningPath').doc('current').set(learningPath);
      
      // Also save user preferences if provided
      if (preferences) {
        await db.collection('users').doc(userId).collection('preferences').doc('reading').set({
          genres: preferences.genres || [],
          booksPerMonth: preferences.booksPerMonth || 2,
          onboardingComplete: true,
          updatedAt: admin.firestore.FieldValue.serverTimestamp()
        }, { merge: true });
      }
      
      logger.info(`✅ Generated Learning Path with ${pathBooks.length} books for user ${userId}`);
      
      res.json({
        success: true,
        userId,
        learningPath: {
          books: pathBooks,
          startingBookIsbn,
          totalBooks: pathBooks.length,
          availableBooks: pathBooks.filter(b => b.available).length,
          unavailableBooks: pathBooks.filter(b => !b.available).length
        }
      });
      
    } catch (error) {
      logger.error('Error in generateLearningPath:', error);
      res.status(500).json({
        success: false,
        error: error.message
      });
    }
  }
);

/**
 * GET /getLearningPath/{userId}
 * Retrieves the user's current learning path
 */
exports.getLearningPath = onRequest(
  { region: 'australia-southeast1' },
  async (req, res) => {
    // Handle CORS preflight
    if (req.method === 'OPTIONS') {
      return handleOptions(req, res);
    }
    
    setCorsHeaders(res);
    
    try {
      const pathParts = extractPathParams(req, 1);
      const userId = pathParts[0];
      
      if (!userId) {
        return res.status(400).json({
          success: false,
          error: 'Missing userId. URL format: /getLearningPath/{userId}'
        });
      }
      
      const db = admin.firestore();
      const pathDoc = await db.collection('users').doc(userId).collection('learningPath').doc('current').get();
      
      if (!pathDoc.exists) {
        return res.json({
          success: true,
          hasPath: false,
          learningPath: null
        });
      }
      
      const pathData = pathDoc.data();
      
      res.json({
        success: true,
        hasPath: true,
        learningPath: {
          books: pathData.books || [],
          startingBookIsbn: pathData.startingBookIsbn,
          createdAt: pathData.createdAt?.toDate?.()?.toISOString() || null
        }
      });
      
    } catch (error) {
      logger.error('Error in getLearningPath:', error);
      res.status(500).json({
        success: false,
        error: error.message
      });
    }
  }
);

/**
 * POST /updateLearningPathProgress
 * Updates the status of books in a user's learning path
 * 
 * Request body:
 * {
 *   "userId": "firebase-uid",
 *   "isbn": "book-isbn",
 *   "status": "completed" | "reading" | "upcoming"
 * }
 */
exports.updateLearningPathProgress = onRequest(
  { region: 'australia-southeast1' },
  async (req, res) => {
    // Handle CORS preflight
    if (req.method === 'OPTIONS') {
      return handleOptions(req, res);
    }
    
    setCorsHeaders(res);
    
    try {
      const { userId, isbn, status } = req.body;
      
      if (!userId || !isbn || !status) {
        return res.status(400).json({
          success: false,
          error: 'Missing required fields: userId, isbn, status'
        });
      }
      
      const validStatuses = ['reading', 'upcoming', 'completed'];
      if (!validStatuses.includes(status)) {
        return res.status(400).json({
          success: false,
          error: `Invalid status. Must be one of: ${validStatuses.join(', ')}`
        });
      }
      
      const db = admin.firestore();
      const pathRef = db.collection('users').doc(userId).collection('learningPath').doc('current');
      const pathDoc = await pathRef.get();
      
      if (!pathDoc.exists) {
        return res.status(404).json({
          success: false,
          error: 'No learning path found for this user'
        });
      }
      
      const pathData = pathDoc.data();
      const books = pathData.books || [];
      
      // Find and update the book
      const bookIndex = books.findIndex(b => b.isbn === isbn);
      if (bookIndex === -1) {
        return res.status(404).json({
          success: false,
          error: `Book ${isbn} not found in learning path`
        });
      }
      
      // Update status
      books[bookIndex].status = status;
      
      // If marking as completed, promote next upcoming book to reading
      if (status === 'completed') {
        const nextUpcoming = books.find(b => b.status === 'upcoming');
        if (nextUpcoming) {
          nextUpcoming.status = 'reading';
        }
      }
      
      // Save updated path
      await pathRef.update({ books });
      
      logger.info(`Updated Learning Path: ${isbn} -> ${status} for user ${userId}`);
      
      res.json({
        success: true,
        updatedBook: books[bookIndex],
        books
      });
      
    } catch (error) {
      logger.error('Error in updateLearningPathProgress:', error);
      res.status(500).json({
        success: false,
        error: error.message
      });
    }
  }
);
