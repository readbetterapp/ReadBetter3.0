import ActivityKit
import SwiftUI
import WidgetKit

// MARK: - Live Activity Widget
// Add this file to your Widget Extension target.
// In your WidgetBundle, add: ReadingLiveActivity()

struct ReadingLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ReadingActivityAttributes.self) { context in
            // ── Lock Screen / StandBy view ──────────────────────────────
            LockScreenView(context: context)
                .activityBackgroundTint(Color.black.opacity(0.85))
                .activitySystemActionForegroundColor(.white)

        } dynamicIsland: { context in
            DynamicIsland {
                // ── Expanded (long-press) ───────────────────────────────
                DynamicIslandExpandedRegion(.leading) {
                    ExpandedLeadingView(context: context)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    ExpandedTrailingView(context: context)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    ExpandedBottomView(context: context)
                }
            } compactLeading: {
                // ── Compact left: cover thumbnail ───────────────────────
                CompactCoverView(context: context)
            } compactTrailing: {
                // ── Compact right: play icon or checkmark ───────────────
                CompactTrailingView(context: context)
            } minimal: {
                // ── Minimal (when two activities compete) ───────────────
                MinimalView(context: context)
            }
            .keylineTint(Color.white.opacity(0.6))
        }
    }
}

// MARK: - Helpers

private func coverImage(from data: Data?) -> Image? {
    guard let data, let uiImage = UIImage(data: data) else { return nil }
    return Image(uiImage: uiImage)
}

private func progressFraction(_ context: ActivityViewContext<ReadingActivityAttributes>) -> Double {
    let d = context.state.duration
    guard d > 0 else { return 0 }
    return min(context.state.currentTime / d, 1.0)
}

private func isBookmarkFresh(_ context: ActivityViewContext<ReadingActivityAttributes>) -> Bool {
    guard let at = context.state.lastBookmarkedAt else { return false }
    return Date().timeIntervalSince(at) < 4
}

// MARK: - Compact Views

private struct CompactCoverView: View {
    let context: ActivityViewContext<ReadingActivityAttributes>

    var body: some View {
        Group {
            if let img = coverImage(from: context.attributes.coverImageData) {
                img
                    .resizable()
                    .scaledToFill()
                    .frame(width: 22, height: 22)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.white.opacity(0.2))
                    .frame(width: 22, height: 22)
                    .overlay(
                        Image(systemName: "book.fill")
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.7))
                    )
            }
        }
        .padding(.leading, 4)
    }
}

private struct CompactTrailingView: View {
    let context: ActivityViewContext<ReadingActivityAttributes>

    var body: some View {
        Group {
            if isBookmarkFresh(context) {
                Image(systemName: "bookmark.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.yellow)
                    .transition(.scale.combined(with: .opacity))
            } else {
                Image(systemName: context.state.isPlaying ? "waveform" : "pause.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white.opacity(0.85))
                    .symbolEffect(.variableColor.iterative, isActive: context.state.isPlaying)
            }
        }
        .padding(.trailing, 4)
        .animation(.spring(response: 0.3), value: isBookmarkFresh(context))
    }
}

private struct MinimalView: View {
    let context: ActivityViewContext<ReadingActivityAttributes>

    var body: some View {
        if isBookmarkFresh(context) {
            Image(systemName: "bookmark.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.yellow)
        } else {
            Image(systemName: context.state.isPlaying ? "waveform" : "headphones")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.white.opacity(0.8))
                .symbolEffect(.variableColor.iterative, isActive: context.state.isPlaying)
        }
    }
}

// MARK: - Expanded Views

private struct ExpandedLeadingView: View {
    let context: ActivityViewContext<ReadingActivityAttributes>

    var body: some View {
        HStack(spacing: 10) {
            // Cover art
            Group {
                if let img = coverImage(from: context.attributes.coverImageData) {
                    img
                        .resizable()
                        .scaledToFill()
                        .frame(width: 46, height: 56)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                } else {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.white.opacity(0.15))
                        .frame(width: 46, height: 56)
                        .overlay(
                            Image(systemName: "book.fill")
                                .font(.system(size: 18))
                                .foregroundColor(.white.opacity(0.5))
                        )
                }
            }
            .shadow(color: .black.opacity(0.4), radius: 4, x: 0, y: 2)

            // Titles
            VStack(alignment: .leading, spacing: 3) {
                Text(context.attributes.bookTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                Text(context.state.chapterTitle)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundColor(.white.opacity(0.6))
                    .lineLimit(1)
            }
        }
        .padding(.leading, 4)
    }
}

private struct ExpandedTrailingView: View {
    let context: ActivityViewContext<ReadingActivityAttributes>

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            if isBookmarkFresh(context), let timeText = context.state.lastBookmarkedTimeText {
                // Bookmark confirmation state
                HStack(spacing: 5) {
                    Image(systemName: "bookmark.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.yellow)
                    Text(timeText)
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundColor(.yellow)
                }
                .transition(.scale.combined(with: .opacity))

                Text("Bookmarked")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.yellow.opacity(0.8))
                    .transition(.opacity)
            } else {
                // Normal playback state
                Image(systemName: context.state.isPlaying ? "waveform" : "pause.fill")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(.white.opacity(0.85))
                    .symbolEffect(.variableColor.iterative, isActive: context.state.isPlaying)
                    .frame(width: 28)

                Text(formatTime(context.state.currentTime))
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.5))
            }
        }
        .padding(.trailing, 8)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: isBookmarkFresh(context))
    }
}

private struct ExpandedBottomView: View {
    let context: ActivityViewContext<ReadingActivityAttributes>

    var body: some View {
        VStack(spacing: 5) {
            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.18))
                        .frame(height: 3)
                    Capsule()
                        .fill(Color.white.opacity(0.75))
                        .frame(width: geo.size.width * progressFraction(context), height: 3)
                }
            }
            .frame(height: 3)

            // Time labels
            HStack {
                Text(formatTime(context.state.currentTime))
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.45))
                Spacer()
                Text("-\(formatTime(max(context.state.duration - context.state.currentTime, 0)))")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.45))
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
    }
}

// MARK: - Lock Screen View

private struct LockScreenView: View {
    let context: ActivityViewContext<ReadingActivityAttributes>

    var body: some View {
        HStack(spacing: 14) {
            // Cover
            Group {
                if let img = coverImage(from: context.attributes.coverImageData) {
                    img
                        .resizable()
                        .scaledToFill()
                        .frame(width: 52, height: 62)
                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                } else {
                    RoundedRectangle(cornerRadius: 7)
                        .fill(Color.white.opacity(0.12))
                        .frame(width: 52, height: 62)
                        .overlay(
                            Image(systemName: "book.fill")
                                .font(.system(size: 20))
                                .foregroundColor(.white.opacity(0.4))
                        )
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(context.attributes.bookTitle)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                Text(context.state.chapterTitle)
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.6))
                    .lineLimit(1)

                Spacer(minLength: 4)

                if isBookmarkFresh(context), let timeText = context.state.lastBookmarkedTimeText {
                    HStack(spacing: 5) {
                        Image(systemName: "bookmark.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.yellow)
                        Text("Bookmarked at \(timeText)")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.yellow)
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                } else {
                    // Progress bar
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.white.opacity(0.2))
                                .frame(height: 3)
                            Capsule()
                                .fill(Color.white)
                                .frame(width: geo.size.width * progressFraction(context), height: 3)
                        }
                    }
                    .frame(height: 3)
                }
            }

            Spacer()

            // Play/pause indicator
            Image(systemName: context.state.isPlaying ? "waveform" : "pause.fill")
                .font(.system(size: 20, weight: .medium))
                .foregroundColor(.white.opacity(0.7))
                .symbolEffect(.variableColor.iterative, isActive: context.state.isPlaying)
                .frame(width: 32)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .animation(.spring(response: 0.35), value: isBookmarkFresh(context))
    }
}

// MARK: - Shared formatter

private func formatTime(_ seconds: Double) -> String {
    guard seconds.isFinite, seconds >= 0 else { return "0:00" }
    let s = Int(seconds)
    let m = s / 60
    let h = m / 60
    if h > 0 {
        return String(format: "%d:%02d:%02d", h, m % 60, s % 60)
    }
    return String(format: "%d:%02d", m, s % 60)
}
