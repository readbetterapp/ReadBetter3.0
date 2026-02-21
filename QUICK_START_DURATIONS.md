# Quick Start: Enable Chapter Durations

## TL;DR - 3 Steps to Enable

### Step 1: Install Dependencies
```bash
cd functions
npm install
```

### Step 2: Deploy Cloud Function
```bash
firebase deploy --only functions:scanAllBooks
```

### Step 3: Re-process Books (if you have existing books)
Visit your Cloud Function URL with `?forceUpdate=true`:
```
https://YOUR-FUNCTION-URL/scanAllBooks?forceUpdate=true
```

That's it! New books will automatically get duration data, and the Featured Books section will display:
- **Year**: e.g., "2020"
- **Duration**: e.g., "6h 40m"
- **Format**: "2020 • 6h 40m"

---

## What Changed?

### Backend (Cloud Functions)
- ✅ Added `music-metadata` package to extract audio duration
- ✅ Updated `discoverChapters()` to fetch duration for each chapter
- ✅ Duration stored in seconds in Firestore

### iOS App
- ✅ Added optional `duration` field to `Chapter` model
- ✅ Updated `BookService` to read duration from Firestore
- ✅ Updated `FeaturedBookCard2` to display year and total duration

### No Breaking Changes
- Existing books without duration data will still work
- Duration field is optional
- App gracefully handles missing duration data

---

For detailed documentation, see `CHAPTER_DURATIONS_SETUP.md`
