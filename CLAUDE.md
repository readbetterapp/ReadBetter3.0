# ReadBetter (ReadBetterApp 3.0)

iOS audiobook reader with synchronized TTS playback and karaoke-style word highlighting. Words light up in real time as they are spoken. Users can tap any word for a contextual definition. Solo-founder project targeting iOS 26.

## Tech Stack

- **Language**: Swift 6 / SwiftUI
- **IDE**: Xcode
- **Backend**: Firebase (Auth, Firestore, Cloud Storage, Cloud Functions)
- **Cloud Functions**: Node.js 20, deployed to `australia-southeast1`
- **Image Caching**: Kingfisher (150MB memory / 500MB disk)
- **Audio**: AVFoundation (AVPlayer, AVAudioSession)
- **APIs**: OpenAI (daily quotes, explainable terms, learning path generation)
- **Alignment Tool**: Gentle (Docker) for word-level audio alignment

## Project Structure

```
ReadBetterApp3.0/
├── ReadBetterApp3_0App.swift        # App entry point, AppDelegate (Firebase, audio session, Kingfisher init)
├── Config/
│   └── Config.swift                 # API key management (OpenAI via xcconfig/Info.plist)
├── Navigation/
│   ├── AppRouter.swift              # NavigationPath routing, AppRoute enum, tab navigation
│   └── ThemeColors.swift            # Brand colors (red accent #FF383C, yellow/cream)
├── Engine/
│   └── KaraokeEngine.swift          # Word-level sync engine (binary search + O(1) caching)
├── Models/
│   ├── Book.swift                   # Book + Chapter (identified by ISBN)
│   ├── Bookmark.swift               # Sentence-level bookmarks with timestamps
│   ├── BookmarkFolder.swift         # Bookmark folder organization
│   ├── EnrichedBookData.swift       # AI-generated metadata (series, genres, themes)
│   ├── ExplainableTerm.swift        # Context-specific word definitions
│   ├── LearningPath.swift           # 5-book personalized reading path
│   ├── PhantomBook.swift            # Books not yet in catalog (coming soon)
│   ├── PreloadedReaderData.swift    # Pre-computed reader data container
│   ├── ReadingProgress.swift        # Per-book/chapter progress tracking
│   ├── ReadingSession.swift         # Daily reading stats
│   ├── TranscriptData.swift         # Full text + sentences + word timings
│   ├── UserPreferences.swift        # Onboarding choices (genres, reading goals)
│   ├── UserProfile.swift            # User account data
│   └── WordTiming.swift             # Individual word start/end times
├── Services/
│   ├── AudioPlayerService.swift     # AVPlayer wrapper (play/pause/seek/time observer)
│   ├── AudioSessionController.swift # AVAudioSession background playback setup
│   ├── AuthManager.swift            # Firebase Auth (anonymous, email, Google, Apple, account linking)
│   ├── BackgroundChapterLoader.swift# Preload chapters in background
│   ├── BookService.swift            # Fetch books from Firestore with local cache
│   ├── BookmarkService.swift        # Firestore-backed bookmarks + folders
│   ├── BookOwnershipService.swift   # Track owned/unlocked books
│   ├── CacheService.swift           # Local user data caching
│   ├── ExplainableTermsService.swift# Context-specific word definitions (OpenAI)
│   ├── LearningPathService.swift    # Personalized 5-book path generation
│   ├── NowPlayingController.swift   # Lock screen / Control Center now playing info
│   ├── QuoteService.swift           # Daily inspiration quotes (OpenAI)
│   ├── ReadingProgressService.swift # Hybrid local+cloud progress (debounced 30s sync)
│   ├── ReadingStatsService.swift    # Daily reading sessions & stats
│   ├── StorageService.swift         # Local file storage wrapper
│   └── TranscriptService.swift      # Load & parse transcript JSON from GCS
├── Views/
│   ├── RootView.swift               # Root navigation, splash screen, service init
│   ├── HomeView.swift               # Dashboard (continue reading, quotes, stats)
│   ├── LibraryView.swift            # Browse books, search, filter by genre
│   ├── BookDetailsView.swift        # Book metadata, chapters, description
│   ├── OptimizedReaderView.swift    # PRIMARY VIEW - karaoke reader with word sync
│   ├── ReaderLoadingView.swift      # Loading state for reader data prep
│   ├── BookmarksView.swift          # Saved bookmarks by folder
│   ├── SearchView.swift             # Global search
│   ├── LoginView.swift              # Auth (email, Google, Apple Sign-In)
│   ├── WelcomeView.swift            # Guest onboarding entry
│   ├── ProfileView.swift            # User account & settings
│   ├── TappableTextView.swift       # Interactive text for word definitions
│   ├── CachedBookImage.swift        # Kingfisher image with fallback
│   ├── UnlockBookModal.swift        # Book unlock/purchase UI
│   ├── UnlockSuccessOverlay.swift   # Success animation after unlock
│   ├── LoginPromptOverlay.swift     # Prompt guests to sign in
│   ├── BookmarkEditSheet.swift      # Edit bookmark metadata
│   └── Onboarding/                  # Multi-step onboarding flow
│       ├── OnboardingContainerView.swift
│       ├── OnboardingWelcomeView.swift
│       ├── OnboardingGenresView.swift
│       ├── OnboardingGoalView.swift
│       ├── OnboardingBookPickerView.swift
│       ├── OnboardingPathRevealView.swift
│       └── OnboardingViewModel.swift
├── Components/
│   ├── MiniPlayerView.swift         # Spotify-style compact audio player
│   ├── CustomTabBar.swift           # Custom tab bar (legacy iOS)
│   ├── ReadingStatsCard.swift       # Stats display card
│   ├── StoryProgressBar.swift       # Chapter/book progress bar
│   ├── GenreCard.swift              # Genre selection card (onboarding)
│   ├── GoalOptionCard.swift         # Reading goal selector (onboarding)
│   ├── ReadingActivityAttributes.swift  # Live Activity attributes
│   ├── ReadingActivityManager.swift     # Live Activity manager
│   └── ReadingActivityWidget.swift      # Dynamic Island / Live Activity widget
├── Utils/
│   ├── ImagePreloader.swift         # Async book cover preloading
│   ├── PlaybackTimeFormatter.swift  # Time display formatting (1:23:45)
│   ├── SentenceTextLayout.swift     # Sentence layout measurement for scrolling
│   ├── ThemeManager.swift           # Dark/light mode, color scheme
│   ├── ScrollOffsetPreferenceKey.swift  # Track scroll position
│   └── ScrollDebugOverlay.swift     # Debug scroll behavior
├── Assets.xcassets/                 # Images, app icons, colors
└── GoogleService-Info.plist         # Firebase config (production)

ReadBetterWidgets/                   # iOS Widget extension
├── ReadBetterWidgets.swift
├── ReadBetterWidgetsBundle.swift
├── ReadBetterWidgetsControl.swift
└── ReadBetterWidgetsLiveActivity.swift

functions/                           # Firebase Cloud Functions (Node.js)
├── index.js                         # All cloud function definitions
└── package.json                     # Dependencies (firebase-admin, openai, axios, music-metadata)

firestore.rules                      # Firestore security rules
```

## Core Architecture

### Content Pipeline (manual, not automated)

1. Source book text (PDF/text from online sources, public domain from Gutenberg for now)
2. Generate TTS audio per chapter using external TTS LLMs
3. Run audio + text through **Gentle** (Docker) to produce word-level alignment JSON (~90-95% accuracy)
4. Upload `.wav`/`.m4a` audio and `.json` timing files to **Google Cloud Storage** bucket, organized by ISBN folder
5. Connect to **Firebase** which processes book metadata (uses ISBN for book info lookup)
6. App fetches book catalog from Firestore, downloads audio/timing data from GCS per chapter

### KaraokeEngine (Engine/KaraokeEngine.swift)

The core sync engine. Performance-critical — do not add unnecessary overhead.

- **Binary search O(log n)** for initial/seek word lookup
- **Sequential fast-forward O(1)** during normal playback (tracks `currentWordArrayIndex`)
- **O(1) lookup dictionary** (`wordIdToArrayIndex`) maps word ID to array index
- **Caching**: stores `lastLookupTime`/`lastLookupResult` to avoid repeated lookups
- **Buffer zones**: 100ms before/after each word for smooth transitions
- **Large jump detection**: >5s time difference triggers binary search instead of sequential scan
- Word updates are real-time (no throttling); progress bar throttled to 10fps
- AVPlayer's time observer drives updates at ~30fps

### Reader View (Views/OptimizedReaderView.swift)

The largest and most complex file. Contains the main reading UI with:
- Real-time word highlighting synced to audio via KaraokeEngine
- Tappable sentences for contextual word definitions
- Playback controls (play/pause/seek, adjustable speed, sleep timer)
- Reader customization (text size S/M/L at 18/22/26pt, fonts: System/New York/Georgia, background colors, highlight colors)
- Bookmark creation and management
- Reading stats tracking during session
- Description reader mode (book summary with narration)
- Overlay/expand mode (Spotify-style from mini player)

### Reading Progress (Services/ReadingProgressService.swift)

Hybrid local + cloud sync pattern:
- **Instant**: saves to UserDefaults immediately
- **Debounced**: syncs to Firestore every 30 seconds
- **Merge on launch**: combines local + cloud data
- **Force sync**: on app background/close

### Navigation (Navigation/AppRouter.swift)

Stack-based navigation using `NavigationPath`. Key routes:
- `.tabs` — Main tab interface (Home, Library, Bookmarks, Search)
- `.bookDetails(bookId)` — Book detail page
- `.reader(bookId, chapterNumber?)` — Reader view
- `.readerAt(bookId, chapterNumber?, startTime?)` — Resume reading at position

Mini player uses Spotify-style expand/collapse with spring animations. iOS 26 uses native `tabViewBottomAccessory`; older iOS uses floating ZStack.

## Firebase / Firestore Structure

```
/books/{isbn}                        # Public book catalog (read-only from app)
/books/{isbn}/chapterIndexes/{id}    # Precomputed word timing data
/phantomBooks/{isbn}                 # Coming-soon books (for learning path)
/explainableTerms/{bookId}/chapters/{chapterId}  # AI word definitions
/users/{uid}                         # User profile
/users/{uid}/bookmarks/{id}          # Bookmarks (sentence-level with timestamps)
/users/{uid}/folders/{id}            # Bookmark folders
/users/{uid}/readingProgress/{bookId}# Reading positions
/users/{uid}/ownedBooks/{bookId}     # Owned/unlocked books
/users/{uid}/preferences/{doc}       # Onboarding choices
/users/{uid}/learningPath/{doc}      # Personalized 5-book path
/users/{uid}/readingSessions/{id}    # Daily stats
```

Security: Books are public read. All user data is owner-only (`request.auth.uid == userId`). No direct writes to books from client.

## Cloud Functions (functions/index.js)

Deployed to `australia-southeast1`, Node.js 20. Key functions:
- `discoverChapters(isbn)` — Lists .m4a + .json pairs from GCS, extracts audio duration
- `getChapterIndex(bookId, chapterId)` — Returns precomputed word timing data
- `generateLearningPath(userId, startingBookIsbn, genres, booksPerMonth)` — OpenAI-powered 5-book path
- `parseTranscript()` — Parses word timing JSON, builds sentence index
- `processChapterExplainableTerms()` — Extracts vocabulary, generates AI definitions

## Authentication

Firebase Auth with four providers:
- Anonymous (guest browsing)
- Email/password
- Google Sign-In
- Apple Sign-In

Supports account linking (anonymous → real provider, preserving bookmarks/progress). Session validation on launch detects deleted users.

## Key Patterns & Conventions

- **Environment objects**: Services are injected via `.environmentObject()` from RootView
- **@Published properties**: Services use `@Published` for reactive UI updates
- **Firestore snapshot listeners**: Real-time sync for bookmarks, learning paths
- **Singleton audio**: `AudioPlayerService` manages a single AVPlayer instance
- **ISBN as book ID**: Books are identified by ISBN-10 throughout the system
- **Preloaded data**: Reader view receives `PreloadedReaderData` — all computation happens during loading, not during playback
- **Background audio**: Configured in AppDelegate BEFORE any AVPlayer creation (critical ordering)
- **Bundle ID variants**: `-dev`, `-beta`, production — each with its own Firebase plist

## Build & Configuration

- **Xcode project**: `ReadBetterApp3.0.xcodeproj`
- **Bundle IDs**: `com.ermintupkovic.readbetter` (prod), `-beta`, `-dev`
- **OpenAI key**: via `Secrets.xcconfig` → Info.plist (release) or env var (debug)
- **Firebase plists**: `GoogleService-Info.plist`, `GoogleService-Info-Beta.plist`, `GoogleService-Info-Dev.plist`
- **Background modes**: Audio playback enabled in Info.plist
- **Cloud Functions deploy**: `firebase deploy --only functions`

## Development Status

~90% complete. Core reading experience is functional. Remaining work is UX/UI refinements. Content pipeline (TTS generation → Gentle alignment → GCS upload) is manual and not yet automated. Publishing/licensing for book catalog is a future milestone — currently using public domain books for user testing.

## Important Warnings

- **OptimizedReaderView.swift is large and complex** — it contains the majority of the reader UI logic. Changes here need careful testing.
- **KaraokeEngine is performance-critical** — avoid adding allocations or unnecessary work in the hot path (`getWordAtTime`, `updateTime`).
- **Audio session ordering matters** — `configureAudioSessionForBackgroundPlayback()` must run before any AVPlayer is created. This is enforced in AppDelegate.
- **Do not commit secrets** — `Secrets.xcconfig` and `GoogleService-Info*.plist` files contain API keys and Firebase credentials.
- **iOS 26 APIs** — Several views use `#available(iOS 26, *)` guards with fallbacks. Keep backward compatibility in mind when using new APIs.
