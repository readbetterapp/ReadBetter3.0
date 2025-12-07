/**
 * Cloud Functions for ReadBetter App
 * Automatically processes books when new folders appear in GCS bucket
 */

const functions = require('firebase-functions');
const admin = require('firebase-admin');
const axios = require('axios');

admin.initializeApp();

const BUCKET_NAME = 'myapp-readeraudio';
const BASE_URL = 'https://storage.googleapis.com';

/**
 * Extract ISBN from GCS file path
 * Example: "0061122416/prologue.json" -> "0061122416"
 */
function extractISBN(path) {
  const parts = path.split('/');
  if (parts.length > 0) {
    const isbn = parts[0];
    // Validate it looks like an ISBN (10 or 13 digits)
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
 * Discover chapters for a book
 */
function discoverChapters(isbn) {
  const chapters = [];
  const chapterNames = [
    'prologue',
    'chapter-1', 'chapter-2', 'chapter-3', 'chapter-4', 'chapter-5',
    'chapter-6', 'chapter-7', 'chapter-8', 'chapter-9', 'chapter-10',
    'epilogue'
  ];
  
  let order = 0;
  for (const name of chapterNames) {
    chapters.push({
      id: `${isbn}-${name}`,
      title: formatChapterTitle(name),
      audioUrl: `${BASE_URL}/${BUCKET_NAME}/${isbn}/${name}.m4a`,
      jsonUrl: `${BASE_URL}/${BUCKET_NAME}/${isbn}/${name}.json`,
      order: order++
    });
  }
  
  return chapters;
}

function formatChapterTitle(name) {
  if (name === 'prologue') return 'Prologue';
  if (name === 'epilogue') return 'Epilogue';
  return name.replace(/-/g, ' ').replace(/\b\w/g, l => l.toUpperCase());
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
    
    // Extract ISBNs
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
    console.error(`Error fetching metadata for ${isbn}:`, error.message);
    throw error;
  }
}

/**
 * Process a book: fetch metadata and save to Firestore
 */
async function processBook(isbn) {
  const db = admin.firestore();
  const bookRef = db.collection('books').doc(isbn);
  
  // Check if book already exists
  const existing = await bookRef.get();
  if (existing.exists) {
    console.log(`Book ${isbn} already exists, skipping...`);
    return;
  }
  
  console.log(`Processing book: ${isbn}`);
  
  // Verify it's a book folder
  const isBook = await isBookFolder(isbn);
  if (!isBook) {
    console.log(`Folder ${isbn} doesn't appear to be a book (no cover.jpg), skipping...`);
    return;
  }
  
  // Fetch metadata
  const metadata = await fetchBookMetadata(isbn);
  
  // Discover chapters
  const chapters = discoverChapters(isbn);
  
  // Get cover URL
  const coverURL = `${BASE_URL}/${BUCKET_NAME}/${isbn}/cover.jpg`;
  
  // Save to Firestore
  const bookData = {
    id: isbn,
    title: metadata.title,
    author: metadata.author,
    isbn10: metadata.isbn10,
    coverUrl: coverURL,
    chapters: chapters,
    createdAt: admin.firestore.FieldValue.serverTimestamp()
  };
  
  if (metadata.description) bookData.description = metadata.description;
  if (metadata.publisher) bookData.publisher = metadata.publisher;
  if (metadata.publishedDate) bookData.publishedDate = metadata.publishedDate;
  if (metadata.isbn13) bookData.isbn13 = metadata.isbn13;
  
  await bookRef.set(bookData);
  console.log(`✅ Successfully processed book: ${isbn} - ${metadata.title}`);
}

/**
 * Cloud Function: Triggered when a new file is uploaded to GCS
 * This runs automatically whenever you upload ANY file to your bucket
 */
exports.processNewBook = functions.storage
  .bucket(BUCKET_NAME)
  .object()
  .onFinalize(async (object) => {
    const filePath = object.name;
    console.log(`New file detected: ${filePath}`);
    
    // Extract ISBN from path
    const isbn = extractISBN(filePath);
    if (!isbn) {
      console.log(`Could not extract ISBN from path: ${filePath}`);
      return null;
    }
    
    // Only process if this is a cover.jpg or chapter file (indicates book setup)
    const fileName = filePath.split('/').pop();
    const isRelevantFile = fileName === 'cover.jpg' || 
                           fileName.endsWith('.m4a') || 
                           fileName.endsWith('.json');
    
    if (!isRelevantFile) {
      return null;
    }
    
    // Process the book (function handles duplicates)
    try {
      await processBook(isbn);
    } catch (error) {
      console.error(`Error processing book ${isbn}:`, error);
      // Don't throw - we don't want to retry on every file upload
    }
    
    return null;
  });

/**
 * Cloud Function: Manually trigger processing of all books in bucket
 * Call this via: https://YOUR-REGION-YOUR-PROJECT.cloudfunctions.net/scanAllBooks
 */
exports.scanAllBooks = functions.https.onRequest(async (req, res) => {
  try {
    const { Storage } = require('@google-cloud/storage');
    const storage = new Storage();
    const bucket = storage.bucket(BUCKET_NAME);
    
    // List all folders (prefixes) in the bucket
    const [files] = await bucket.getFiles({ delimiter: '/' });
    const prefixes = files.prefixes || [];
    
    console.log(`Found ${prefixes.length} potential book folders`);
    
    const processed = [];
    const skipped = [];
    const errors = [];
    
    for (const prefix of prefixes) {
      const isbn = prefix.replace('/', '');
      
      if (!/^\d{10,13}$/.test(isbn)) {
        skipped.push(isbn);
        continue;
      }
      
      try {
        await processBook(isbn);
        processed.push(isbn);
      } catch (error) {
        console.error(`Error processing ${isbn}:`, error);
        errors.push(isbn);
      }
      
      // Small delay to avoid rate limiting
      await new Promise(resolve => setTimeout(resolve, 500));
    }
    
    res.json({
      success: true,
      processed: processed.length,
      skipped: skipped.length,
      errors: errors.length,
      details: {
        processed,
        skipped,
        errors
      }
    });
  } catch (error) {
    console.error('Error scanning books:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

