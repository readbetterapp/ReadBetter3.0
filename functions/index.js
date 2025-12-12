/**
 * Cloud Functions for ReadBetter App
 * Automatically processes books from GCS bucket
 */

const {onRequest} = require("firebase-functions/v2/https");
const {onSchedule} = require("firebase-functions/v2/scheduler");
const {setGlobalOptions} = require("firebase-functions/v2");
const admin = require("firebase-admin");
const axios = require("axios");
const logger = require("firebase-functions/logger");
const { libraryCache, chapterIndexCache } = require('./utils/cache');
const { parseTranscript } = require('./utils/transcriptParser');

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
  
  // Build chapter objects
  const chapters = sortedChapters.map((name, index) => ({
    id: `${isbn}-${name}`,
    title: formatChapterTitle(name),
    audioUrl: `${BASE_URL}/${BUCKET_NAME}/${isbn}/${name}.m4a`,
    jsonUrl: `${BASE_URL}/${BUCKET_NAME}/${isbn}/${name}.json`,
    order: index
  }));
  
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
