import ActivityKit
import Foundation

// MARK: - Reading Session Live Activity
//
// SETUP REQUIRED:
// 1. Add a Widget Extension target to your Xcode project (File > New > Target > Widget Extension)
//    - Name it e.g. "ReadBetterWidgets"
//    - Uncheck "Include Configuration App Intent"
// 2. Add "NSSupportsLiveActivities" = YES to your main app's Info.plist
// 3. Add this file AND ReadingActivityWidget.swift to BOTH the main app target
//    and the widget extension target
// 4. Add ReadingActivityManager.swift to the main app target only
// 5. In the widget extension's ReadBetterWidgetsBundle.swift, add ReadingLiveActivity
//    to the @main WidgetBundle

public struct ReadingActivityAttributes: ActivityAttributes {

    // MARK: - Static data (set at activity start, never changes)
    public struct ContentState: Codable, Hashable {
        // Playback state
        public var isPlaying: Bool
        public var currentTime: Double        // seconds
        public var duration: Double           // seconds

        // Chapter info (updates on chapter change)
        public var chapterTitle: String
        public var chapterNumber: Int

        // Bookmark event — set briefly when user bookmarks, cleared after a few seconds
        public var lastBookmarkedAt: Date?
        public var lastBookmarkedTimeText: String?  // e.g. "1:42"

        public init(
            isPlaying: Bool,
            currentTime: Double,
            duration: Double,
            chapterTitle: String,
            chapterNumber: Int,
            lastBookmarkedAt: Date? = nil,
            lastBookmarkedTimeText: String? = nil
        ) {
            self.isPlaying = isPlaying
            self.currentTime = currentTime
            self.duration = duration
            self.chapterTitle = chapterTitle
            self.chapterNumber = chapterNumber
            self.lastBookmarkedAt = lastBookmarkedAt
            self.lastBookmarkedTimeText = lastBookmarkedTimeText
        }
    }

    // Static — passed once at start, never updated
    public var bookTitle: String
    public var bookId: String
    // Cover image passed as raw PNG data so widget can render it without networking
    public var coverImageData: Data?

    public init(bookTitle: String, bookId: String, coverImageData: Data?) {
        self.bookTitle = bookTitle
        self.bookId = bookId
        self.coverImageData = coverImageData
    }
}
