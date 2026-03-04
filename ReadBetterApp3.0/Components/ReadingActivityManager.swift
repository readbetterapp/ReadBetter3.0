import ActivityKit
import UIKit
import Foundation

// MARK: - Reading Activity Manager
// Singleton. Add to your main app target only.
//
// Usage in OptimizedReaderView:
//   .onAppear  → ReadingActivityManager.shared.startOrUpdate(...)
//   .onChange(of: audioPlayer.isPlaying) → ReadingActivityManager.shared.update(...)
//   .onChange(of: audioPlayer.currentTime) → throttled update
//   presentBookmarkToast → ReadingActivityManager.shared.bookmark(timeText:)
//   .onDisappear → ReadingActivityManager.shared.end()

@MainActor
final class ReadingActivityManager {

    static let shared = ReadingActivityManager()
    private init() {}

    private var activity: Activity<ReadingActivityAttributes>?

    // Throttle currentTime updates — we don't need 60fps in the island
    private var lastTimeUpdate: Date = .distantPast
    private let timeUpdateInterval: TimeInterval = 2.0

    // Track current state so we can build deltas
    private var currentState: ReadingActivityAttributes.ContentState?
    private var bookmarkClearTask: Task<Void, Never>?

    // MARK: - Start or resume

    func startOrUpdate(
        bookTitle: String,
        bookId: String,
        coverImage: UIImage?,
        chapterTitle: String,
        chapterNumber: Int,
        isPlaying: Bool,
        currentTime: Double,
        duration: Double
    ) {
        // If we already have a running activity for this book, just update it
        if let existing = activity, existing.activityState == .active {
            Task {
                await updateState(
                    chapterTitle: chapterTitle,
                    chapterNumber: chapterNumber,
                    isPlaying: isPlaying,
                    currentTime: currentTime,
                    duration: duration
                )
            }
            return
        }

        // Check if Live Activities are supported and enabled
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            print("📍 LiveActivity: Activities not enabled on this device")
            return
        }

        // Compress cover to small PNG for embedding in attributes
        // Keep it small — ActivityKit has a ~4KB limit on attribute data
        let coverData: Data? = {
            guard let img = coverImage else { return nil }
            let size = CGSize(width: 60, height: 72)
            let renderer = UIGraphicsImageRenderer(size: size)
            let resized = renderer.image { _ in
                img.draw(in: CGRect(origin: .zero, size: size))
            }
            return resized.pngData()
        }()

        let attributes = ReadingActivityAttributes(
            bookTitle: bookTitle,
            bookId: bookId,
            coverImageData: coverData
        )

        let initialState = ReadingActivityAttributes.ContentState(
            isPlaying: isPlaying,
            currentTime: currentTime,
            duration: duration,
            chapterTitle: chapterTitle,
            chapterNumber: chapterNumber
        )

        currentState = initialState

        do {
            let activity = try Activity<ReadingActivityAttributes>.request(
                attributes: attributes,
                content: .init(state: initialState, staleDate: nil),
                pushType: nil
            )
            self.activity = activity
            print("📍 LiveActivity started: \(activity.id)")
        } catch {
            print("📍 LiveActivity start failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Update playback state

    func update(
        isPlaying: Bool,
        currentTime: Double,
        duration: Double,
        chapterTitle: String? = nil,
        chapterNumber: Int? = nil
    ) {
        guard activity?.activityState == .active else { return }

        // Throttle time-only updates
        let now = Date()
        let isTimeOnlyUpdate = (chapterTitle == nil)
        if isTimeOnlyUpdate && now.timeIntervalSince(lastTimeUpdate) < timeUpdateInterval { return }
        lastTimeUpdate = now

        Task {
            await updateState(
                chapterTitle: chapterTitle ?? currentState?.chapterTitle ?? "",
                chapterNumber: chapterNumber ?? currentState?.chapterNumber ?? 1,
                isPlaying: isPlaying,
                currentTime: currentTime,
                duration: duration
            )
        }
    }

    // MARK: - Bookmark event

    func bookmark(timeText: String, currentTime: Double, duration: Double) {
        guard activity?.activityState == .active else { return }

        bookmarkClearTask?.cancel()

        Task {
            guard let state = currentState else { return }
            let bookmarkedState = ReadingActivityAttributes.ContentState(
                isPlaying: state.isPlaying,
                currentTime: currentTime,
                duration: duration,
                chapterTitle: state.chapterTitle,
                chapterNumber: state.chapterNumber,
                lastBookmarkedAt: Date(),
                lastBookmarkedTimeText: timeText
            )
            await pushState(bookmarkedState)
        }

        // Clear bookmark highlight after 4 seconds
        bookmarkClearTask = Task {
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard !Task.isCancelled else { return }
            await clearBookmarkState()
        }
    }

    // MARK: - End session

    func end() {
        bookmarkClearTask?.cancel()
        guard let activity else { return }

        Task {
            await activity.end(nil, dismissalPolicy: .immediate)
            print("📍 LiveActivity ended")
        }
        self.activity = nil
        self.currentState = nil
    }

    // MARK: - Private helpers

    private func updateState(
        chapterTitle: String,
        chapterNumber: Int,
        isPlaying: Bool,
        currentTime: Double,
        duration: Double
    ) async {
        // Preserve any active bookmark state while updating playback
        let newState = ReadingActivityAttributes.ContentState(
            isPlaying: isPlaying,
            currentTime: currentTime,
            duration: duration,
            chapterTitle: chapterTitle,
            chapterNumber: chapterNumber,
            lastBookmarkedAt: currentState?.lastBookmarkedAt,
            lastBookmarkedTimeText: currentState?.lastBookmarkedTimeText
        )
        await pushState(newState)
    }

    private func clearBookmarkState() async {
        guard let state = currentState else { return }
        let cleared = ReadingActivityAttributes.ContentState(
            isPlaying: state.isPlaying,
            currentTime: state.currentTime,
            duration: state.duration,
            chapterTitle: state.chapterTitle,
            chapterNumber: state.chapterNumber,
            lastBookmarkedAt: nil,
            lastBookmarkedTimeText: nil
        )
        await pushState(cleared)
    }

    private func pushState(_ state: ReadingActivityAttributes.ContentState) async {
        currentState = state
        await activity?.update(.init(state: state, staleDate: nil))
    }
}
