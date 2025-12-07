# ReadBetter Cloud Functions

Automatically processes books from GCS bucket when new folders are uploaded.

## Setup Instructions

### 1. Install Firebase CLI
```bash
npm install -g firebase-tools
```

### 2. Login to Firebase
```bash
firebase login
```

### 3. Initialize Firebase Functions (if not already done)
```bash
cd cloud-functions
firebase init functions
```
- Select your Firebase project
- Choose JavaScript
- Install dependencies? Yes

### 4. Install Dependencies
```bash
cd functions  # or cloud-functions if that's your folder name
npm install
```

### 5. Deploy Functions
```bash
firebase deploy --only functions
```

## What It Does

### Auto-Process Function (`processNewBook`)
- **Trigger**: Automatically runs when ANY file is uploaded to your GCS bucket
- **Action**: 
  - Detects new ISBN folders
  - Fetches book metadata from Google Books API
  - Saves to Firestore automatically
  - Skips duplicates

### Manual Scan Function (`scanAllBooks`)
- **Trigger**: HTTP request (for one-time setup)
- **Action**: Scans entire bucket and processes all books
- **URL**: `https://YOUR-REGION-YOUR-PROJECT.cloudfunctions.net/scanAllBooks`

## How to Use

### Automatic (Recommended)
1. Deploy the functions
2. Upload a new book folder to GCS
3. Function automatically processes it - **no manual steps!**

### One-Time Setup (Process Existing Books)
1. Visit: `https://YOUR-REGION-YOUR-PROJECT.cloudfunctions.net/scanAllBooks`
2. Or call via curl:
```bash
curl https://YOUR-REGION-YOUR-PROJECT.cloudfunctions.net/scanAllBooks
```

## Configuration

Edit `index.js` and change:
- `BUCKET_NAME`: Your GCS bucket name (currently: `myapp-readeraudio`)

## Permissions

Make sure your Firebase project has:
- Storage Admin role (to read GCS bucket)
- Firestore write permissions (already set)

## Monitoring

Check function logs in Firebase Console:
- Functions → Logs
- See real-time processing of books








