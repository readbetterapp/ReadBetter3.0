# Chapter Durations Setup

## Overview

The book scanner now automatically extracts audio duration for each chapter when processing books. This duration is displayed in the Featured Books section of the app.

## How It Works

When you run the book scanner (`scanAllBooks` Cloud Function), it will:

1. Discover all chapters for each book
2. For each chapter, fetch the audio file metadata
3. Extract the duration (in seconds) using the `music-metadata` library
4. Store the duration in Firestore alongside other chapter data

## Setup Steps

### 1. Install Dependencies

Navigate to the functions directory and install the new dependency:

```bash
cd functions
npm install
```

This will install `music-metadata@^8.1.4` which is used to extract audio metadata.

### 2. Deploy the Updated Cloud Function

Deploy the updated function to Firebase:

```bash
firebase deploy --only functions
```

Or deploy just the scanAllBooks function:

```bash
firebase deploy --only functions:scanAllBooks
```

### 3. Re-process Existing Books (Optional)

If you have existing books in Firestore without duration data, you can re-process them by calling the scanner with `forceUpdate=true`:

**Option A: Via HTTP Request**
```bash
curl "https://YOUR-FUNCTION-URL/scanAllBooks?forceUpdate=true"
```

**Option B: Via Firebase Console**
- Go to Firebase Console → Functions
- Find the `scanAllBooks` function
- Click "View logs" to get the URL
- Open the URL in your browser with `?forceUpdate=true` parameter

### 4. Process New Books

For new books, simply trigger the scanner as usual. The duration will be automatically extracted and stored.

## Data Structure

The chapter data in Firestore will now include a `duration` field:

```json
{
  "chapters": [
    {
      "id": "0061122416-prologue",
      "title": "Prologue",
      "audioUrl": "https://storage.googleapis.com/...",
      "jsonUrl": "https://storage.googleapis.com/...",
      "order": 0,
      "duration": 1234.5
    }
  ]
}
```

**Duration Format:**
- Stored in **seconds** as a number (e.g., 1234.5 = 20 minutes 34.5 seconds)
- The app automatically converts this to human-readable format (e.g., "6h 40m")

## Display in App

The Featured Books cards now display:
- **Year** - Extracted from `publishedDate` (e.g., "2020")
- **Total Duration** - Sum of all chapter durations (e.g., "6h 40m")
- Format: "2020 • 6h 40m"

## Troubleshooting

### Duration Not Showing
- Check Firestore to verify the `duration` field exists for chapters
- Re-run the scanner with `forceUpdate=true` to re-process books
- Check Cloud Function logs for any errors during duration extraction

### Duration Extraction Fails
- Verify the audio URL is accessible
- Check that the audio file format is supported (.m4a)
- Look for timeout errors in Cloud Function logs (default timeout is 30 seconds per chapter)

### Performance Considerations
- Duration extraction adds ~1-2 seconds per chapter
- For books with many chapters (e.g., 20+ chapters), processing may take longer
- The function processes chapters sequentially to avoid rate limiting

## Development Notes

### Key Files Modified
1. `functions/package.json` - Added `music-metadata` dependency
2. `functions/index.js` - Added `getAudioDuration()` function and updated `discoverChapters()`
3. `ReadBetterApp3.0/Models/Book.swift` - Added optional `duration` field to `Chapter` struct
4. `ReadBetterApp3.0/Services/BookService.swift` - Updated to parse `duration` from Firestore
5. `ReadBetterApp3.0/Views/SearchView.swift` - Added duration display in `FeaturedBookCard2`

### Audio Format Support
The `music-metadata` library supports various audio formats including:
- M4A (AAC)
- MP3
- WAV
- OGG
- FLAC

Your app currently uses `.m4a` format, which is fully supported.

## Future Enhancements

Potential improvements:
- Cache duration extraction results to speed up re-processing
- Add duration to description audio files as well
- Display chapter durations in the reader view
- Add total book duration to book details page
