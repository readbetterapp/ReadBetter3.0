//
//  OptimizedReaderView.swift
//  ReadBetterApp3.0
//
//  High-performance reader with preloaded data.
//  Uses KaraokeEngine for smooth word synchronization.
//

import SwiftUI
import AVFoundation
import Combine
import QuartzCore
import UIKit
import OSLog

// MARK: - Text Size Enum
enum TextSize: String, CaseIterable, Hashable {
    case small = "S"
    case medium = "M"
    case large = "L"
    
    var fontSize: CGFloat {
        switch self {
        case .small: return 18
        case .medium: return 22
        case .large: return 26
        }
    }
    
    // Approximate line height (font size × line spacing factor)
    var lineHeight: CGFloat {
        return fontSize * 1.35
    }
    
    // Lines that fit on screen (measured on iPhone 15 Pro Max)
    func linesPerScreen(menuOpen: Bool) -> Int {
        switch (self, menuOpen) {
        case (.small, true):  return 20
        case (.small, false): return 24
        case (.medium, true): return 15
        case (.medium, false): return 21
        case (.large, true):  return 13
        case (.large, false): return 18
        }
    }
}

// MARK: - Submenu Type Enum
enum SubmenuType {
    case speed
    case textSize
    case highlight
    case background
}

// MARK: - Reader Background Color Enum
enum ReaderBackgroundColor: String, CaseIterable, Hashable {
    case light = "light"
    case dark = "dark"
    case cream = "cream"
    case blue = "blue"
    
    var displayName: String {
        switch self {
        case .light: return "Light"
        case .dark: return "Dark"
        case .cream: return "Cream"
        case .blue: return "Blue"
        }
    }
    
    var iconName: String {
        return "paintpalette.fill" // Always use paintpalette for main button
    }
    
    var color: Color {
        switch self {
        case .light:
            return Color(hex: "#F7FAFF") // Light mode background
        case .dark:
            return Color(hex: "#1c1c1e") // Dark mode background
        case .cream:
            return Color(hex: "#F7F3E9") // Cream background
        case .blue:
            return Color(hex: "#1E293B") // Blue background
        }
    }
}

// MARK: - Highlight Color Enum
enum HighlightColor: String, CaseIterable, Hashable {
    case none = "none"
    case yellow = "yellow"
    case blue = "blue"
    case green = "green"
    case pink = "pink"
    
    var color: Color {
        switch self {
        case .none: return .clear
        case .yellow: return Color(red: 254/255, green: 240/255, blue: 138/255) // #fef08a
        case .blue: return Color(red: 147/255, green: 197/255, blue: 253/255) // #93c5fd
        case .green: return Color(red: 134/255, green: 239/255, blue: 172/255) // #86efac
        case .pink: return Color(red: 251/255, green: 207/255, blue: 232/255) // #fbcfe8
        }
    }
    
    var displayName: String {
        switch self {
        case .none: return "None"
        case .yellow: return "Yellow"
        case .blue: return "Blue"
        case .green: return "Green"
        case .pink: return "Pink"
        }
    }
}

// MARK: - Preference Keys for Position Tracking
struct SentencePositionPreferenceKey: PreferenceKey {
    static var defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        // Multiple children emit this preference; avoid letting `.zero` overwrite a real frame.
        let next = nextValue()
        if next != .zero {
            value = next
        }
    }
}

struct ScrollViewHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// MARK: - Playback Controls Height Preference
struct PlaybackControlsHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// MARK: - Header Height Preference
struct HeaderHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// MARK: - Simplified Reading Container
struct ReadingContainerView<Content: View>: View {
    let headerHeight: CGFloat
    let playbackControlsHeight: CGFloat
    let safeMargin: CGFloat
    let isHeaderVisible: Bool
    let content: () -> Content
    
    // Effective header height (minimal when hidden, full height when visible)
    private var effectiveHeaderHeight: CGFloat {
        isHeaderVisible ? headerHeight + safeMargin : max(safeMargin - 20, 0)
    }
    
    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                // Header space - collapses when header is hidden
                Color.clear
                    .frame(height: effectiveHeaderHeight)
                
                // Scrollable content area - expands when header is hidden
                content()
                    .frame(height: geometry.size.height - effectiveHeaderHeight)
            }
            .animation(.easeInOut(duration: 0.3), value: isHeaderVisible)
        }
    }
}
struct OptimizedReaderView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @EnvironmentObject var router: AppRouter
    @EnvironmentObject var authManager: AuthManager
    @EnvironmentObject var bookmarkService: BookmarkService
    @EnvironmentObject var readingProgressService: ReadingProgressService
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    
    let preloadedData: PreloadedReaderData
    let initialSeekTime: Double?
    
    // MARK: - Spotify-style Overlay Mode Properties
    /// When true, the reader is presented as an overlay from mini player (Spotify-style)
    let isOverlayMode: Bool
    /// Animation namespace for matched geometry effect with mini player cover art
    var animationNamespace: Namespace.ID?
    /// Callback to collapse back to mini player (only used in overlay mode)
    var onDismiss: (() -> Void)?
    
    init(preloadedData: PreloadedReaderData, initialSeekTime: Double? = nil, isOverlayMode: Bool = false, animationNamespace: Namespace.ID? = nil, onDismiss: (() -> Void)? = nil) {
        self.preloadedData = preloadedData
        self.initialSeekTime = initialSeekTime
        self.isOverlayMode = isOverlayMode
        self.animationNamespace = animationNamespace
        self.onDismiss = onDismiss
    }

    // MARK: - Bookmark Toast
    private struct BookmarkToast: Identifiable {
        enum Kind {
            case saved
            case removed
        }
        
        let id = UUID()
        let kind: Kind
        let timeText: String
    }
    
    @StateObject private var karaokeEngine = KaraokeEngine()
    // Use singleton for background playback - player persists beyond view lifecycle
    @ObservedObject private var audioPlayer = OptimizedAudioPlayer.shared
    
    @State private var currentSentenceIndex: Int = 0
    @State private var displayLink: CADisplayLink?
    @State private var isScrubbing: Bool = false  // Track when user is scrubbing slider
    @State private var sliderValue: Double = 0  // Separate slider value to prevent fighting during scrubbing
    // Scroll proxy for resync button
    @State private var scrollProxy: ScrollViewProxy? = nil
    @State private var pendingSeekTime: Double? = nil  // Store target time during scrubbing, apply when scrubbing ends
    @State private var didApplyInitialSeek: Bool = false
    @State private var shouldScrollToCurrentOnAppear: Bool = false  // Flag to scroll to current position when already playing
    @State private var frozenCurrentWordIndex: Int? = nil  // Frozen value for views during scrubbing (prevents re-renders)
    @State private var frozenLastSpokenWordIndex: Int? = nil  // Frozen value for views during scrubbing (prevents re-renders)
    
    // Haptic feedback for word locks
    @State private var hapticGenerator: UIImpactFeedbackGenerator?
    @State private var lastHapticWordIndex: Int? = nil
    
    // Optimization: Cache word-to-sentence mapping for O(1) lookup
    @State private var wordToSentenceMap: [Int: Int] = [:]  // wordIndex -> sentenceIndex
    
    // Position tracking for resync button
    @State private var currentSentenceFrame: CGRect = .zero  // Track current sentence position
    @State private var scrollViewHeight: CGFloat = 0  // Track visible scroll view height
    @State private var scrollViewWidth: CGFloat = 0  // Track visible scroll view width (for text layout)
    @State private var playbackControlsHeight: CGFloat = 0  // Track menu height for safe area
    @State private var headerHeight: CGFloat = 0  // Track header height for safe area
    private let safeMargin: CGFloat = 12  // Tight padding requested
    
    // Autoscroll tracking
    @State private var lastAutoScrollTime: CFTimeInterval = 0
    @State private var lastAutoScrolledWordIndex: Int? = nil
    @State private var lastManualScrollTime: CFTimeInterval = 0  // Cooldown after manual scrolls (rewind/forward/tap)
    private let manualScrollCooldown: CFTimeInterval = 0.5  // 500ms cooldown to prevent double-scroll
    @State private var pendingCenterSentenceIndex: Int? = nil
    @State private var pendingResyncWordIndex: Int? = nil
    @State private var lineScrollMarkerOffsetY: CGFloat = 0
    @State private var cachedLineLayoutSentenceId: UUID? = nil
    @State private var cachedLineLayoutWidth: CGFloat = 0
    @State private var cachedLineLayoutTextSize: CGFloat = 0
    @State private var cachedLineLayoutLineSpacing: CGFloat = 0
    @State private var cachedLineLayoutRectsByWordIndex: [Int: CGRect] = [:]
    #if DEBUG
    @State private var showAutoScrollHUD: Bool = true
    #endif
    
    // MARK: - Simplified Scroll State
    enum ScrollMode {
        case none
        case playing
        case scrubbing
        case paused
    }
    
    @State private var scrollMode: ScrollMode = .none
    @State private var lastPauseScrollTime: Date? = nil
    
    // Chapter navigation
    var onChapterChange: ((Int) -> Void)?
    
    // Settings state with UserDefaults persistence
    @State private var textSize: TextSize = .medium
    @State private var playbackSpeed: Double = 1.0
    @State private var highlightColor: HighlightColor = .none
    @State private var readerBackgroundColor: ReaderBackgroundColor = .light
    @State private var didLoadSettings: Bool = false
    @State private var isMenuExpanded: Bool = true
    @State private var activeSubmenu: SubmenuType? = nil
    @State private var isChapterDropdownOpen: Bool = false  // Track chapter dropdown visibility
    @State private var isOutOfSync: Bool = false  // User scrolled away from auto-synced position
    
    // Bookmarking UI
    @State private var isBookmarkEditorPresented: Bool = false
    @State private var bookmarkEditorId: String = ""
    
    // Reading stats tracking
    @State private var sessionListeningSeconds: Double = 0
    @State private var lastPlayingStateTime: Date?
    @State private var bookmarkToast: BookmarkToast? = nil
    @State private var bookmarkToastTask: Task<Void, Never>? = nil
    @State private var chapterBookmarksBySentenceIndex: [Int: Double] = [:]
    @State private var isBookmarkToggleInFlight: Bool = false
    
    // Explainable Terms UI
    @State private var selectedExplainableTerm: ExplainableTerm? = nil
    @State private var explainableWordIndices: Set<Int> = []
    @State private var showExplanationOverlay: Bool = false
    
    // Text Search UI
    @State private var isSearchActive: Bool = false
    @State private var searchQuery: String = ""
    @State private var searchMatches: [SearchMatch] = []
    @State private var currentSearchMatchIndex: Int = 0
    @FocusState private var isSearchFieldFocused: Bool
    
    // Header auto-hide
    @State private var isHeaderVisible: Bool = true
    @State private var headerHideTask: Task<Void, Never>?
    private let headerAutoHideDelay: TimeInterval = 3.0 // 3 seconds
    
    // Search Match Model
    private struct SearchMatch: Identifiable {
        let id = UUID()
        let sentenceIndex: Int
        let range: Range<String.Index>
        let matchText: String
    }
    
    // MARK: - Scroll + Sync Performance (drag detection / throttling)
    @GestureState private var isUserDraggingScroll: Bool = false
    @StateObject private var syncGate = ReaderSyncGate()
    
    // UserDefaults keys
    private let textSizeKey = "readerTextSize"
    private let playbackSpeedKey = "readerPlaybackSpeed"
    private let highlightColorKey = "readerHighlightColor"
    private let readerBackgroundColorKey = "readerBackgroundColor"
    
    // Computed property for reader-specific theme colors
    private var readerColors: ThemeColors {
        switch readerBackgroundColor {
        case .light:
            // Light mode colors
            return ThemeColors(isDarkMode: false)
        case .dark:
            // Dark mode colors
            return ThemeColors(isDarkMode: true)
        case .cream:
            // Light cream background
            return ThemeColors(
                background: Color(hex: "#F7F3E9"), // Cream
                text: Color(hex: "#2D2D2D"), // Dark text
                textSecondary: Color(hex: "#6B6B6B"),
                divider: Color(hex: "#E5DCC8"),
                card: Color(hex: "#FEFCF8"),
                cardBorder: Color(hex: "#E5DCC8"),
                primary: Color(hex: "#2D2D2D"), // Dark for visibility on light background
                primaryText: Color(hex: "#FEFCF8"),
                accent: Color(hex: "#D4A574")
            )
        case .blue:
            // Darker blue background
            return ThemeColors(
                background: Color(hex: "#1E293B"), // Dark blue
                text: Color(hex: "#E2E8F0"), // Light text
                textSecondary: Color(hex: "#94A3B8"),
                divider: Color(hex: "#334155"),
                card: Color(hex: "#0F172A"),
                cardBorder: Color(hex: "#334155"),
                primary: Color(hex: "#60A5FA"),
                primaryText: Color(hex: "#0F172A"),
                accent: Color(hex: "#3B82F6")
            )
        }
    }
    
    // Helper to check if current background is light
    private var isLightBackground: Bool {
        readerBackgroundColor == .light || readerBackgroundColor == .cream
    }

    private var bookmarkMarkerColor: Color {
        highlightColor == .none ? readerColors.accent : highlightColor.color
    }
    
    private var isDescription: Bool {
        // Check if this is a description (dummy chapter with order -1 or id ending with "-description")
        preloadedData.chapter.order == -1 || preloadedData.chapter.id.hasSuffix("-description")
    }
    
    private var currentChapterIndex: Int {
        preloadedData.book.chapters.firstIndex(where: { $0.id == preloadedData.chapter.id }) ?? -1
    }
    
    private var hasPreviousChapter: Bool {
        // No navigation for descriptions
        guard !isDescription else { return false }
        return currentChapterIndex > 0
    }
    
    private var hasNextChapter: Bool {
        // No navigation for descriptions
        guard !isDescription else { return false }
        return currentChapterIndex >= 0 && currentChapterIndex < preloadedData.book.chapters.count - 1
    }
    
    // Check if book has any chapters to navigate
    private var hasChapters: Bool {
        guard !isDescription else { return false }
        return preloadedData.book.chapters.count > 1
    }
    
    #if DEBUG
    private var autoScrollDebugOverlay: some View {
        let sentenceIsZero = currentSentenceFrame == .zero
        let isLong = currentSentenceFrame.height > fieldOfViewHeight
        let bandHeight = fieldOfViewHeight
        
        // Progress-based word position estimation (matches new algorithm)
        var wordProgress: CGFloat = 0
        var estimatedWordY: CGFloat = 0
        var triggerY: CGFloat = 0
        var pNormalized: CGFloat = 0
        
        if currentSentenceIndex >= 0, currentSentenceIndex < preloadedData.sentences.count,
           let wordIndex = karaokeEngine.currentWordIndex {
            let sentence = preloadedData.sentences[currentSentenceIndex]
            if let localPos = sentence.globalWordIndices.firstIndex(of: wordIndex), !sentence.globalWordIndices.isEmpty {
                wordProgress = CGFloat(localPos + 1) / CGFloat(sentence.globalWordIndices.count)
                estimatedWordY = currentSentenceFrame.minY + (wordProgress * currentSentenceFrame.height)
                triggerY = fieldOfViewTopY + (bandHeight * markerTriggerPercent)
                pNormalized = (bandHeight > 1) ? (estimatedWordY - fieldOfViewTopY) / bandHeight : 0
            }
        }
        
        return VStack(alignment: .leading, spacing: 4) {
            Text("AutoScroll")
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
            Text("enabled=\(isPlaybackAutoScrollEnabled ? "1" : "0") play=\(audioPlayer.isPlaying ? "1" : "0") out=\(isOutOfSync ? "1" : "0") scrub=\(isScrubbing ? "1" : "0") drag=\(isUserDraggingScroll ? "1" : "0")")
                .font(.system(size: 11, design: .monospaced))
            Text("sentenceZero=\(sentenceIsZero ? "1" : "0") long=\(isLong ? "1" : "0") sH=\(Int(currentSentenceFrame.height)) bandH=\(Int(bandHeight))")
                .font(.system(size: 11, design: .monospaced))
            Text(String(format: "wordProg=%.2f estY=%.0f trigY=%.0f p=%.2f", wordProgress, estimatedWordY, triggerY, pNormalized))
                .font(.system(size: 11, design: .monospaced))
        }
        .padding(8)
        .background(Color.black.opacity(0.7))
        .foregroundColor(.white)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .padding(.top, 8)
        .padding(.leading, 8)
        .allowsHitTesting(false)
    }
    #endif
    
    var body: some View {
        ZStack {
            readerColors.background
                .ignoresSafeArea()
                // Avoid a launch "flash" where we render the default `.light` background for 1 frame,
                // then immediately switch to the saved value when `loadSettings()` runs in `.onAppear`.
                .animation(didLoadSettings ? .easeInOut(duration: 0.4) : nil, value: readerBackgroundColor) // Smooth fade transition after initial load
            
            // Tap outside to close dropdown
            if isChapterDropdownOpen {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            isChapterDropdownOpen = false
                        }
                    }
            }
            
            VStack(spacing: 0) {
                // Header - fades and collapses when hidden
                headerView
                    .opacity(isHeaderVisible ? 1 : 0)
                    .frame(height: isHeaderVisible ? nil : 0, alignment: .top)
                    .clipped()
                    .animation(.easeInOut(duration: 0.3), value: isHeaderVisible)
                    .zIndex(100) // Ensure header is above content
                    #if DEBUG
                    .simultaneousGesture(
                        TapGesture(count: 2).onEnded {
                            showAutoScrollHUD.toggle()
                        }
                    )
                    #endif
                
                // Text Display with Simplified Container
                ReadingContainerView(
                    headerHeight: headerHeight,
                    playbackControlsHeight: playbackControlsHeight,
                    safeMargin: safeMargin,
                    isHeaderVisible: isHeaderVisible
                ) {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 20) {
                                ForEach(Array(preloadedData.sentences.enumerated()), id: \.element.id) { index, sentence in
                                    OptimizedSentenceView(
                                        sentence: sentence,
                                        sentenceIndex: index,
                                        isBookmarked: chapterBookmarksBySentenceIndex[index] != nil,
                                        currentSentenceIndex: currentSentenceIndex,
                                        scrollIDSuffix: readerBackgroundColor.rawValue,
                                        lineMarkerID: sentenceLineMarkerScrollID(index),
                                        lineMarkerOffsetY: lineScrollMarkerOffsetY,
                                        currentWordIndex: karaokeEngine.currentWordIndex,
                                        lastSpokenWordIndex: karaokeEngine.lastSpokenWordIndex,
                                        themeColors: readerColors,
                                        textSize: textSize.fontSize,
                                        highlightColor: highlightColor,
                                        indexedWords: preloadedData.indexedWords,
                                        explainableWordIndices: explainableWordIndices,
                                        searchMatches: searchMatches.filter { $0.sentenceIndex == index }.map { $0.range },
                                        currentSearchMatchIndex: {
                                            // Check if the current global search match is in this sentence
                                            guard currentSearchMatchIndex < searchMatches.count,
                                                  searchMatches[currentSearchMatchIndex].sentenceIndex == index else {
                                                return nil
                                            }
                                            // Find which position this match is within this sentence's matches
                                            let matchesInThisSentence = searchMatches.enumerated().filter { $0.element.sentenceIndex == index }
                                            return matchesInThisSentence.firstIndex(where: { $0.offset == currentSearchMatchIndex })
                                        }(),
                                    containerWidth: scrollViewWidth - 40, // Account for horizontal padding
                                    onSentenceTap: {
                                        // Reset timer if header visible, but don't reopen if hidden
                                        handleUserInteraction(shouldReopen: false)
                                        
                                        // Tap-to-seek: jump to sentence's start time
                                        let seekTime = sentence.startTime
                                        let tappedIndex = index
                                            
                                            Task { @MainActor in
                                                // Use seekAndWait to ensure audio has actually moved before updating UI.
                                                // This prevents race conditions during playback.
                                                let actualTime = await audioPlayer.seekAndWait(to: seekTime)
                                                
                                                karaokeEngine.resetSearchState()
                                                karaokeEngine.updateTime(actualTime, duration: audioPlayer.duration)
                                                
                                                // Directly set the sentence index (we know which one was tapped)
                                                currentSentenceIndex = tappedIndex
                                                isOutOfSync = false
                                                
                                                hapticGenerator?.impactOccurred(intensity: 0.5)
                                                
                                                // Scroll to bring the tapped sentence into view using our smart positioning
                                                jumpToSyncPosition(time: actualTime)
                                            }
                                        },
                                        onExplainableWordTap: { wordIndex in
                                            // Show explanation overlay for the tapped explainable word
                                            if let term = ExplainableTermsService.shared.getTerm(at: wordIndex, chapterId: preloadedData.chapter.id) {
                                                selectedExplainableTerm = term
                                                showExplanationOverlay = true
                                                hapticGenerator?.impactOccurred(intensity: 0.3)
                                            }
                                        }
                                    )
                                    .equatable() // Use Equatable to prevent unnecessary re-renders
                                    .id("\(index)-\(readerBackgroundColor.rawValue)") // Include background color in id to force rebuild on color change
                                    .background(
                                        // CRITICAL FIX: Always measure, but only write preference for current sentence
                                        // This prevents GeometryReader from appearing/disappearing during layout (which causes warnings)
                                        GeometryReader { geometry in
                                            Color.clear
                                                .preference(
                                                    key: SentencePositionPreferenceKey.self,
                                                    value: index == currentSentenceIndex 
                                                        ? geometry.frame(in: .named("scroll"))
                                                        : .zero  // Only write non-zero for current sentence (handler ignores .zero)
                                                )
                                        }
                                    )
                                }
                            }
                            .padding(.horizontal, 20)
                            .padding(.top, scrollContentVerticalPadding + (isMenuExpanded ? 0 : 50))
                            .padding(.bottom, playbackControlsHeight + 24) // Extra bottom padding so content can scroll under controls
                        }
                        // IMPORTANT: Measure the actual visible ScrollView viewport (not content geometry).
                        .background(
                            GeometryReader { viewportGeo in
                                Color.clear
                                    .onAppear {
                                        scrollViewHeight = viewportGeo.size.height
                                        scrollViewWidth = viewportGeo.size.width
                                    }
                                    .onChange(of: viewportGeo.size.height) { _, h in
                                        scrollViewHeight = h
                                    }
                                    .onChange(of: viewportGeo.size.width) { _, w in
                                        scrollViewWidth = w
                                    }
                            }
                        )
                        .coordinateSpace(name: "scroll")
                        .scrollIndicators(.hidden)
                        // Tap to show header
                        .contentShape(Rectangle())
                        .onTapGesture {
                            handleUserInteraction()
                        }
                        // Detect user-driven scroll to mark out-of-sync
                        .simultaneousGesture(
                            // Avoid marking out-of-sync on incidental taps; require a real drag.
                            DragGesture(minimumDistance: 10)
                                .updating($isUserDraggingScroll) { _, state, _ in
                                    state = true
                                }
                                .onChanged { _ in
                                    // Only mark out-of-sync when user scrolls (not scrubbing)
                                    guard !isScrubbing else { return }
                                    isOutOfSync = true
                                }
                        )
                        .overlay(
                            // Track scroll offset for proper coordinate calculations
                            GeometryReader { scrollOffsetGeometry in
                                Color.clear
                                    .preference(
                                        key: ScrollOffsetPreferenceKey.self,
                                        value: scrollOffsetGeometry.frame(in: .named("scroll")).minY
                                    )
                            }
                            .frame(height: 0)
                        )
                        .onAppear {
                            // Initialize scroll mode
                            scrollMode = audioPlayer.isPlaying ? .playing : .paused
                            
                            // Store proxy reference for use outside ScrollViewReader scope
                            scrollProxy = proxy
                            
                            // If we need to scroll to current position
                            if shouldScrollToCurrentOnAppear {
                                shouldScrollToCurrentOnAppear = false
                                
                                // Scroll to current sentence after a brief delay to let layout settle
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                    // Try to get sentence from karaoke engine first (already playing case)
                                    if let wordIndex = karaokeEngine.currentWordIndex,
                                       let sentenceIndex = wordToSentenceMap[wordIndex] {
                                        currentSentenceIndex = sentenceIndex
                                        proxy.scrollTo(sentenceScrollID(sentenceIndex), anchor: .center)
                                        print("⚡ Scrolled to sentence \(sentenceIndex) for word \(wordIndex)")
                                    }
                                    // Otherwise use currentSentenceIndex if it was set (fresh load with seek)
                                    else if currentSentenceIndex > 0 {
                                        proxy.scrollTo(sentenceScrollID(currentSentenceIndex), anchor: .center)
                                        print("⚡ Scrolled to pre-set sentence \(currentSentenceIndex)")
                                    }
                                    // Or check if we have initialSeekTime and find the sentence
                                    else if let seekTime = initialSeekTime, seekTime > 0,
                                            let sentenceIndex = findSentenceAtTime(seekTime) {
                                        currentSentenceIndex = sentenceIndex
                                        proxy.scrollTo(sentenceScrollID(sentenceIndex), anchor: .center)
                                        print("⚡ Scrolled to sentence \(sentenceIndex) for initialSeekTime \(seekTime)")
                                    }
                                }
                            }
                        }
                        .onPreferenceChange(SentencePositionPreferenceKey.self) { frame in
                        // Only update frame if it's valid and for the current sentence
                        // This prevents false updates from other sentences
                        guard frame != .zero else { return }
                        DispatchQueue.main.async {
                            currentSentenceFrame = frame
                            // #region agent log
                            agentDebugLog("H1", "OptimizedReaderView.swift:SentencePositionPreference", "updated currentSentenceFrame", [
                                "frameMinY": frame.minY,
                                "frameHeight": frame.height,
                                "currentSentenceIndex": currentSentenceIndex
                            ])
                            // #endregion agent log
                            
                            // SINGLE-SOURCE centering decision: center only if measured height fits band.
                            // Note: Long sentences with word targets are now handled directly in jumpToSyncPosition
                            // to avoid double-jump. This handler only deals with short sentence centering.
                            if let pending = pendingCenterSentenceIndex, pending == currentSentenceIndex {
                                defer {
                                    pendingCenterSentenceIndex = nil
                                    pendingResyncWordIndex = nil
                                }
                                
                                guard let proxy = scrollProxy else { return }
                                
                                let sentenceID = sentenceScrollID(pending)
                                
                                if frame.height <= fieldOfViewHeight {
                                    // Short sentence: smooth center animation.
                                    scrollWithAnimation {
                                        proxy.scrollTo(sentenceID, anchor: .center)
                                    }
                                }
                                // Long sentences are handled directly in jumpToSyncPosition - no second jump needed.
                            }
                        }
                    }
                    .onChange(of: karaokeEngine.currentWordIndex) { oldValue, newValue in
                        // CRITICAL FIX: Use DispatchQueue.main.async for stronger deferral - guarantees next runloop tick
                        // The onChange handler runs during view updates, so we must defer everything
                        // Capture proxy explicitly for async closure
                        let capturedProxy = proxy
                        DispatchQueue.main.async {
                            // During scrubbing, word highlighting continues following audio
                            // Scrolling is paused during scrubbing to prevent jarring movement
                            guard !isScrubbing else { return }
                            
                            // CRITICAL FIX: Don't scroll if wordIndex is invalid (-1 or nil)
                            // This prevents scrolling when there's no valid word
                            guard let wordIndex = newValue, wordIndex >= 0 else {
                                return
                            }
                            
                            // #region agent log
                            agentDebugLog("H3", "OptimizedReaderView.swift:currentWordIndex", "word change", [
                                "wordIndex": wordIndex,
                                "currentSentenceIndex": currentSentenceIndex,
                                "foundSentenceIndex": findSentenceAtTime(getCurrentAudioTime()) ?? -1
                            ])
                            // #endregion agent log
                            
                            // Trigger haptic feedback when word changes during normal playback
                            // Avoid haptics while the user is actively dragging the scroll view (reduces scroll hitching)
                            if !syncGate.isUserDraggingScroll, wordIndex != lastHapticWordIndex {
                                hapticGenerator?.impactOccurred(intensity: 0.7)
                                lastHapticWordIndex = wordIndex
                            }
                            
                            // Time-based sentence lookup for scrolling only (highlighting is time/word-driven)
                            let currentTime = getCurrentAudioTime()
                            let sentenceIndex = findSentenceAtTime(currentTime)
                            
                            guard let sentenceIndex else {
                                // No sentence found; skip scrolling but keep highlighting active
                                return
                            }
                            
                            let didAdvanceSentence = sentenceIndex != currentSentenceIndex
                            if didAdvanceSentence {
                                currentSentenceIndex = sentenceIndex
                                lineScrollMarkerOffsetY = 0
                                cachedLineLayoutSentenceId = nil
                                cachedLineLayoutRectsByWordIndex = [:]
                                
                                if isPlaybackAutoScrollEnabled {
                                    autoScrollOnSentenceAdvance(to: sentenceIndex, proxy: capturedProxy)
                                }
                            } else {
                                if isPlaybackAutoScrollEnabled {
                                    autoScrollLongSentenceIfNeeded(wordIndex: wordIndex, proxy: capturedProxy)
                                }
                            }
                        }
                    }
                    .onChange(of: isScrubbing) { oldValue, newValue in
                        // CRITICAL FIX: Use DispatchQueue.main.async for stronger deferral - guarantees next runloop tick
                        DispatchQueue.main.async {
                            if newValue {
                                // Scrubbing started - update mode and prepare haptic
                                scrollMode = .scrubbing
                                hapticGenerator?.prepare()
                                // Show header during scrubbing
                                showHeader()
                            } else {
                                // Scrubbing ended - resume playing mode and reset haptic tracking
                                lastHapticWordIndex = nil
                                scrollMode = .playing
                                // Schedule hide if still playing
                                if audioPlayer.isPlaying {
                                    scheduleHeaderHide()
                                }
                            }
                        }
                    }
                    .onChange(of: audioPlayer.currentTime) { oldValue, newValue in
                        // CRITICAL FIX: Defer state modification to avoid "modifying state during view update" warning
                        DispatchQueue.main.async {
                            // Keep slider value in sync with audio player when not scrubbing
                            // This ensures smooth slider movement during normal playback
                            if !isScrubbing {
                                sliderValue = newValue
                            }

                            // Keep Lock Screen / Control Center in sync.
                            // Now Playing updates are handled by the audio player internally
                        }
                    }
                    .onChange(of: audioPlayer.isPlaying) { oldValue, newValue in
                        // Update scroll mode when playback state changes
                        DispatchQueue.main.async {
                            if newValue {
                                // Started playing - set mode to playing (unless scrubbing)
                                if scrollMode != .scrubbing {
                                    scrollMode = .playing
                                }
                                // Schedule header auto-hide when playing starts
                                scheduleHeaderHide()
                            } else {
                                // Paused - set mode to paused
                                if scrollMode != .scrubbing {
                                    scrollMode = .paused
                                }
                                // Show and keep header and menu visible when paused
                                headerHideTask?.cancel()
                                withAnimation(.easeIn(duration: 0.2)) {
                                    isHeaderVisible = true
                                    isMenuExpanded = true
                                }
                            }
                        }
                    }
                } // Close ScrollViewReader
                } // Close ReadingContainerView content
            } // Close VStack
            
            // Playback Controls - stays in place, gets covered by keyboard when search is active
            VStack {
                Spacer()
                playbackControls
            }
            .ignoresSafeArea(.keyboard, edges: .bottom) // Menu stays in place, keyboard covers it
            
            // Search Bar Overlay - stays above keyboard when typing
            if isSearchActive {
                VStack(spacing: 0) {
                    Spacer()
                    searchBarView
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .zIndex(999)
            }

            // Center toast confirmation (non-blocking overlay)
            if let toast = bookmarkToast {
                VStack(spacing: 10) {
                    Image(systemName: toast.kind == .saved ? "bookmark.fill" : "bookmark.slash")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundColor(readerColors.primary)
                    
                    Text(toast.kind == .saved ? "Bookmark saved" : "Bookmark removed")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(readerColors.text)
                    
                    Text("At \(toast.timeText)")
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .foregroundColor(readerColors.textSecondary)
                }
                .padding(.vertical, 18)
                .padding(.horizontal, 22)
                .background(readerColors.card.opacity(isLightBackground ? 0.96 : 0.92))
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(readerColors.cardBorder, lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(themeManager.isDarkMode ? 0.35 : 0.18), radius: 14, x: 0, y: 8)
                .frame(maxWidth: 280)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .transition(.opacity)
                .zIndex(1000)
                .allowsHitTesting(false)
            }
            
            // Explainable term overlay - shows context-specific explanations
            if showExplanationOverlay, let term = selectedExplainableTerm {
                ExplanationOverlayView(
                    term: term,
                    themeColors: readerColors,
                    isLightBackground: isLightBackground,
                    onDismiss: {
                        withAnimation(.easeOut(duration: 0.2)) {
                            showExplanationOverlay = false
                            selectedExplainableTerm = nil
                        }
                    }
                )
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
                .zIndex(1001)
            }
            
            #if DEBUG
            if showAutoScrollHUD {
                VStack {
                    autoScrollDebugOverlay
                    Spacer()
                }
                .zIndex(9999)
            }
            #endif
            
            // Chapter dropdown menu - positioned at body level to avoid clipping
            if isChapterDropdownOpen && hasChapters {
                VStack {
                    Spacer()
                        .frame(height: 64) // Height of header
                    
                    HStack {
                        Spacer()
                        
                        chapterDropdownMenu
                            .padding(.top, 8)
                        
                        Spacer()
                    }
                    
                    Spacer()
                }
                .zIndex(200) // Above header but below tap-outside overlay
            }
        }
        .onAppear {
            // Load saved settings from UserDefaults WITHOUT animating the initial state change
            // (prevents a brief white flash behind the menu on first render).
            var tx = Transaction()
            tx.disablesAnimations = true
            withTransaction(tx) {
                loadSettings()
            }
            didLoadSettings = true

            // Prime bookmark cache for this chapter (powers markers/ticks + fast lookup)
            Task { @MainActor in
                rebuildChapterBookmarkCache()
            }
            
            // Load explainable terms and build word index lookup using TEXT MATCHING
            Task { @MainActor in
                // Fetch and cache terms first (await ensures data is ready)
                let terms = await ExplainableTermsService.shared.getTerms(
                    for: preloadedData.book.id,
                    chapterId: preloadedData.chapter.id
                )
                
                if !terms.terms.isEmpty {
                    // v2.0: Build lookup by matching term TEXT against indexed words
                    // This matches ALL occurrences of each term in the chapter
                    let indices = ExplainableTermsService.shared.buildLookup(
                        for: preloadedData.chapter.id,
                        indexedWords: preloadedData.indexedWords
                    )
                    explainableWordIndices = indices
                }
            }

            // Prepare background audio session + interruption handling (activation happens on play).
            AudioSessionController.shared.configureIfNeeded()
            var shouldResumeAfterInterruption = false
            AudioSessionController.shared.onPauseRequested = { [weak player = audioPlayer] in
                guard let player else { return }
                shouldResumeAfterInterruption = player.isPlaying
                player.pause()
            }
            AudioSessionController.shared.onResumeRequested = { [weak player = audioPlayer] in
                guard let player else { return }
                // Resume when:
                // - iOS indicates we should resume (we were playing when interruption began), OR
                // - user explicitly pressed Play during an interruption (pending play request).
                let pending = AudioSessionController.shared.consumePendingPlayRequest()
                guard shouldResumeAfterInterruption || pending else { return }
                shouldResumeAfterInterruption = false
                player.play()
            }
            
            // NO WORK HERE - everything is preloaded!
            
            // Build word-to-sentence map for O(1) lookup (only once!)
            // Add validation to ensure all words are mapped correctly
            var map: [Int: Int] = [:]
            var totalWordsMapped = 0
            for (sentenceIndex, sentence) in preloadedData.sentences.enumerated() {
                for wordIndex in sentence.globalWordIndices {
                    // Validate word index is valid
                    guard wordIndex >= 0 else {
                        print("⚠️ Warning: Invalid word index \(wordIndex) in sentence \(sentenceIndex)")
                        continue
                    }
                    // If word already mapped, log warning (shouldn't happen, but handle gracefully)
                    if let existingSentence = map[wordIndex], existingSentence != sentenceIndex {
                        print("⚠️ Warning: Word \(wordIndex) already mapped to sentence \(existingSentence), now also in sentence \(sentenceIndex)")
                    }
                    map[wordIndex] = sentenceIndex
                    totalWordsMapped += 1
                }
            }
            wordToSentenceMap = map
            print("✅ Built word-to-sentence map: \(totalWordsMapped) words mapped across \(preloadedData.sentences.count) sentences")
            
            // Initialize haptic feedback generator for smooth, instant word lock feedback
            hapticGenerator = UIImpactFeedbackGenerator(style: .soft)
            hapticGenerator?.prepare()
            
            // Set audio time getter for event-driven word sync
            // Use singleton directly - it won't be deallocated
            karaokeEngine.setAudioTimeGetter {
                OptimizedAudioPlayer.shared.getCurrentTime()
            }
            
            // Setup CADisplayLink for 60fps word sync updates (replaces AVPlayer time observer)
            // Use a closure-based target to access view properties
            let target = DisplayLinkTarget(
                minIntervalProvider: { [weak syncGate] in
                    // Keep highlighting active while dragging, but reduce update frequency so scrolling stays smooth.
                    guard let gate = syncGate else { return 1.0 / 60.0 }
                    return gate.isUserDraggingScroll ? (1.0 / 30.0) : (1.0 / 60.0)
                },
                callback: { [weak karaokeEngine] in
                    // CADisplayLink fires on the main runloop; avoid creating a Task per frame.
                    // Use singleton directly - it won't be deallocated
                    guard let engine = karaokeEngine else { return }
                    let player = OptimizedAudioPlayer.shared
                    let currentTime = player.getCurrentTime()
                    engine.updateTime(currentTime, duration: player.duration)
                }
            )
            
            let newDisplayLink = CADisplayLink(target: target, selector: #selector(DisplayLinkTarget.tick(_:)))
            newDisplayLink.preferredFramesPerSecond = 60
            newDisplayLink.add(to: .main, forMode: .common)
            displayLink = newDisplayLink
            
            // Load pre-built data instantly (no computation!)
            karaokeEngine.loadPrebuiltData(
                indexedWords: preloadedData.indexedWords,
                sentences: preloadedData.sentences,
                totalWords: preloadedData.totalWords
            )
            
            // Setup audio - either skip if already playing, or load fresh
            setupAudioOnAppear()
        }
        .onChange(of: playbackSpeed) { oldValue, newValue in
            // Update audio player speed when setting changes
            audioPlayer.setPlaybackSpeed(newValue)
            // Save to UserDefaults
            UserDefaults.standard.set(newValue, forKey: playbackSpeedKey)
        }
        .onChange(of: textSize) { oldValue, newValue in
            // Save to UserDefaults
            UserDefaults.standard.set(newValue.rawValue, forKey: textSizeKey)
        }
        .onChange(of: highlightColor) { oldValue, newValue in
            // Save to UserDefaults
            UserDefaults.standard.set(newValue.rawValue, forKey: highlightColorKey)
        }
        .onChange(of: readerBackgroundColor) { oldValue, newValue in
            // Save to UserDefaults
            UserDefaults.standard.set(newValue.rawValue, forKey: readerBackgroundColorKey)
        }
        // Note: long/short classification is now derived only from `currentSentenceFrame.height > fieldOfViewHeight`.
        .onPreferenceChange(HeaderHeightPreferenceKey.self) { value in
            DispatchQueue.main.async {
                headerHeight = value
            }
        }
        .onPreferenceChange(PlaybackControlsHeightPreferenceKey.self) { value in
            DispatchQueue.main.async {
                playbackControlsHeight = value
            }
        }
        .onChange(of: isUserDraggingScroll) { _, newValue in
            // Mirror transient GestureState into an object the display-link throttle can read.
            syncGate.isUserDraggingScroll = newValue
        }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .active:
                // When returning from background, CADisplayLink may have paused.
                // Re-sync word highlighting (and scroll if still in auto-sync mode).
                DispatchQueue.main.async {
                    let t = getCurrentAudioTime()
                    karaokeEngine.resetSearchState()
                    karaokeEngine.updateTime(t, duration: audioPlayer.duration)

                    if let sentenceIndex = findSentenceAtTime(t) {
                        currentSentenceIndex = sentenceIndex
                    }

                    if !isOutOfSync && !isScrubbing {
                        jumpToSyncPosition(time: t)
                    }
                    
                    // Schedule header auto-hide if playing
                    if audioPlayer.isPlaying {
                        scheduleHeaderHide()
                    }
                }
                // Resume listening time tracking if playing
                if audioPlayer.isPlaying {
                    lastPlayingStateTime = Date()
                }
            case .inactive, .background:
                // Save progress when app goes to background
                saveReadingProgress()
                // Force sync to cloud immediately
                readingProgressService.forceSyncToCloud()
                // Log accumulated listening time
                logSessionListeningTime()
                ReadingStatsService.shared.forceSyncToCloud()
            @unknown default:
                break
            }
        }
        .onChange(of: audioPlayer.isPlaying) { _, isPlaying in
            if isPlaying {
                // Started playing - record the time
                lastPlayingStateTime = Date()
            } else {
                // Stopped playing - accumulate listening time
                if let lastTime = lastPlayingStateTime {
                    let elapsed = Date().timeIntervalSince(lastTime)
                    if elapsed > 0 && elapsed < 3600 { // Sanity check: max 1 hour per segment
                        sessionListeningSeconds += elapsed
                    }
                }
                lastPlayingStateTime = nil
            }
        }
        .onReceive(bookmarkService.$bookmarks) { _ in
            Task { @MainActor in
                rebuildChapterBookmarkCache()
            }
        }
        .sheet(isPresented: $isBookmarkEditorPresented) {
            BookmarkEditSheet(bookmarkId: bookmarkEditorId)
                .environmentObject(themeManager)
                .environmentObject(bookmarkService)
        }
        .onDisappear {
            // Save reading progress on view disappear
            saveReadingProgress()
            
            // Log accumulated listening time for stats
            logSessionListeningTime()
            
            // Clean up CADisplayLink
            displayLink?.invalidate()
            displayLink = nil
            
            // Cancel pending toast dismiss work
            bookmarkToastTask?.cancel()
            bookmarkToastTask = nil
            
            // Cancel header hide task
            headerHideTask?.cancel()
            headerHideTask = nil
            
            // Clean up timers
            karaokeEngine.reset()
        }
    }
    
    // MARK: - Header
    private var headerView: some View {
        HStack {
            Button(action: {
                // Save reading progress before closing
                saveReadingProgress()
                // DON'T stop playback when closing the reader - allow background playback to continue.
                // The audio player is a singleton and will keep playing.
                // User can control playback from Lock Screen / Control Center.
                
                if isOverlayMode, let onDismiss = onDismiss {
                    // Spotify-style: Collapse back to mini player
                    onDismiss()
                } else {
                    // Standard mode: Navigate to tabs and dismiss
                    router.navigateBackToTabs()
                dismiss()
                }
            }) {
                // Use chevron.down in overlay mode for Spotify-style collapse hint
                Image(systemName: isOverlayMode ? "chevron.down" : "xmark")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(readerColors.text)
                    .frame(width: 40, height: 40)
            }
            
            Spacer()
            
            // Chapter navigation and title
            HStack(spacing: 16) {
                // Previous chapter button - only show if there are chapters and we have a previous chapter
                if hasChapters && hasPreviousChapter {
                    Button(action: {
                        goToPreviousChapter()
                    }) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(readerColors.text)
                            .frame(width: 32, height: 32)
                    }
                } else if hasChapters && !hasPreviousChapter {
                    // Show placeholder to maintain spacing when only next button is visible
                    Color.clear
                        .frame(width: 32, height: 32)
                }
                
                VStack(spacing: 2) {
                    // Chapter title - tappable to open dropdown
                    Button(action: {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            isChapterDropdownOpen.toggle()
                        }
                    }) {
                        HStack(spacing: 4) {
                            Text(preloadedData.chapter.title)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(readerColors.text)
                                .lineLimit(1)
                            
                            // Dropdown indicator
                            Image(systemName: isChapterDropdownOpen ? "chevron.up" : "chevron.down")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(readerColors.textSecondary)
                        }
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    Text(preloadedData.book.title)
                        .font(.system(size: 12))
                        .foregroundColor(readerColors.textSecondary)
                        .lineLimit(1)
                }
                .frame(minWidth: 120)
                
                // Next chapter button - only show if there are chapters and we have a next chapter
                if hasChapters && hasNextChapter {
                    Button(action: {
                        goToNextChapter()
                    }) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(readerColors.text)
                            .frame(width: 32, height: 32)
                    }
                } else if hasChapters && !hasNextChapter {
                    // Show placeholder to maintain spacing when only previous button is visible
                    Color.clear
                        .frame(width: 32, height: 32)
                }
            }
            
            Spacer()
            
            // Placeholder for symmetry
            Color.clear
                .frame(width: 40, height: 40)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .safeAreaInset(edge: .top, spacing: 0) { Color.clear.frame(height: 0) } // Force respect top safe area
        .padding(.top, getSafeAreaTop()) // Add status bar padding
        .background(
            GeometryReader { geo in
                Color.clear
                    .preference(
                        key: HeaderHeightPreferenceKey.self,
                        value: geo.size.height
                    )
            }
        )
    }
    
    // Helper to get top safe area inset
    private func getSafeAreaTop() -> CGFloat {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first else {
            return 44 // Default fallback
        }
        return window.safeAreaInsets.top
    }
    
    // Helper to get bottom safe area inset
    private func getSafeAreaBottom() -> CGFloat {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first else {
            return 34 // Default fallback for home indicator
        }
        return window.safeAreaInsets.bottom
    }
    
    // MARK: - Chapter Navigation
    private func goToPreviousChapter() {
        guard hasPreviousChapter else { return }
        // Save progress before changing chapters
        saveReadingProgress()
        // Just pause - the new chapter will load fresh audio
        audioPlayer.pause()
        let prevChapterOrder = preloadedData.book.chapters.sorted { $0.order < $1.order }[currentChapterIndex - 1].order
        
        if isOverlayMode {
            // In overlay mode: collapse first, then navigate
            onDismiss?()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                router.navigate(to: .reader(bookId: preloadedData.book.id, chapterNumber: prevChapterOrder + 1))
            }
        } else {
            // Standard mode: Navigate immediately to prevent showing "ready page"
        router.replace(with: .reader(bookId: preloadedData.book.id, chapterNumber: prevChapterOrder + 1))
        dismiss()
        }
    }
    
    private func goToNextChapter() {
        guard hasNextChapter else { return }
        // Save progress and mark current chapter as complete
        saveReadingProgress()
        readingProgressService.markChapterComplete(bookId: preloadedData.book.id, chapterId: preloadedData.chapter.id)
        // Log chapter completion for stats
        ReadingStatsService.shared.logChapterComplete(bookId: preloadedData.book.id)
        // Just pause - the new chapter will load fresh audio
        audioPlayer.pause()
        let nextChapterOrder = preloadedData.book.chapters.sorted { $0.order < $1.order }[currentChapterIndex + 1].order
        
        if isOverlayMode {
            // In overlay mode: collapse first, then navigate
            onDismiss?()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                router.navigate(to: .reader(bookId: preloadedData.book.id, chapterNumber: nextChapterOrder + 1))
            }
        } else {
            // Standard mode: Navigate immediately to prevent showing "ready page"
        router.replace(with: .reader(bookId: preloadedData.book.id, chapterNumber: nextChapterOrder + 1))
        dismiss()
        }
    }
    
    private func goToChapter(_ chapterOrder: Int) {
        // Save progress before changing chapters
        saveReadingProgress()
        // Mark current chapter as complete if we're near the end
        if audioPlayer.currentTime > audioPlayer.duration * 0.95 {
            readingProgressService.markChapterComplete(bookId: preloadedData.book.id, chapterId: preloadedData.chapter.id)
            // Log chapter completion for stats
            ReadingStatsService.shared.logChapterComplete(bookId: preloadedData.book.id)
        }
        // Just pause - the new chapter will load fresh audio
        audioPlayer.pause()
        // Close dropdown
        isChapterDropdownOpen = false
        
        if isOverlayMode {
            // In overlay mode: collapse first, then navigate
            onDismiss?()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                router.navigate(to: .reader(bookId: preloadedData.book.id, chapterNumber: chapterOrder + 1))
            }
        } else {
            // Standard mode: Navigate immediately to prevent showing "ready page"
        // This ensures ReaderLoadingView appears right away, no intermediate view flash
        router.replace(with: .reader(bookId: preloadedData.book.id, chapterNumber: chapterOrder + 1))
        dismiss()
        }
    }
    
    // MARK: - Reading Stats
    private func logSessionListeningTime() {
        // If still playing, accumulate time since last check
        if let lastTime = lastPlayingStateTime {
            let elapsed = Date().timeIntervalSince(lastTime)
            if elapsed > 0 && elapsed < 3600 { // Sanity check: max 1 hour per segment
                sessionListeningSeconds += elapsed
            }
            lastPlayingStateTime = nil
        }
        
        // Log to stats service if we have meaningful listening time (at least 5 seconds)
        if sessionListeningSeconds >= 5 {
            ReadingStatsService.shared.logListeningTime(
                seconds: sessionListeningSeconds,
                bookId: preloadedData.book.id
            )
            sessionListeningSeconds = 0 // Reset for next session
        }
    }
    
    // MARK: - Reading Progress
    private func saveReadingProgress() {
        let book = preloadedData.book
        let chapter = preloadedData.chapter
        
        // Calculate total book duration from all chapters
        // For now, estimate based on current chapter duration * total chapters
        // In future, we could store actual durations per chapter
        let estimatedTotalDuration = audioPlayer.duration * Double(book.chapters.count)
        
        // Get existing progress or create new
        var progress = readingProgressService.getProgress(for: book.id) ?? ReadingProgress(
            bookId: book.id,
            bookTitle: book.title,
            bookAuthor: book.author,
            bookCoverUrl: book.coverUrl,
            currentChapterId: chapter.id,
            currentChapterNumber: chapter.order + 1,
            currentChapterTitle: chapter.title,
            currentTime: audioPlayer.currentTime,
            chapterDuration: audioPlayer.duration,
            totalBookDuration: estimatedTotalDuration,
            completedChapterIds: [],
            totalChapters: book.chapters.count
        )
        
        // Update position
        progress.updatePosition(
            chapterId: chapter.id,
            chapterNumber: chapter.order + 1,
            chapterTitle: chapter.title,
            time: audioPlayer.currentTime,
            duration: audioPlayer.duration
        )
        
        // Update total duration estimate if needed
        if progress.totalBookDuration == 0 {
            progress.totalBookDuration = estimatedTotalDuration
        }
        
        readingProgressService.saveProgress(progress)
    }
    
    // MARK: - Chapter Dropdown Menu
    private var chapterDropdownMenu: some View {
        let sortedChapters = preloadedData.book.chapters.sorted { $0.order < $1.order }
        
        return VStack(spacing: 0) {
            ForEach(Array(sortedChapters.enumerated()), id: \.element.id) { index, chapter in
                let isCurrentChapter = chapter.id == preloadedData.chapter.id
                
                Button(action: {
                    goToChapter(chapter.order)
                }) {
                    HStack {
                        Text(chapter.title)
                            .font(.system(size: 14, weight: isCurrentChapter ? .semibold : .regular))
                            .foregroundColor(isCurrentChapter ? readerColors.primaryText : readerColors.text)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        
                        Spacer()
                        
                        if isCurrentChapter {
                            Image(systemName: "checkmark")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(readerColors.primaryText)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(isCurrentChapter ? readerColors.primary : Color.clear)
                }
                .buttonStyle(PlainButtonStyle())
                
                if index < sortedChapters.count - 1 {
                    Divider()
                        .background(readerColors.cardBorder)
                }
            }
        }
        .background {
            if #available(iOS 26.0, *) {
                RoundedRectangle(cornerRadius: 12)
                    .fill(.ultraThinMaterial)
            } else {
                readerColors.card
            }
        }
        .cornerRadius(12)
        .overlay {
            if #available(iOS 26.0, *) {
                EmptyView()
            } else {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(readerColors.cardBorder, lineWidth: 1)
            }
        }
        .shadow(color: Color.black.opacity(0.3), radius: 12, x: 0, y: 6) // Darker shadow for better visibility
        .shadow(color: Color.black.opacity(0.2), radius: 4, x: 0, y: 2) // Additional shadow layer
        .frame(width: 280) // Fixed width for consistent appearance
        .onTapGesture {
            // Prevent tap from propagating to background (which would close dropdown)
            // This allows tapping inside dropdown without closing it
        }
    }
    
    // MARK: - Playback Controls
    private var playbackControls: some View {
        VStack(spacing: 0) {
            if isMenuExpanded {
                VStack(spacing: 16) {
                    // Collapse button at top center (no circle background, just arrow)
                    // Positioned evenly between top of menu and progress bar
                    HStack {
                        Spacer()
                        Button(action: {
                            hideHeaderAndMenu()
                        }) {
                            Image(systemName: "chevron.down")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(readerColors.text)
                        }
                        Spacer()
                    }
                    .padding(.bottom, 8) // Even spacing above and below (matches spacing: 16 in VStack)
                    .contentShape(Rectangle()) // Make entire area swipeable
                    .simultaneousGesture(
                        DragGesture(minimumDistance: 30)
                            .onEnded { value in
                                // Swipe down to collapse menu and header (only in chevron area)
                                if value.translation.height > 60 {
                                    hideHeaderAndMenu()
                                }
                            }
                    )
                    
                    // Progress Slider
                    VStack(spacing: 30) { // Increased spacing so time labels don't touch slider thumb
                        // Custom slider with darker unplayed portion on light modes
                        GeometryReader { geometry in
                            ZStack(alignment: .leading) {
                                // Unplayed portion background - darker on light modes
                                Rectangle()
                                    .fill(isLightBackground ? Color.black.opacity(0.5) : Color.white.opacity(0.2))
                                    .frame(height: 4)
                                    .cornerRadius(2)
                                
                                // Played portion
                                Rectangle()
                                    .fill(readerColors.primary)
                                    .frame(width: geometry.size.width * CGFloat(audioPlayer.currentTime / max(audioPlayer.duration, 1)), height: 4)
                                    .cornerRadius(2)
                                
                                // Slider control overlay (thumb will be visible)
                                Slider(
                                    value: Binding(
                                        get: { 
                                            // When scrubbing, use sliderValue to prevent fighting with audio player
                                            // When not scrubbing, use audioPlayer.currentTime to show actual progress
                                            isScrubbing ? sliderValue : audioPlayer.currentTime
                                        },
                                        set: { newTime in
                                            // DEFERRED UPDATES: Silently prepare state during scrubbing, update UI when scrubber lands
                                            // Note: The set closure is ONLY called when user manually drags the slider
                                            guard newTime.isFinite && newTime >= 0 else { return }
                                            let duration = audioPlayer.duration
                                            let clampedTime = min(max(0, newTime), max(duration, 0))
                                            
                                            // CRITICAL FIX: Defer ALL state modifications to avoid "modifying state during view update" warning
                                            Task { @MainActor in
                                                // If set is called, user is dragging (scrubbing)
                                                // Update slider value (prevents fighting with audio player during playback)
                                                sliderValue = clampedTime
                                                pendingSeekTime = clampedTime
                                                
                                                // DO NOT update karaokeEngine during scrubbing
                                                // Let CADisplayLink continue updating based on actual audio playback
                                                // Word highlighting will continue following playback, not scrubber position
                                                
                                                // Ensure scrubbing state is set (handles edge case where first drag happens before onEditingChanged)
                                                if !isScrubbing {
                                                    isScrubbing = true
                                                    // Keep CADisplayLink running so word highlighting continues following audio playback
                                                    // Only scrolling is paused, not word highlighting
                                                    hapticGenerator?.prepare()
                                                }
                                            }
                                        }
                                    ),
                                    in: 0...max(audioPlayer.duration, 1),
                                    onEditingChanged: { isEditing in
                                        Task { @MainActor in
                                            if isEditing {
                                                // User started scrubbing
                                                isScrubbing = true
                                                // Initialize slider value to current audio time (prevents jump when starting to scrub)
                                                sliderValue = audioPlayer.currentTime
                                                // Keep CADisplayLink running so word highlighting continues following audio
                                                // Scrolling will be paused, but word highlighting continues
                                                // Prepare haptic generator for smooth feedback
                                                hapticGenerator?.prepare()
                                            } else {
                                                // User finished scrubbing - perform expensive operations now
                                                // Note: karaokeEngine state is already prepared from silent updates during scrubbing
                                                isScrubbing = false
                                                
                                                // Apply all deferred updates using the stored target time (or current time as fallback)
                                                let targetTime = pendingSeekTime ?? audioPlayer.currentTime
                                                let duration = audioPlayer.duration
                                                
                                                // CRITICAL FIX: Wait for seek to complete and use ACTUAL audio time
                                                // This ensures word highlighting matches where audio actually lands
                                                Task { @MainActor in
                                                    // Seek audio to final position and wait for completion
                                                    let actualTime = await audioPlayer.seekAndWait(to: targetTime)
                                                    
                                                // Reset search state before applying the new time for accuracy
                                                karaokeEngine.resetSearchState()
                                                    
                                                    // Always find the last word that ends at or before actualTime
                                                    let indexedWords = karaokeEngine.getIndexedWords()
                                                    var lastSpokenWordIndex: Int? = nil
                                                    var lastSpokenWordEndTime: Double = 0
                                                    
                                                    for word in indexedWords.reversed() {
                                                        if word.end <= actualTime && word.end.isFinite && word.start.isFinite {
                                                            lastSpokenWordIndex = word.id
                                                            lastSpokenWordEndTime = word.end
                                                            break
                                                        }
                                                    }
                                                    
                                                    if let lastSpoken = lastSpokenWordIndex {
                                                        karaokeEngine.updateTime(lastSpokenWordEndTime, duration: duration)
                                                    }
                                                    
                                                    // Apply the actual landed time
                                                    karaokeEngine.updateTime(actualTime, duration: duration)
                                                    
                                                    // Haptic for current word if changed
                                                    if let currentWord = karaokeEngine.currentWordIndex,
                                                       currentWord != lastHapticWordIndex {
                                                        hapticGenerator?.impactOccurred(intensity: 0.7)
                                                        lastHapticWordIndex = currentWord
                                                    }
                                                    
                                                    // Clear pending seek time
                                                    pendingSeekTime = nil
                                                    
                                                    // Sync slider value to actual audio time after seek completes
                                                    sliderValue = actualTime
                                                    
                                                    // Instant jump to the scrubbed position (no animation - user expects immediate response)
                                                    jumpToSyncPosition(time: actualTime, animated: false)
                                                    
                                                    // CADisplayLink was never paused, so no need to resume
                                                    // Everything is now synchronized to the new position
                                                }
                                            }
                                        }
                                    }
                                )
                                .tint(readerColors.primary) // Thumb color
                                .background(Color.clear) // Transparent background so custom track shows
                                
                                // Bookmark tick marks (chapter-only)
                                ForEach(Array(chapterBookmarkTimesSorted.enumerated()), id: \.offset) { _, t in
                                    let duration = max(audioPlayer.duration, 1)
                                    let clamped = min(max(t, 0), duration)
                                    let x = geometry.size.width * CGFloat(clamped / duration)
                                    
                                    Rectangle()
                                        .fill(bookmarkMarkerColor.opacity(0.95))
                                        .frame(width: 2, height: 12)
                                        .cornerRadius(1)
                                        .offset(x: x - 1)
                                        .allowsHitTesting(false)
                                }
                            }
                        }
                        .frame(height: 4)
                        
                        HStack {
                            Text(formatTime(audioPlayer.currentTime))
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundColor(readerColors.textSecondary)
                            
                            Spacer()
                            
                            Text(formatTime(audioPlayer.duration))
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundColor(readerColors.textSecondary)
                        }
                    }
                    
                    // Control Buttons
                    HStack(spacing: 32) {
                        // Rewind 10s
                        Button(action: {
                            handleUserInteraction()
                            
                            let currentTime = audioPlayer.getCurrentTime()
                            guard currentTime.isFinite && currentTime >= 0 else { return }
                            
                            let newTime = max(0, currentTime - 10)
                            audioPlayer.seek(to: newTime)
                            // Reset word sync and trigger update after seek
                            Task { @MainActor in
                                karaokeEngine.resetSearchState()
                                let updatedTime = audioPlayer.getCurrentTime()
                                karaokeEngine.updateTime(updatedTime, duration: audioPlayer.duration)
                                
                                // Scroll to bring the new position into view
                                jumpToSyncPosition(time: updatedTime)
                            }
                        }) {
                            Image(systemName: "gobackward.10")
                                .font(.system(size: 24))
                                .foregroundColor(readerColors.text)
                        }
                        
                        // Play/Pause
                        Button(action: {
                            handleUserInteraction()
                            
                            audioPlayer.togglePlayPause()
                            
                            // IMPORTANT: Keep UI responsive on tap.
                            // The previous implementation scanned ~10k words on the main thread, which can
                            // stall input long enough to trigger "System gesture gate timed out".
                            // KaraokeEngine already tracks last-spoken incrementally; a single update is enough.
                            Task { @MainActor in
                                let t = audioPlayer.getCurrentTime()
                                karaokeEngine.resetSearchState()
                                karaokeEngine.updateTime(t, duration: audioPlayer.duration)
                                
                                if let sentenceIndex = findSentenceAtTime(t) {
                                    currentSentenceIndex = sentenceIndex
                                }
                                
                                scrollMode = audioPlayer.isPlaying ? .playing : .paused
                            }
                        }) {
                            Image(systemName: audioPlayer.isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 28, weight: .semibold))
                                .foregroundColor(readerColors.text)
                                .frame(width: 64, height: 64)
                        }
                        
                        // Forward 10s
                        Button(action: {
                            handleUserInteraction()
                            
                            let currentTime = audioPlayer.getCurrentTime()
                            guard currentTime.isFinite && currentTime >= 0 else { return }
                            
                            let newTime = min(audioPlayer.duration, currentTime + 10)
                            audioPlayer.seek(to: newTime)
                            // Reset word sync and trigger update after seek
                            Task { @MainActor in
                                karaokeEngine.resetSearchState()
                                let updatedTime = audioPlayer.getCurrentTime()
                                karaokeEngine.updateTime(updatedTime, duration: audioPlayer.duration)
                                
                                // Scroll to bring the new position into view
                                jumpToSyncPosition(time: updatedTime)
                            }
                        }) {
                            Image(systemName: "goforward.10")
                                .font(.system(size: 24))
                                .foregroundColor(readerColors.text)
                        }
                    }
                    
                // Settings Button Row or Submenu
                if let activeSubmenu = activeSubmenu {
                    // Show submenu
                    submenuView(for: activeSubmenu)
                } else {
                    // Show main settings buttons
                    settingsButtonRow
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 8)
        } else {
            // Collapsed state - show minimal indicator (no circle background, just arrow)
            // Positioned at bottom of screen
            HStack {
                Spacer()
                Button(action: {
                    showHeader()
                }) {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(readerColors.text)
                }
                Spacer()
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle()) // Make entire collapsed area swipeable
            .simultaneousGesture(
                DragGesture(minimumDistance: 30)
                    .onEnded { value in
                        // Swipe up to expand menu and header
                        if value.translation.height < -60 {
                            showHeader()
                        }
                    }
            )
        }
        }
        .padding(.bottom, getSafeAreaBottom()) // Add home indicator safe area padding
        .background {
            if #available(iOS 26.0, *) {
                LinearGradient(
                    gradient: Gradient(stops: [
                        .init(color: readerColors.background.opacity(0.15), location: 0),
                        .init(color: readerColors.background.opacity(0.75), location: 0.05),
                        .init(color: readerColors.background.opacity(0.85), location: 0.2),
                        .init(color: readerColors.background.opacity(0.9), location: 0.3),
                        .init(color: readerColors.background.opacity(1), location: 1)
                    ]),
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea(edges: .bottom) // Extend background to bottom of screen
            } else {
                readerColors.card
                    .ignoresSafeArea(edges: .bottom) // Extend background to bottom of screen
            }
        }
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(readerColors.cardBorder),
            alignment: .top
        )
        .overlay(alignment: .top) {
            if isOutOfSync {
                backToSyncButton
                    .offset(y: isSearchActive ? -80 : -50) // Move higher when search is active to avoid search bar
                    .transition(.opacity)
                    .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isOutOfSync)
            }
            GeometryReader { geo in
                Color.clear
                    .preference(
                        key: PlaybackControlsHeightPreferenceKey.self,
                        value: geo.size.height
                    )
            }
            .frame(height: 0)
        }
    }
    
    // MARK: - Back to Sync Button
    private var backToSyncButton: some View {
        Button(action: {
            resyncToCurrentSentence()
        }) {
            HStack(spacing: 8) {
                Image(systemName: "waveform")
                    .font(.system(size: 14, weight: .semibold))
                Text("Back to Sync")
                    .font(.system(size: 14, weight: .semibold))
            }
            .foregroundColor(readerColors.primaryText)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(readerColors.primary)
            .clipShape(Capsule())
            .shadow(color: Color.black.opacity(0.25), radius: 8, x: 0, y: 4)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    // MARK: - Bookmarking
    private var currentBookmarkId: String {
        Bookmark.makeId(
            bookId: preloadedData.book.id,
            chapterId: preloadedData.chapter.id,
            sentenceIndex: currentSentenceIndex
        )
    }
    
    private var isCurrentSentenceBookmarked: Bool {
        chapterBookmarksBySentenceIndex[currentSentenceIndex] != nil
    }
    
    private var currentBookmarkChapterNumber: Int? {
        preloadedData.chapter.order >= 0 ? (preloadedData.chapter.order + 1) : nil
    }
    
    private var isCurrentBookmarkDescription: Bool {
        preloadedData.chapter.order < 0
    }

    private var chapterBookmarkTimesSorted: [Double] {
        chapterBookmarksBySentenceIndex.values.sorted()
    }
    
    private func currentSentenceForBookmark() -> PrecomputedSentence? {
        guard currentSentenceIndex >= 0, currentSentenceIndex < preloadedData.sentences.count else { return nil }
        return preloadedData.sentences[currentSentenceIndex]
    }
    
    private var bookmarkCircleButton: some View {
        Group {
            Image(systemName: isCurrentSentenceBookmarked ? "bookmark.fill" : "bookmark")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(isCurrentSentenceBookmarked ? readerColors.primary : readerColors.text)
                .frame(width: 44, height: 44)
        }
        .onTapGesture {
            Task { @MainActor in
                await toggleBookmarkForCurrentSentence()
            }
        }
        .onLongPressGesture(minimumDuration: 0.35) {
            Task { @MainActor in
                await openBookmarkEditorForCurrentSentence()
            }
        }
    }
    
    // MARK: - Search Bar View
    private var searchBarView: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                // Search text field
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 16))
                        .foregroundColor(readerColors.textSecondary)
                    
                    TextField("Search in chapter...", text: $searchQuery)
                        .font(.system(size: 16))
                        .foregroundColor(readerColors.text)
                        .focused($isSearchFieldFocused)
                        .keyboardType(.asciiCapable)           // Removes emoji button
                        .autocorrectionDisabled()              // Removes predictive text
                        .textInputAutocapitalization(.never)   // Prevents auto-capitalization
                        .disableAutocorrection(true)           // Additional autocorrection disable
                        .submitLabel(.search)
                        .onAppear {
                            // Disable dictation by setting keyboard appearance
                            UITextField.appearance().keyboardAppearance = .default
                        }
                        .onSubmit {
                            performSearch()
                        }
                        .onChange(of: searchQuery) { _, newValue in
                            if newValue.isEmpty {
                                searchMatches = []
                                currentSearchMatchIndex = 0
                            } else {
                                performSearch()
                            }
                        }
                    
                    if !searchQuery.isEmpty {
                        Button(action: {
                            searchQuery = ""
                            searchMatches = []
                            currentSearchMatchIndex = 0
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 16))
                                .foregroundColor(readerColors.textSecondary)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(readerColors.card)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                
                // Match counter and navigation
                if !searchMatches.isEmpty {
                    HStack(spacing: 8) {
                        Text("\(currentSearchMatchIndex + 1)/\(searchMatches.count)")
                            .font(.system(size: 14, weight: .medium, design: .monospaced))
                            .foregroundColor(readerColors.text)
                            .frame(minWidth: 50)
                        
                        // Previous match button
                        Button(action: previousSearchMatch) {
                            Image(systemName: "chevron.up")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(readerColors.text)
                                .frame(width: 32, height: 32)
                                .background(readerColors.card)
                                .clipShape(Circle())
                        }
                        
                        // Next match button
                        Button(action: nextSearchMatch) {
                            Image(systemName: "chevron.down")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(readerColors.text)
                                .frame(width: 32, height: 32)
                                .background(readerColors.card)
                                .clipShape(Circle())
                        }
                    }
                }
                
                // Close button
                Button(action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        closeSearch()
                    }
                }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(readerColors.text)
                        .frame(width: 36, height: 36)
                        .background(readerColors.card)
                        .clipShape(Circle())
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(readerColors.background.opacity(0.95))
            .overlay(
                Rectangle()
                    .frame(height: 1)
                    .foregroundColor(readerColors.cardBorder),
                alignment: .top
            )
            }
    }
    
    // MARK: - Search Results Overlay
    private var searchResultsOverlay: some View {
        VStack(spacing: 0) {
            // Header spacing
            Spacer()
                .frame(height: headerHeight + 20)
            
            // Results list in the center area
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(Array(searchMatches.enumerated()), id: \.element.id) { index, match in
                        Button(action: {
                            scrollToSearchMatch(at: index)
                            // Dismiss keyboard after selection
                            isSearchFieldFocused = false
                        }) {
                            HStack(alignment: .top, spacing: 12) {
                                // Result number
                                Text("\(index + 1)")
                                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                    .foregroundColor(readerColors.textSecondary)
                                    .frame(width: 24)
                                
                                // Sentence text with highlighted match
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(getHighlightedMatchText(for: match))
                                        .font(.system(size: 14))
                                        .foregroundColor(readerColors.text)
                                        .lineLimit(3)
                                        .multilineTextAlignment(.leading)
                                }
                                
                                Spacer()
                                
                                // Chevron indicator
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(readerColors.textSecondary)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(index == currentSearchMatchIndex 
                                        ? readerColors.primary.opacity(0.15) 
                                        : readerColors.card.opacity(0.8))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .strokeBorder(
                                        index == currentSearchMatchIndex 
                                            ? readerColors.primary.opacity(0.5)
                                            : readerColors.cardBorder.opacity(0.5),
                                        lineWidth: 1
                                    )
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }
            .frame(maxHeight: 300) // Limit height of results list
            
            Spacer()
        }
    }
    
    // Helper to get highlighted text for a search match
    private func getHighlightedMatchText(for match: SearchMatch) -> AttributedString {
        guard match.sentenceIndex >= 0, match.sentenceIndex < preloadedData.sentences.count else {
            return AttributedString(match.matchText)
        }
        
        let sentence = preloadedData.sentences[match.sentenceIndex]
        var attributedString = AttributedString(sentence.text)
        
        // Find the range in the attributed string and highlight it
        if let range = attributedString.range(of: match.matchText, options: .caseInsensitive) {
            attributedString[range].foregroundColor = readerColors.primary
            attributedString[range].font = .system(size: 14, weight: .semibold)
        }
        
        return attributedString
    }
    
    @MainActor
    private func toggleBookmarkForCurrentSentence() async {
        guard bookmarkService.uid != nil else { return }
        guard !isBookmarkToggleInFlight else { return }
        
        let sentenceIndex = currentSentenceIndex
        guard sentenceIndex >= 0, sentenceIndex < preloadedData.sentences.count else { return }
        let sentence = preloadedData.sentences[sentenceIndex]
        
        isBookmarkToggleInFlight = true
        defer { isBookmarkToggleInFlight = false }
        
        do {
            let didSave = try await bookmarkService.toggleBookmark(
                bookId: preloadedData.book.id,
                chapterId: preloadedData.chapter.id,
                chapterNumber: currentBookmarkChapterNumber,
                isDescription: isCurrentBookmarkDescription,
                sentenceIndex: sentenceIndex,
                startTime: sentence.startTime,
                text: sentence.text
            )

            if didSave {
                chapterBookmarksBySentenceIndex[sentenceIndex] = sentence.startTime
            } else {
                chapterBookmarksBySentenceIndex.removeValue(forKey: sentenceIndex)
            }
            
            triggerBookmarkHaptic()
            presentBookmarkToast(saved: didSave, startTime: sentence.startTime)
        } catch {
            bookmarkService.lastErrorMessage = "Bookmark failed: \(error.localizedDescription)"
        }
    }

    @MainActor
    private func triggerBookmarkHaptic() {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.prepare()
        generator.impactOccurred()
    }
    
    @MainActor
    private func presentBookmarkToast(saved: Bool, startTime: Double) {
        bookmarkToastTask?.cancel()
        
        withAnimation(.easeInOut(duration: 0.18)) {
            bookmarkToast = BookmarkToast(
                kind: saved ? .saved : .removed,
                timeText: PlaybackTimeFormatter.string(from: startTime)
            )
        }
        
        bookmarkToastTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            withAnimation(.easeInOut(duration: 0.18)) {
                bookmarkToast = nil
            }
        }
    }

    @MainActor
    private func rebuildChapterBookmarkCache() {
        var map: [Int: Double] = [:]
        for b in bookmarkService.bookmarks {
            guard b.bookId == preloadedData.book.id else { continue }
            guard b.chapterId == preloadedData.chapter.id else { continue }
            guard b.isDescription == isCurrentBookmarkDescription else { continue }
            map[b.sentenceIndex] = b.startTime
        }
        chapterBookmarksBySentenceIndex = map
    }
    
    @MainActor
    private func openBookmarkEditorForCurrentSentence() async {
        guard bookmarkService.uid != nil else { return }
        
        let sentenceIndex = currentSentenceIndex
        guard sentenceIndex >= 0, sentenceIndex < preloadedData.sentences.count else { return }
        let sentence = preloadedData.sentences[sentenceIndex]
        
        do {
            let bookmark = try await bookmarkService.ensureBookmark(
                bookId: preloadedData.book.id,
                chapterId: preloadedData.chapter.id,
                chapterNumber: currentBookmarkChapterNumber,
                isDescription: isCurrentBookmarkDescription,
                sentenceIndex: sentenceIndex,
                startTime: sentence.startTime,
                text: sentence.text
            )
            chapterBookmarksBySentenceIndex[sentenceIndex] = bookmark.startTime
            bookmarkEditorId = bookmark.id
            isBookmarkEditorPresented = true
        } catch {
            bookmarkService.lastErrorMessage = "Bookmark failed: \(error.localizedDescription)"
        }
    }
    
    // MARK: - Settings Button Row
    private var settingsButtonRow: some View {
        HStack(spacing: 12) {
            // Bookmark (tap toggle, long-press organize)
            bookmarkCircleButton
            
            // Search button
            Button(action: {
                handleUserInteraction()
                
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    isSearchActive.toggle()
                    if isSearchActive {
                        // Collapse menu when opening search
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            isMenuExpanded = false
                        }
                        // Focus search field when opening
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            isSearchFieldFocused = true
                        }
                    } else {
                        closeSearch()
                    }
                }
            }) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(readerColors.text)
                    .frame(width: 44, height: 44)
            }
            
            // Playback Speed button
            Button(action: {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    activeSubmenu = .speed
                }
            }) {
                Image(systemName: "speedometer")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(readerColors.text)
                    .frame(width: 44, height: 44)
            }
            
            // Text Size button
            Button(action: {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    activeSubmenu = .textSize
                }
            }) {
                Image(systemName: "textformat.size")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(readerColors.text)
                    .frame(width: 44, height: 44)
            }
            
            // Highlight Color button
            Button(action: {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    activeSubmenu = .highlight
                }
            }) {
                Image(systemName: "paintbrush.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(highlightColor == .none ? readerColors.text : highlightColor.color)
                    .frame(width: 44, height: 44)
            }
            
            // Background Color button
            Button(action: {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    activeSubmenu = .background
                }
            }) {
                Image(systemName: "paintpalette.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(readerColors.text)
                    .frame(width: 44, height: 44)
                    .overlay(alignment: .topTrailing) {
                        Circle()
                            .fill(readerBackgroundColor.color)
                            .frame(width: 10, height: 10)
                            .padding(2)
                    }
            }
        }
    }
    
    // MARK: - Submenu View
    private func submenuView(for submenu: SubmenuType) -> some View {
        HStack(spacing: 12) {
            // Back button
            Button(action: {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    activeSubmenu = nil
                }
            }) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(readerColors.text)
                    .frame(width: 44, height: 44)
            }
            
            // Submenu options
            switch submenu {
            case .speed:
                speedSubmenuView
            case .textSize:
                textSizeSubmenuView
            case .highlight:
                highlightSubmenuView
            case .background:
                backgroundSubmenuView
            }
        }
    }
    
    // MARK: - Speed Submenu
    private var speedSubmenuView: some View {
        HStack(spacing: 12) {
            ForEach([0.75, 1.0, 1.25, 1.5, 2.0], id: \.self) { speed in
                Button(action: {
                    playbackSpeed = speed
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        activeSubmenu = nil
                    }
                }) {
                    Text(String(format: "%.2fx", speed))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(playbackSpeed == speed ? readerColors.primary : readerColors.text)
                        .frame(width: 44, height: 44)
                }
            }
        }
    }
    
    // MARK: - Text Size Submenu
    private var textSizeSubmenuView: some View {
        HStack(spacing: 12) {
            ForEach(TextSize.allCases, id: \.self) { size in
                Button(action: {
                    textSize = size
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        activeSubmenu = nil
                    }
                }) {
                    Text(size.rawValue)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(textSize == size ? readerColors.primary : readerColors.text)
                        .frame(width: 44, height: 44)
                }
            }
        }
    }
    
    // MARK: - Highlight Color Submenu
    private var highlightSubmenuView: some View {
        HStack(spacing: 12) {
            ForEach(HighlightColor.allCases, id: \.self) { color in
                Button(action: {
                    highlightColor = color
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        activeSubmenu = nil
                    }
                }) {
                    Group {
                        if color == .none {
                            Image(systemName: "xmark")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(highlightColor == color ? readerColors.primary : readerColors.text)
                        } else {
                            Circle()
                                .fill(color.color)
                                .frame(width: 24, height: 24)
                        }
                    }
                    .frame(width: 44, height: 44)
                }
            }
        }
    }
    
    // MARK: - Background Color Submenu
    private var backgroundSubmenuView: some View {
        HStack(spacing: 12) {
            ForEach(ReaderBackgroundColor.allCases, id: \.self) { color in
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.4)) {
                        readerBackgroundColor = color
                    }
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        activeSubmenu = nil
                    }
                }) {
                    Circle()
                        .fill(color.color)
                        .frame(width: 28, height: 28)
                        .overlay {
                            if readerBackgroundColor == color {
                                Circle()
                                    .stroke(readerColors.primary, lineWidth: 2)
                            }
                        }
                        .frame(width: 44, height: 44)
                }
            }
        }
    }
    
    // MARK: - Audio Setup on Appear
    /// Called from onAppear to either skip loading (if already playing) or load fresh audio
    private func setupAudioOnAppear() {
        // Check if audio is already playing for this book/chapter
        let isAlreadyPlaying = audioPlayer.hasActiveSession &&
                               audioPlayer.bookId == preloadedData.book.id &&
                               audioPlayer.chapterNumber == (preloadedData.chapter.order + 1)
        
        if isAlreadyPlaying {
            print("⚡ OptimizedReaderView: Audio already loaded - skipping audio reload")
            print("   Current time: \(audioPlayer.currentTime)s, Playing: \(audioPlayer.isPlaying)")
            
            // Sync karaoke engine to current playback position
            karaokeEngine.updateTime(audioPlayer.currentTime, duration: audioPlayer.duration)
            
            // Update current sentence index immediately (before ScrollView appears)
            if let wordIndex = karaokeEngine.currentWordIndex,
               let sentenceIndex = wordToSentenceMap[wordIndex] {
                currentSentenceIndex = sentenceIndex
                print("⚡ Set currentSentenceIndex to \(sentenceIndex) for word \(wordIndex)")
            }
            
            // Set flag to scroll once ScrollView is ready
            shouldScrollToCurrentOnAppear = true
        } else {
            // Load audio fresh
            loadAudioFresh()
            
            // Also set flag to scroll to initial position after load completes
            // This handles fresh loads with initialSeekTime or saved progress
            shouldScrollToCurrentOnAppear = true
        }
    }
    
    /// Load audio from scratch (not already playing)
    private func loadAudioFresh() {
        Task {
            if let preloadedAsset = preloadedData.audioAsset {
                await audioPlayer.load(
                    asset: preloadedAsset,
                    preloadedDuration: preloadedData.audioDuration,
                    chapterTitle: preloadedData.chapter.title,
                    bookTitle: preloadedData.book.title,
                    coverURL: preloadedData.book.coverUrl.flatMap { URL(string: $0) },
                    bookId: preloadedData.book.id,
                    chapterNumber: preloadedData.chapter.order + 1
                )
            } else {
                await audioPlayer.load(
                    url: preloadedData.audioURL,
                    preloadedDuration: preloadedData.audioDuration,
                    chapterTitle: preloadedData.chapter.title,
                    bookTitle: preloadedData.book.title,
                    coverURL: preloadedData.book.coverUrl.flatMap { URL(string: $0) },
                    bookId: preloadedData.book.id,
                    chapterNumber: preloadedData.chapter.order + 1
                )
            }
            
            // Store preloaded data for instant re-entry
            audioPlayer.setPreloadedData(preloadedData)
            
            await MainActor.run {
                // Ensure audio doesn't auto-play - explicitly pause FIRST
                audioPlayer.pause()
                // Then apply saved playback speed
                audioPlayer.setPlaybackSpeed(playbackSpeed)
                
                // If opened from a bookmark, seek + scroll to the saved position
                applyInitialSeekIfNeeded()
            }
        }
    }
    
    // MARK: - Initial Seek (e.g., opening from a bookmark)
    @MainActor
    private func applyInitialSeekIfNeeded() {
        guard !didApplyInitialSeek else { return }
        guard let t = initialSeekTime, t.isFinite, t >= 0 else { return }
        
        didApplyInitialSeek = true
        
        // Seek audio
        audioPlayer.seek(to: t)
        
        // Sync highlighting + sentence index
        karaokeEngine.resetSearchState()
        karaokeEngine.updateTime(t, duration: audioPlayer.duration)
        
        if let sentenceIndex = findSentenceAtTime(t) {
            currentSentenceIndex = sentenceIndex
            pendingCenterSentenceIndex = sentenceIndex
            isOutOfSync = false
            
            // Scroll to the sentence after a brief delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                if let proxy = scrollProxy {
                    proxy.scrollTo(sentenceScrollID(sentenceIndex), anchor: .center)
                    print("⚡ applyInitialSeekIfNeeded: Scrolled to sentence \(sentenceIndex) for time \(t)")
                }
            }
        }
        
        scrollMode = .paused
    }
    
    // MARK: - Sentence-Based Scrolling (for scrubbing)
    
    /// Find which sentence contains the given time using binary search for efficiency
    /// Returns sentence index if found, nil otherwise
    private func findSentenceAtTime(_ time: Double) -> Int? {
        // Binary search since sentences are sorted by time
        var left = 0
        var right = preloadedData.sentences.count - 1
        
        while left <= right {
            let mid = (left + right) / 2
            let sentence = preloadedData.sentences[mid]
            
            if time >= sentence.startTime && time <= sentence.endTime {
                return mid
            } else if time < sentence.startTime {
                right = mid - 1
            } else {
                left = mid + 1
            }
        }
        
        // Fallback: if binary search fails, try linear search (handles edge cases)
        for (index, sentence) in preloadedData.sentences.enumerated() {
            if time >= sentence.startTime && time <= sentence.endTime {
                return index
            }
        }
        
        // If time is before first sentence, return first sentence
        if time < preloadedData.sentences.first?.startTime ?? 0 {
            return 0
        }
        
        // If time is after last sentence, return last sentence
        if let lastSentence = preloadedData.sentences.last, time > lastSentence.endTime {
            return preloadedData.sentences.count - 1
        }
        
        return nil
    }
    
    // MARK: - Autoscroll Viewport Band
    
    // Keep these in sync with the LazyVStack padding below.
    private var scrollContentHorizontalPadding: CGFloat { 20 }
    private var scrollContentVerticalPadding: CGFloat { 48 }
    
    /// The visible reading band inside the ScrollView.
    /// NOTE: scrollViewHeight is already the constrained height (excludes header and menu)
    /// thanks to ReadingContainerView. We only subtract the content padding.
    private var fieldOfViewTopY: CGFloat { scrollContentVerticalPadding }
    private var fieldOfViewBottomY: CGFloat {
        max(scrollViewHeight - scrollContentVerticalPadding, fieldOfViewTopY + 1)
    }
    private var fieldOfViewHeight: CGFloat { fieldOfViewBottomY - fieldOfViewTopY }
    
    // Destination for long-sentence jumps: place current word near the top band,
    // revealing the remaining content below.
    private var markerTopSafeAnchor: UnitPoint {
        let h = max(scrollViewHeight, 1)
        // Include iOS status bar height to prevent text from going behind it
        let statusBarHeight = getSafeAreaTop()
        // Add extra padding (24pt) beyond fieldOfViewTopY to keep long sentences away from status bar
        let topMargin = fieldOfViewTopY + statusBarHeight + 24 + (textSize.lineHeight * 0.5)
        let y = min(max(topMargin / h, 0), 1)
        return UnitPoint(x: 0.5, y: y)
    }

    // Destination for Back-to-Sync (and scrub-end) on long sentences: place current word near the center
    // of the visible reading band for a smoother "return to reading" experience.
    private var markerResyncAnchor: UnitPoint {
        let h = max(scrollViewHeight, 1)
        let targetY = fieldOfViewTopY + (fieldOfViewHeight * 0.5)
        let y = min(max(targetY / h, 0), 1)
        return UnitPoint(x: 0.5, y: y)
    }

    private var sentenceTextLayoutWidth: CGFloat {
        max(scrollViewWidth - (scrollContentHorizontalPadding * 2), 1)
    }
    
    // Normalized trigger: when the current word reaches 85% of the band height, jump it back near the top.
    private var markerTriggerPercent: CGFloat { 0.85 }
    
    // SINGLE-SOURCE: sentence long/short is determined only from currentSentenceFrame.height vs fieldOfViewHeight.
    
    // MARK: - Smart Positioning System
    
    // Calculate optimal anchor point for sentence based on height and viewport
    // Menu-aware: accounts for header and playback controls height
    private func calculateSentenceAnchor(sentenceHeight: CGFloat, viewportHeight: CGFloat, progress: Double = 0.0) -> UnitPoint {
        if sentenceHeight <= viewportHeight {
            // Short sentence - center it in available viewport
            return .center
        } else {
            // Long sentence - position to show content without going past header
            // Use progress for long sentences to show current reading position
            let targetY = progress > 0 ? progress : 0.2  // Default to 20% from top for new sentences
            return UnitPoint(x: 0.5, y: min(targetY, 0.8))  // Never go below 80% to avoid footer overlap
        }
    }
    
    // Get current available viewport height accounting for UI elements
    private func getAvailableViewportHeight() -> CGFloat {
        return max(scrollViewHeight - headerHeight - playbackControlsHeight - (safeMargin * 2), 100)
    }
    

    
    
    // Estimate progress within the current sentence using word index
    private func currentSentenceProgress() -> Double {
        guard let wordIndex = karaokeEngine.currentWordIndex,
              currentSentenceIndex >= 0,
              currentSentenceIndex < preloadedData.sentences.count else { return 0 }
        
        let sentence = preloadedData.sentences[currentSentenceIndex]
        let words = sentence.globalWordIndices
        guard let position = words.firstIndex(of: wordIndex), !words.isEmpty else { return 0 }
        return Double(position + 1) / Double(words.count)
    }
    
    // MARK: - Scroll IDs + Jump Helpers
    
    private func sentenceScrollID(_ sentenceIndex: Int) -> String {
        "\(sentenceIndex)-\(readerBackgroundColor.rawValue)"
    }
    
    private func sentenceLineMarkerScrollID(_ sentenceIndex: Int) -> String {
        "\(sentenceIndex)-lineMarker-\(readerBackgroundColor.rawValue)"
    }
    
    private func scrollWithoutAnimation(_ action: () -> Void) {
        var transaction = Transaction()
        transaction.animation = nil
        withTransaction(transaction) {
            action()
        }
    }
    
    private func scrollWithAnimation(_ action: () -> Void) {
        withAnimation(.easeInOut(duration: 0.25)) {
            action()
        }
    }
    
    /// Smooth jump used by seek buttons (rewind/forward) and Back-to-Sync.
    /// - Short sentences (fit in band): center in the field-of-view.
    /// - Long sentences (taller than band): scroll directly to the word position in one smooth motion.
    /// - Parameter animated: If true, uses smooth animation. If false (e.g., scrub-end), instant jump.
    private func jumpToSyncPosition(time: Double, proxy overrideProxy: ScrollViewProxy? = nil, animated: Bool = true) {
        guard let proxy = overrideProxy ?? scrollProxy else { return }
        let t = time.isFinite && time >= 0 ? time : 0
        guard let sentenceIndex = findSentenceAtTime(t) else { return }

        // Capture a best-effort current word for this time.
        let candidateWordIndex = karaokeEngine.getWordAtTime(t) ?? karaokeEngine.currentWordIndex
        let targetWordIndex: Int? = {
            guard let w = candidateWordIndex else { return nil }
            if let mappedSentence = wordToSentenceMap[w], mappedSentence == sentenceIndex {
                return w
            }
            let sentence = preloadedData.sentences[sentenceIndex]
            return sentence.globalWordIndices.contains(w) ? w : nil
        }()
        
        cachedLineLayoutSentenceId = nil
        cachedLineLayoutRectsByWordIndex = [:]
        
        currentSentenceIndex = sentenceIndex
        isOutOfSync = false
        
        let sentenceID = sentenceScrollID(sentenceIndex)
        let sentence = preloadedData.sentences[sentenceIndex]
        
        // For short sentences or if we don't have a valid word, just center/top the sentence.
        // For long sentences with a valid word, scroll directly to the word position.
        let doScroll = animated ? scrollWithAnimation : scrollWithoutAnimation
        
        // Check if this will be a long sentence (use precomputed height if available, else estimate)
        // We need to decide upfront whether to use marker-based scroll or sentence-based scroll.
        if let wordIdx = targetWordIndex,
           let localPosition = sentence.globalWordIndices.firstIndex(of: wordIdx),
           !sentence.globalWordIndices.isEmpty {
            
            // Estimate word progress
            let wordProgress = CGFloat(localPosition + 1) / CGFloat(sentence.globalWordIndices.count)
            
            // If word is past ~30% of sentence, it's likely a long sentence and we should scroll to word.
            // Otherwise, scrolling to sentence top/center is fine.
            if wordProgress > 0.3 {
                // Long sentence path: set marker position and scroll to it in one motion.
                // We estimate the Y position based on current frame height (or a reasonable default).
                let estimatedSentenceHeight = currentSentenceFrame.height > 0 ? currentSentenceFrame.height : fieldOfViewHeight * 2
                let estimatedWordYInSentence = wordProgress * estimatedSentenceHeight
                lineScrollMarkerOffsetY = estimatedWordYInSentence
                
                // Calculate remaining content height (from current word to end of sentence)
                let remainingHeight = estimatedSentenceHeight - estimatedWordYInSentence
                
                // If remaining content fits in the band, center it instead of using resync anchor.
                // This creates a smoother transition as the sentence nears its end.
                let anchor: UnitPoint = remainingHeight <= fieldOfViewHeight ? .center : markerResyncAnchor
                
                let markerID = sentenceLineMarkerScrollID(sentenceIndex)
                doScroll {
                    proxy.scrollTo(markerID, anchor: anchor)
                }
                
                // Set cooldown to prevent auto-scroll from immediately re-triggering.
                lastManualScrollTime = CACurrentMediaTime()
                
                // Clear pending flags - we handled it directly.
                pendingCenterSentenceIndex = nil
                pendingResyncWordIndex = nil
                return
            }
        }
        
        // Short sentence or word near beginning: use the normal pending-center flow.
        lineScrollMarkerOffsetY = 0
        pendingCenterSentenceIndex = sentenceIndex
        pendingResyncWordIndex = targetWordIndex
        
        // Set cooldown to prevent auto-scroll from immediately re-triggering.
        lastManualScrollTime = CACurrentMediaTime()
        
        doScroll {
            proxy.scrollTo(sentenceID, anchor: .top)
        }
    }
    
    // MARK: - Playback Auto-Scroll
    
    private var isPlaybackAutoScrollEnabled: Bool {
        audioPlayer.isPlaying && !isOutOfSync && !isScrubbing && !isUserDraggingScroll
    }
    
    private func autoScrollOnSentenceAdvance(to sentenceIndex: Int, proxy: ScrollViewProxy) {
        lastAutoScrolledWordIndex = nil
        lineScrollMarkerOffsetY = 0
        cachedLineLayoutSentenceId = nil
        cachedLineLayoutRectsByWordIndex = [:]
        
        let sentenceID = sentenceScrollID(sentenceIndex)
        pendingCenterSentenceIndex = sentenceIndex
        
        // Smooth animation for sentence transitions during playback.
        scrollWithAnimation {
            proxy.scrollTo(sentenceID, anchor: .top)
        }
    }
    
    private func autoScrollLongSentenceIfNeeded(wordIndex: Int, proxy: ScrollViewProxy) {
        // SINGLE-SOURCE: long sentence is defined only by measured frame height in scroll space.
        guard currentSentenceFrame.height > fieldOfViewHeight else { return }
        if lastAutoScrolledWordIndex == wordIndex { return }
        
        // Throttle to avoid scroll spam.
        let now = CACurrentMediaTime()
        let minInterval: CFTimeInterval = 1.0 / 15.0
        guard (now - lastAutoScrollTime) >= minInterval else { return }
        
        // Skip if we just did a manual scroll (rewind/forward/tap/back-to-sync).
        // This prevents double-scroll after user-initiated navigation.
        guard (now - lastManualScrollTime) >= manualScrollCooldown else { return }
        
        guard currentSentenceIndex >= 0, currentSentenceIndex < preloadedData.sentences.count else { return }
        let sentence = preloadedData.sentences[currentSentenceIndex]
        
        // PROGRESS-BASED ESTIMATION: More reliable than TextKit rect lookup.
        // Find the word's position within this sentence's word list.
        guard let localPosition = sentence.globalWordIndices.firstIndex(of: wordIndex) else { return }
        let totalWordsInSentence = sentence.globalWordIndices.count
        guard totalWordsInSentence > 0 else { return }
        
        // Estimate word's Y position using progress ratio.
        // Words are roughly evenly distributed vertically in wrapped text.
        let wordProgress = CGFloat(localPosition + 1) / CGFloat(totalWordsInSentence)
        let estimatedWordYInSentence = wordProgress * currentSentenceFrame.height
        let estimatedWordYInViewport = currentSentenceFrame.minY + estimatedWordYInSentence
        
        // Check if word is approaching bottom of visible band.
        let triggerY = fieldOfViewTopY + (fieldOfViewHeight * markerTriggerPercent)  // e.g., 75% down the band
        
        if estimatedWordYInViewport >= triggerY {
            lastAutoScrollTime = now
            lastAutoScrolledWordIndex = wordIndex
            
            // Place the marker at the estimated word position, then scroll to it.
            lineScrollMarkerOffsetY = estimatedWordYInSentence
            let markerID = sentenceLineMarkerScrollID(currentSentenceIndex)
            
            // Calculate remaining content height (from current word to end of sentence)
            let remainingHeight = currentSentenceFrame.height - estimatedWordYInSentence
            
            // If remaining content fits in the band, center it instead of top-aligning.
            // This creates a smoother transition as the sentence nears its end.
            let anchor: UnitPoint = remainingHeight <= fieldOfViewHeight ? .center : markerTopSafeAnchor
            
            // Smooth animation for long-sentence scrolling during playback.
            DispatchQueue.main.async { [self] in
                scrollWithAnimation {
                    proxy.scrollTo(markerID, anchor: anchor)
                }
            }
        }
    }
    
    // Manually re-align scroll to the sentence at the current audio time
    private func resyncToCurrentSentence() {
        // Cancel any ongoing user drag state
        isOutOfSync = false
        
        // Force immediate jump without animation to override any scroll momentum
        jumpToSyncPosition(time: getCurrentAudioTime(), animated: false)
        
        // Then do a smooth scroll to the final position after a brief delay
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 50_000_000) // 0.05 seconds
            jumpToSyncPosition(time: getCurrentAudioTime(), animated: true)
        }
    }
    
    // #region agent log helper
    private func agentDebugLog(_ hypothesisId: String, _ location: String, _ message: String, _ data: [String: Any]) {
#if DEBUG
        guard syncGate.isAgentDebugLoggingEnabled else { return }
        // Avoid synchronous file I/O in the UI path (can cause scroll hitching on device).
        let logger = Logger(subsystem: "ReadBetterApp3.0", category: "ReaderDebug")
        logger.debug("hypothesisId=\(hypothesisId, privacy: .public) location=\(location, privacy: .public) message=\(message, privacy: .public) data=\(String(describing: data), privacy: .public)")
#else
        return
#endif
    }
    // #endregion agent log helper
    
    
    // MARK: - Helper Methods
    
    /// Get current audio time safely (validates finite and positive)
    private func getCurrentAudioTime() -> Double {
        let time = audioPlayer.getCurrentTime()
        guard time.isFinite && time >= 0 else { return 0 }
        return time
    }
    
    // MARK: - Format Time
    private func formatTime(_ seconds: Double) -> String {
        PlaybackTimeFormatter.string(from: seconds)
    }

    // MARK: - Now Playing (Lock Screen / Control Center)
    @MainActor

    private func stopPlaybackAndCleanup() {
        audioPlayer.stop()
        AudioSessionController.shared.onPauseRequested = nil
        AudioSessionController.shared.onResumeRequested = nil
        // NOTE: Do NOT call setActive(false) here - it breaks background audio for subsequent plays.
        // The audio session should stay active throughout the app's lifecycle.
    }
    
    // MARK: - Header Auto-Hide
    private func scheduleHeaderHide() {
        // Only auto-hide when playing
        guard audioPlayer.isPlaying else { return }
        
        // Cancel any existing hide task
        headerHideTask?.cancel()
        
        // Schedule new hide task
        headerHideTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(headerAutoHideDelay * 1_000_000_000))
            
            guard !Task.isCancelled else { return }
            
            withAnimation(.easeOut(duration: 0.3)) {
                isHeaderVisible = false
                // Also collapse menu when header hides
                isMenuExpanded = false
            }
        }
    }
    
    private func showHeader() {
        // Cancel any pending hide
        headerHideTask?.cancel()
        
        // Show header and menu together with animation
        withAnimation(.easeIn(duration: 0.2)) {
            isHeaderVisible = true
            isMenuExpanded = true
        }
        
        // Schedule auto-hide if playing
        if audioPlayer.isPlaying {
            scheduleHeaderHide()
        }
    }
    
    private func hideHeaderAndMenu() {
        // Cancel any pending hide
        headerHideTask?.cancel()
        
        // Hide header and menu together
        withAnimation(.easeOut(duration: 0.3)) {
            isHeaderVisible = false
            isMenuExpanded = false
        }
    }
    
    private func handleUserInteraction(shouldReopen: Bool = true) {
        // User interaction behavior:
        // - If shouldReopen is false (e.g., sentence tap), only reset timer if already visible
        // - If shouldReopen is true (e.g., button press), reopen header/menu if hidden
        if shouldReopen && (!isHeaderVisible || !isMenuExpanded) {
            showHeader()
        } else if audioPlayer.isPlaying && isHeaderVisible {
            // If already visible and playing, reset the hide timer
            scheduleHeaderHide()
        }
    }
    
    // MARK: - Text Search
    private func performSearch() {
        guard !searchQuery.isEmpty else {
            searchMatches = []
            currentSearchMatchIndex = 0
            return
        }
        
        let query = searchQuery.lowercased()
        var matches: [SearchMatch] = []
        
        // Search through all sentences
        for (index, sentence) in preloadedData.sentences.enumerated() {
            let text = sentence.text
            let lowercasedText = text.lowercased()
            
            // Find all occurrences in this sentence
            var searchStartIndex = lowercasedText.startIndex
            
            while searchStartIndex < lowercasedText.endIndex,
                  let range = lowercasedText.range(of: query, range: searchStartIndex..<lowercasedText.endIndex) {
                
                // Convert to original text range
                let originalRange = text.index(text.startIndex, offsetBy: lowercasedText.distance(from: lowercasedText.startIndex, to: range.lowerBound))..<text.index(text.startIndex, offsetBy: lowercasedText.distance(from: lowercasedText.startIndex, to: range.upperBound))
                
                matches.append(SearchMatch(
                    sentenceIndex: index,
                    range: originalRange,
                    matchText: String(text[originalRange])
                ))
                
                // Move past this match
                searchStartIndex = range.upperBound
            }
        }
        
        searchMatches = matches
        currentSearchMatchIndex = matches.isEmpty ? 0 : 0
        
        // Jump to first match
        if !matches.isEmpty {
            scrollToSearchMatch(at: 0)
        }
    }
    
    private func scrollToSearchMatch(at index: Int) {
        guard index >= 0, index < searchMatches.count else { return }
        let match = searchMatches[index]
        
        // Update current match index
        currentSearchMatchIndex = index
        
        // Jump to the sentence containing the match
        currentSentenceIndex = match.sentenceIndex
        isOutOfSync = true // Pause auto-scroll during search
        
        guard let proxy = scrollProxy else { return }
        guard match.sentenceIndex >= 0, match.sentenceIndex < preloadedData.sentences.count else { return }
        
        let sentence = preloadedData.sentences[match.sentenceIndex]
        let sentenceText = sentence.text
        
        // Calculate character-based progress of the match within the sentence
        let matchStartOffset = sentenceText.distance(from: sentenceText.startIndex, to: match.range.lowerBound)
        let totalChars = sentenceText.count
        let charProgress = totalChars > 0 ? CGFloat(matchStartOffset) / CGFloat(totalChars) : 0.5
        
        // Use the sentence ID directly (line marker only exists for currentSentenceIndex after re-render)
        let sentenceID = sentenceScrollID(match.sentenceIndex)
        
        // Calculate an anchor point that positions the matched word in the center of visible area
        // The anchor is relative to the sentence view itself
        // charProgress tells us how far down the sentence the match is (0 = top, 1 = bottom)
        // We want to center that position in the viewport
        
        // Account for search bar height when calculating visible area
        let searchBarHeight: CGFloat = 60
        let adjustedViewportHeight = scrollViewHeight - headerHeight - searchBarHeight
        let viewportCenterY = headerHeight + (adjustedViewportHeight / 2)
        
        // The anchor point for scrollTo is relative to the target view
        // anchor.y = 0 means align top of view to scroll position
        // anchor.y = 1 means align bottom of view to scroll position
        // anchor.y = charProgress means align the match position to scroll position
        // We use charProgress as the anchor y to bring that part of the sentence to the target position
        let anchor = UnitPoint(x: 0.5, y: charProgress)
        
        withAnimation(.easeInOut(duration: 0.3)) {
            proxy.scrollTo(sentenceID, anchor: anchor)
        }
    }
    
    private func nextSearchMatch() {
        guard !searchMatches.isEmpty else { return }
        let nextIndex = (currentSearchMatchIndex + 1) % searchMatches.count
        scrollToSearchMatch(at: nextIndex)
    }
    
    private func previousSearchMatch() {
        guard !searchMatches.isEmpty else { return }
        let prevIndex = currentSearchMatchIndex == 0 ? searchMatches.count - 1 : currentSearchMatchIndex - 1
        scrollToSearchMatch(at: prevIndex)
    }
    
    private func closeSearch() {
        isSearchActive = false
        searchQuery = ""
        searchMatches = []
        currentSearchMatchIndex = 0
        isSearchFieldFocused = false
    }
    
    // MARK: - Settings Management
    private func loadSettings() {
        // Load text size
        if let savedTextSize = UserDefaults.standard.string(forKey: textSizeKey),
           let size = TextSize(rawValue: savedTextSize) {
            textSize = size
        }
        
        // Load playback speed
        let savedSpeed = UserDefaults.standard.double(forKey: playbackSpeedKey)
        if savedSpeed > 0 {
            // Validate speed is one of our allowed values
            let allowedSpeeds: [Double] = [0.75, 1.0, 1.25, 1.5, 2.0]
            if allowedSpeeds.contains(savedSpeed) {
                playbackSpeed = savedSpeed
            }
        }
        
        // Load highlight color
        if let savedHighlight = UserDefaults.standard.string(forKey: highlightColorKey),
           let color = HighlightColor(rawValue: savedHighlight) {
            highlightColor = color
        }
        
        // Load background color (default to system theme)
        if let savedBackground = UserDefaults.standard.string(forKey: readerBackgroundColorKey),
           let color = ReaderBackgroundColor(rawValue: savedBackground) {
            readerBackgroundColor = color
        } else {
            // Default to system theme
            readerBackgroundColor = themeManager.isDarkMode ? .dark : .light
        }
    }
}

// MARK: - Optimized Sentence View (Individual Word Segments for Zero Lag)
struct OptimizedSentenceView: View {
    let sentence: PrecomputedSentence
    let sentenceIndex: Int
    let isBookmarked: Bool
    let currentSentenceIndex: Int
    let scrollIDSuffix: String
    let lineMarkerID: String
    let lineMarkerOffsetY: CGFloat
    let currentWordIndex: Int?
    let lastSpokenWordIndex: Int?
    let themeColors: ThemeColors
    let textSize: CGFloat
    let highlightColor: HighlightColor
    let indexedWords: [IndexedWord]
    let explainableWordIndices: Set<Int>
    let searchMatches: [Range<String.Index>] // Search match ranges in this sentence
    let currentSearchMatchIndex: Int? // Index within searchMatches array of the currently selected match (nil if not in this sentence)
    let containerWidth: CGFloat // Actual container width for accurate line break detection
    let onSentenceTap: () -> Void
    let onExplainableWordTap: (Int) -> Void
    
    // Cache base AttributedString (build once, modify on updates)
    // Invalidate cache when textSize or themeColors change
    @State private var baseAttributedString: AttributedString?
    @State private var cachedTextSize: CGFloat = 0
    @State private var cachedThemeColorHash: Int = 0
    
    // Check if sentence is finished (all words spoken and not current sentence)
    private var isFinishedSentence: Bool {
        // Sentence is finished (should have reduced opacity) only when it's not the current sentence
        // This ensures sentences stay at full opacity until currentSentenceIndex changes to a different sentence
        return sentenceIndex != currentSentenceIndex
    }

    private var bookmarkMarkerColor: Color {
        highlightColor == .none ? themeColors.accent : highlightColor.color
    }

    private var bookmarkEdgeMarker: some View {
        RoundedRectangle(cornerRadius: 1, style: .continuous)
            .fill(bookmarkMarkerColor)
            .frame(width: 2) // Very thin but visible
            .frame(maxHeight: .infinity, alignment: .top)
            .offset(x: -20) // Matches LazyVStack .padding(.horizontal, 20) => sits on screen edge
            .padding(.top, 2)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
    
    var body: some View {
        ZStack(alignment: .topLeading) {
            // Use TappableTextView for accurate word-level tap detection
            TappableTextView(
                attributedText: buildNSAttributedString(),
                explainableWordRanges: buildExplainableWordNSRanges(),
                onWordTap: { wordIndex in
                    onExplainableWordTap(wordIndex)
                },
                onBackgroundTap: {
                    onSentenceTap()
                }
            )
                .fixedSize(horizontal: false, vertical: true)
            
            // Single marker used for line-based auto-scroll (no PreferenceKey).
            if sentenceIndex == currentSentenceIndex {
                // IMPORTANT: This must be layout-driven (not `.offset`) so `ScrollViewReader.scrollTo`
                // can target the marker's actual position. `offset` is a post-layout transform and
                // often does not affect the scroll target calculation.
                VStack(spacing: 0) {
                    Color.clear
                        .frame(height: max(lineMarkerOffsetY, 0))
                    Color.clear
                        .frame(width: 1, height: 1)
                        .id(lineMarkerID)
                }
                .allowsHitTesting(false)
            }
        }
        .overlay(alignment: .leading) {
            if isBookmarked {
                bookmarkEdgeMarker
            }
        }
        .opacity(isFinishedSentence ? 0.5 : 1.0) // Apply 50% opacity to finished sentences
        .onAppear {
            // Build base string once on first appearance
            let currentThemeHash = themeColors.text.hashValue
            if baseAttributedString == nil || cachedTextSize != textSize || cachedThemeColorHash != currentThemeHash {
                buildBaseAttributedString()
                cachedTextSize = textSize
                cachedThemeColorHash = currentThemeHash
            }
        }
        .onChange(of: textSize) { _, newValue in
            // CRITICAL FIX: Defer state modifications to avoid "modifying state during view update" warning
            Task { @MainActor in
                // Invalidate cache when text size changes
                baseAttributedString = nil
                cachedTextSize = newValue
                buildBaseAttributedString()
            }
        }
        .onChange(of: themeColors.text) { _, _ in
            // CRITICAL FIX: Defer state modifications to avoid "modifying state during view update" warning
            Task { @MainActor in
                // CRITICAL: Invalidate cache when theme colors change to fix initial load bug
                // This ensures text colors are correct on initial load with lighter backgrounds
                baseAttributedString = nil
                cachedThemeColorHash = themeColors.text.hashValue
                buildBaseAttributedString()
            }
        }
        .id("\(themeColors.text.hashValue)-\(themeColors.primary.hashValue)-\(themeColors.background.hashValue)") // Force rebuild when theme colors change (background color change)
    }
    
    // Build base AttributedString once (Grok's approach - cache the base)
    private func buildBaseAttributedString() {
        let text = sentence.text
         var base = AttributedString(text)
        
        // Set base styling with dynamic text size
        base.font = .system(size: textSize, weight: .semibold)
        
        // Handle sentences with no matched words
        // CRITICAL: Always use current themeColors (not cached) to fix initial load bug
        if sentence.globalWordIndices.isEmpty {
            base.foregroundColor = themeColors.text.opacity(0.5)
        } else {
            // Set default color for all text (will be overridden for specific words)
            base.foregroundColor = themeColors.text.opacity(0.5)
        }
        
        baseAttributedString = base
    }
    
    // Build AttributedString efficiently - use cached base and only modify changed ranges
    private func buildAttributedString() -> AttributedString {
        // Build base if not cached or if theme colors have changed
        let currentThemeHash = themeColors.text.hashValue
        let needsCacheUpdate = baseAttributedString == nil || cachedThemeColorHash != currentThemeHash
        
        // CRITICAL FIX: Don't modify state during body calculation
        // If cache is invalid, build a temporary string for this render
        // Defer the actual cache update to happen asynchronously
        let base: AttributedString
        if needsCacheUpdate {
            // Build temporary base without modifying state
            let text = sentence.text
            var tempBase = AttributedString(text)
            tempBase.font = .system(size: textSize, weight: .semibold)
            if sentence.globalWordIndices.isEmpty {
                tempBase.foregroundColor = themeColors.text.opacity(0.5)
            } else {
                tempBase.foregroundColor = themeColors.text.opacity(0.5)
            }
            base = tempBase
            
            // Defer cache update to happen after body calculation
            DispatchQueue.main.async {
                buildBaseAttributedString()
                cachedThemeColorHash = currentThemeHash
            }
        } else if let cachedBase = baseAttributedString {
            base = cachedBase
        } else {
            // Fallback if base building failed
            var attributed = AttributedString(sentence.text)
            attributed.font = .system(size: textSize, weight: .semibold)
            attributed.foregroundColor = themeColors.text.opacity(0.5)
            return attributed
        }
        
        // Create mutable copy (O(1) operation - Grok's approach)
        // AttributedString is a value type, so assignment creates a copy
        var attributed = base
        let text = sentence.text
        
        // Handle sentences with no matched words
        guard !sentence.globalWordIndices.isEmpty else {
            return attributed
        }
        
        // Build sorted ranges first (needed for both highlight and punctuation)
        let sortedRanges = sentence.wordRanges
            .filter { sentence.globalWordIndices.contains($0.wordIndex) }
            .sorted { $0.range.lowerBound < $1.range.lowerBound }
        
        // Apply word colors efficiently (purely by time-based currentWordIndex; ignore sentence gating)
        for (wordIndex, range) in sentence.wordRanges {
            guard sentence.globalWordIndices.contains(wordIndex) else { continue }
            guard range.lowerBound >= text.startIndex,
                  range.upperBound <= text.endIndex,
                  range.lowerBound < range.upperBound else { continue }
            
            let startOffset = text.distance(from: text.startIndex, to: range.lowerBound)
            let endOffset = text.distance(from: text.startIndex, to: range.upperBound)
            
            guard startOffset >= 0 && endOffset <= text.count && startOffset < endOffset,
                  let attrStart = attributed.characters.index(attributed.characters.startIndex, offsetBy: startOffset, limitedBy: attributed.characters.endIndex),
                  let attrEnd = attributed.characters.index(attrStart, offsetBy: endOffset - startOffset, limitedBy: attributed.characters.endIndex) else {
                continue
            }
            
            let attrRange = attrStart..<attrEnd
            
            // Apply color based on word state
            if wordIndex == currentWordIndex {
                attributed[attrRange].foregroundColor = themeColors.primary
            } else if let lastSpoken = lastSpokenWordIndex, wordIndex <= lastSpoken {
                attributed[attrRange].foregroundColor = themeColors.text
            } else {
                attributed[attrRange].foregroundColor = themeColors.text.opacity(0.5)
            }
            
            // Apply styling for explainable words - make them stand out subtly
            if explainableWordIndices.contains(wordIndex) {
                // Thick light blue underline for explainable words
                attributed[attrRange].underlineStyle = .thick
                let lightBlue = Color(red: 100/255, green: 180/255, blue: 255/255) // Brighter blue
                attributed[attrRange].underlineColor = UIColor(lightBlue)
                
                // Make explainable words slightly brighter to draw attention (even when read)
                if wordIndex != currentWordIndex {
                    // Boost brightness: unread goes from 0.5 -> 0.75, read stays full but gets subtle tint
                    if let lastSpoken = lastSpokenWordIndex, wordIndex <= lastSpoken {
                        // Already read - keep full brightness, underline does the work
                    } else {
                        // Unread - make brighter than normal unread words
                        attributed[attrRange].foregroundColor = themeColors.text.opacity(0.75)
                    }
                }
            }
        }
        
        // Apply continuous highlight background for spoken/current words (includes punctuation)
        // Get highlight ranges to check punctuation
        var highlightRanges: [Range<Int>] = []
        if highlightColor != .none {
            highlightRanges = applyContinuousHighlight(to: &attributed, text: text, sortedRanges: sortedRanges)
            
            // Change underline to yellow for explainable words that are highlighted
            // This ensures they remain visible on any highlight color
            for (wordIndex, range) in sortedRanges {
                if explainableWordIndices.contains(wordIndex) {
                    let startOffset = text.distance(from: text.startIndex, to: range.lowerBound)
                    let endOffset = text.distance(from: text.startIndex, to: range.upperBound)
                    let intRange = startOffset..<endOffset
                    
                    // Check if this word is within a highlighted range
                    let isHighlighted = highlightRanges.contains { highlightRange in
                        intRange.overlaps(highlightRange)
                    }
                    
                    if isHighlighted {
                        // Change to yellow thick underline only when highlight is BLUE (for contrast)
                        // Otherwise keep the blue underline for other highlight colors
                        let attrRange = AttributedString.Index(range.lowerBound, within: attributed)!..<AttributedString.Index(range.upperBound, within: attributed)!
                        if highlightColor == .blue {
                            let yellow = Color(red: 255/255, green: 200/255, blue: 0/255) // Bright yellow
                            attributed[attrRange].underlineColor = UIColor(yellow)
                        }
                        // For other colors, keep the light blue underline
                    }
                }
            }
        }
        
        // Apply search match highlighting
        for (matchIndex, matchRange) in searchMatches.enumerated() {
            let startOffset = text.distance(from: text.startIndex, to: matchRange.lowerBound)
            let endOffset = text.distance(from: text.startIndex, to: matchRange.upperBound)
            
            guard startOffset >= 0 && endOffset <= text.count && startOffset < endOffset,
                  let attrStart = attributed.characters.index(attributed.characters.startIndex, offsetBy: startOffset, limitedBy: attributed.characters.endIndex),
                  let attrEnd = attributed.characters.index(attrStart, offsetBy: endOffset - startOffset, limitedBy: attributed.characters.endIndex) else {
                continue
            }
            
            let attrRange = attrStart..<attrEnd
            // Check if this is the currently selected search match by index
            let isCurrentMatch = currentSearchMatchIndex == matchIndex
            
            if isCurrentMatch {
                // Green/teal background for current selected match - stands out from others
                attributed[attrRange].backgroundColor = UIColor(Color.green.opacity(0.6))
            } else {
                // Orange background for other search matches
                attributed[attrRange].backgroundColor = UIColor(Color.orange.opacity(0.4))
            }
            // Black text for visibility
            attributed[attrRange].foregroundColor = .black
        }
        
        // Apply punctuation styling (simplified - just follow word before it)
        
        var coveredRanges: [Range<Int>] = []
        for (_, range) in sortedRanges {
            let startOffset = text.distance(from: text.startIndex, to: range.lowerBound)
            let endOffset = text.distance(from: text.startIndex, to: range.upperBound)
            coveredRanges.append(startOffset..<endOffset)
        }
        
        // Style uncovered characters (punctuation/spaces)
        for (index, _) in text.enumerated() {
            let isCovered = coveredRanges.contains { $0.contains(index) }
            if !isCovered {
                guard let attrStart = attributed.characters.index(attributed.characters.startIndex, offsetBy: index, limitedBy: attributed.characters.endIndex),
                      let attrEnd = attributed.characters.index(attrStart, offsetBy: 1, limitedBy: attributed.characters.endIndex) else {
                    continue
                }
                
                let attrRange = attrStart..<attrEnd

                // If this character falls inside a highlight range, force it to black immediately.
                // This prevents the punctuation pass from temporarily overriding the highlight styling
                // until `lastSpokenWordIndex` advances.
                let isInHighlight = highlightRanges.contains { $0.contains(index) }
                if isInHighlight && highlightColor != .none {
                    attributed[attrRange].foregroundColor = .black
                    continue
                }
                
                // Find the word before this position
                let wordBefore = sortedRanges.last { wordRange in
                    let wordEnd = text.distance(from: text.startIndex, to: wordRange.range.upperBound)
                    return wordEnd <= index
                }
                
                if let wordBefore = wordBefore,
                   let lastSpoken = lastSpokenWordIndex,
                   wordBefore.wordIndex <= lastSpoken {
                    // Punctuation after spoken word - make black if in highlight, otherwise normal color
                    if isInHighlight && highlightColor != .none {
                        attributed[attrRange].foregroundColor = .black
                    } else {
                        attributed[attrRange].foregroundColor = themeColors.text
                    }
                } else {
                    attributed[attrRange].foregroundColor = themeColors.text.opacity(0.5)
                }
            }
        }
        
        return attributed
    }
    
    // MARK: - NSAttributedString for TappableTextView
    
    /// Build NSAttributedString for UIKit-based TappableTextView
    /// Mirrors the logic from buildAttributedString() but returns NSAttributedString
    private func buildNSAttributedString() -> NSAttributedString {
        let text = sentence.text
        let result = NSMutableAttributedString(string: text)
        
        // Base styling
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = textSize * 0.4
        
        let baseAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: textSize, weight: .semibold),
            .foregroundColor: UIColor(themeColors.text.opacity(0.5)),
            .paragraphStyle: paragraphStyle
        ]
        result.addAttributes(baseAttributes, range: NSRange(location: 0, length: text.count))
        
        // Handle sentences with no matched words
        guard !sentence.globalWordIndices.isEmpty else {
            return result
        }
        
        // Build sorted ranges
        let sortedRanges = sentence.wordRanges
            .filter { sentence.globalWordIndices.contains($0.wordIndex) }
            .sorted { $0.range.lowerBound < $1.range.lowerBound }
        
        // Apply word colors
        for (wordIndex, range) in sentence.wordRanges {
            guard sentence.globalWordIndices.contains(wordIndex) else { continue }
            guard range.lowerBound >= text.startIndex,
                  range.upperBound <= text.endIndex,
                  range.lowerBound < range.upperBound else { continue }
            
            let startOffset = text.distance(from: text.startIndex, to: range.lowerBound)
            let length = text.distance(from: range.lowerBound, to: range.upperBound)
            let nsRange = NSRange(location: startOffset, length: length)
            
            // Apply color based on word state
            let color: UIColor
            if wordIndex == currentWordIndex {
                color = UIColor(themeColors.primary)
            } else if let lastSpoken = lastSpokenWordIndex, wordIndex <= lastSpoken {
                color = UIColor(themeColors.text)
            } else {
                color = UIColor(themeColors.text.opacity(0.5))
            }
            result.addAttribute(.foregroundColor, value: color, range: nsRange)
            
            // Apply styling for explainable words - make them stand out subtly
            if explainableWordIndices.contains(wordIndex) {
                // Thick light blue underline for explainable words
                result.addAttribute(.underlineStyle, value: NSUnderlineStyle.thick.rawValue, range: nsRange)
                let lightBlue = UIColor(Color(red: 100/255, green: 180/255, blue: 255/255)) // Brighter blue
                result.addAttribute(.underlineColor, value: lightBlue, range: nsRange)
                
                // Make explainable words slightly brighter to draw attention (even when read)
                if wordIndex != currentWordIndex {
                    if let lastSpoken = lastSpokenWordIndex, wordIndex <= lastSpoken {
                        // Already read - keep full brightness, underline does the work
                    } else {
                        // Unread - make brighter than normal unread words (0.75 vs 0.5)
                        let brighterColor = UIColor(themeColors.text.opacity(0.75))
                        result.addAttribute(.foregroundColor, value: brighterColor, range: nsRange)
                    }
                }
            }
        }
        
        // Apply highlight background if enabled
        // HORIZONTAL: Words on same line connected (including spaces between)
        // VERTICAL: Each line separate (highlight stops at line breaks)
        // CRITICAL: Must match logic in applyContinuousHighlight() to prevent vertical bleeding
        var highlightedNSRanges: [NSRange] = []  // Track highlighted ranges for punctuation styling
        if highlightColor != .none, let lastSpoken = lastSpokenWordIndex {
            // Find all words that should be highlighted (with their indices for consecutive checking)
            let wordsToHighlight = sortedRanges
                .filter { wordIndex, _ in wordIndex == currentWordIndex || wordIndex <= lastSpoken }
            
            if !wordsToHighlight.isEmpty {
                // Group consecutive words into continuous ranges
                // CRITICAL: Check for line breaks AND non-consecutive word indices
                var continuousRanges: [(start: Int, end: Int)] = []
                var currentStart: Int? = nil
                var currentEnd: Int? = nil
                var prevWordIndex: Int? = nil
                
                for (index, (wordIndex, range)) in wordsToHighlight.enumerated() {
                    let startOffset = text.distance(from: text.startIndex, to: range.lowerBound)
                    let endOffset = text.distance(from: text.startIndex, to: range.upperBound)
                    
                    // Check if there's a line break before this word
                    let hasLineBreakBefore: Bool = {
                        if index == 0 { return false }
                        let prevRange = wordsToHighlight[index - 1].range
                        // SAFETY: Guard against overlapping word ranges to prevent crash
                        guard prevRange.upperBound <= range.lowerBound else {
                            return true  // Treat overlapping ranges as separate highlights
                        }
                        let textBetween = String(text[prevRange.upperBound..<range.lowerBound])
                        return textBetween.contains("\n") || textBetween.contains("\r")
                    }()
                    
                    // Check if this word is consecutive with the previous word in word indices
                    let isConsecutiveWord: Bool = {
                        guard let prev = prevWordIndex else { return true }
                        return wordIndex == prev + 1
                    }()
                    
                    // Determine if we should continue the current range or start a new one
                    let shouldContinue: Bool = {
                        guard let prevEnd = currentEnd else { return false }
                        // Don't continue if there's a line break
                        if hasLineBreakBefore { return false }
                        // Don't continue if words aren't consecutive (handles hyphenated words)
                        if !isConsecutiveWord { return false }
                        // Don't continue if gap is too large
                        let gap = startOffset - prevEnd
                        return gap <= 3
                    }()
                    
                    if shouldContinue {
                        // Extend current range
                        currentEnd = endOffset
                    } else {
                        // Save previous range and start new one
                        if let start = currentStart, let end = currentEnd {
                            continuousRanges.append((start: start, end: end))
                        }
                        currentStart = startOffset
                        currentEnd = endOffset
                    }
                    
                    prevWordIndex = wordIndex
                }
                
                // Add final range
                if let start = currentStart, let end = currentEnd {
                    continuousRanges.append((start: start, end: end))
                }
                
                // Extend each range to include adjacent punctuation (but not spaces or across lines)
                var finalRanges: [(start: Int, end: Int)] = []
                for range in continuousRanges {
                    var startOffset = range.start
                    var endOffset = range.end
                    
                    // Scan backward to include leading punctuation ONLY (quotes, etc.)
                    // Stop at whitespace or line breaks
                    while startOffset > 0 {
                        let charIndex = text.index(text.startIndex, offsetBy: startOffset - 1)
                        let char = text[charIndex]
                        if char.isPunctuation && !char.isWhitespace && char != "\n" && char != "\r" {
                            startOffset -= 1
                        } else {
                            break
                        }
                    }
                    
                    // Scan forward to include trailing punctuation ONLY
                    // Stop at whitespace or line breaks
                    while endOffset < text.count {
                        let charIndex = text.index(text.startIndex, offsetBy: endOffset)
                        let char = text[charIndex]
                        if char.isPunctuation && !char.isWhitespace && char != "\n" && char != "\r" {
                            endOffset += 1
                        } else {
                            break
                        }
                    }
                    
                    finalRanges.append((start: startOffset, end: endOffset))
                }
                
                // Apply background to each range
                // Use TextKit 2 to split ranges at visual line boundaries to prevent vertical bleeding
                // This matches how UITextView renders text (TextKit 2 by default on iOS 16+)
                let effectiveWidth = containerWidth > 0 ? containerWidth : UIScreen.main.bounds.width - 40
                
                // Create TextKit 2 layout infrastructure
                let textContentStorage = NSTextContentStorage()
                textContentStorage.attributedString = result
                
                let textLayoutManager = NSTextLayoutManager()
                textContentStorage.addTextLayoutManager(textLayoutManager)
                
                let textContainer = NSTextContainer(size: CGSize(width: effectiveWidth, height: .greatestFiniteMagnitude))
                textContainer.lineFragmentPadding = 0
                textLayoutManager.textContainer = textContainer
                
                // Force layout calculation
                textLayoutManager.ensureLayout(for: textLayoutManager.documentRange)
                
                // Collect all line break positions using TextKit 2
                var lineBreakPositions: [Int] = []
                textLayoutManager.enumerateTextLayoutFragments(
                    from: textContentStorage.documentRange.location,
                    options: [.ensuresLayout]
                ) { fragment in
                    for lineFragment in fragment.textLineFragments {
                        let lineRange = lineFragment.characterRange
                        if let elementRange = fragment.textElement?.elementRange,
                           let startLocation = elementRange.location as? NSTextLocation {
                            let documentOffset = textContentStorage.offset(
                                from: textContentStorage.documentRange.location,
                                to: startLocation
                            )
                            let lineEnd = documentOffset + lineRange.location + lineRange.length
                            lineBreakPositions.append(lineEnd)
                        }
                    }
                    return true
                }
                
                // Apply highlights split at line boundaries
                for range in finalRanges {
                    var currentPos = range.start
                    let rangeEnd = range.end
                    
                    while currentPos < rangeEnd {
                        // Find the next line break after currentPos
                        var segmentEnd = rangeEnd
                        for lineBreak in lineBreakPositions {
                            if lineBreak > currentPos && lineBreak < segmentEnd {
                                segmentEnd = lineBreak
                                break
                            }
                        }
                        
                        let segmentLength = segmentEnd - currentPos
                        if segmentLength > 0 {
                            let segmentRange = NSRange(location: currentPos, length: segmentLength)
                            result.addAttribute(.backgroundColor, value: UIColor(highlightColor.color), range: segmentRange)
                            result.addAttribute(.foregroundColor, value: UIColor.black, range: segmentRange)
                            highlightedNSRanges.append(segmentRange)
                        }
                        
                        currentPos = segmentEnd
                    }
                }
            }
            
            // Change underline to yellow for explainable words that are highlighted
            // This ensures they remain visible on any highlight color
            for (wordIndex, range) in sortedRanges {
                if explainableWordIndices.contains(wordIndex) {
                    let startOffset = text.distance(from: text.startIndex, to: range.lowerBound)
                    let endOffset = text.distance(from: text.startIndex, to: range.upperBound)
                    
                    // Check if this word is within a highlighted range
                    let isHighlighted = highlightedNSRanges.contains { highlightRange in
                        let wordStart = startOffset
                        let wordEnd = endOffset
                        let highlightStart = highlightRange.location
                        let highlightEnd = highlightRange.location + highlightRange.length
                        return wordStart < highlightEnd && wordEnd > highlightStart
                    }
                    
                    if isHighlighted {
                        // Change to yellow thick underline only when highlight is BLUE (for contrast)
                        // Otherwise keep the blue underline for other highlight colors
                        let nsRange = NSRange(location: startOffset, length: endOffset - startOffset)
                        if highlightColor == .blue {
                            let yellow = UIColor(Color(red: 255/255, green: 200/255, blue: 0/255)) // Bright yellow
                            result.addAttribute(.underlineColor, value: yellow, range: nsRange)
                        }
                        // For other colors, keep the light blue underline
                    }
                }
            }
        }
        
        // Apply search match highlighting
        for (matchIndex, matchRange) in searchMatches.enumerated() {
            let startOffset = text.distance(from: text.startIndex, to: matchRange.lowerBound)
            let length = text.distance(from: matchRange.lowerBound, to: matchRange.upperBound)
            let nsRange = NSRange(location: startOffset, length: length)
            
            // Check if this is the currently selected search match by index
            let isCurrentMatch = currentSearchMatchIndex == matchIndex
            
            if isCurrentMatch {
                // Green/teal background for current selected match - stands out from others
                result.addAttribute(.backgroundColor, value: UIColor(Color.green.opacity(0.6)), range: nsRange)
            } else {
                // Orange background for other search matches
                result.addAttribute(.backgroundColor, value: UIColor(Color.orange.opacity(0.4)), range: nsRange)
            }
            result.addAttribute(.foregroundColor, value: UIColor.black, range: nsRange)
        }
        
        // Style punctuation (simplified - follow preceding word, respect highlights)
        var coveredRanges: [Range<Int>] = []
        for (_, range) in sortedRanges {
            let startOffset = text.distance(from: text.startIndex, to: range.lowerBound)
            let endOffset = text.distance(from: text.startIndex, to: range.upperBound)
            coveredRanges.append(startOffset..<endOffset)
        }
        
        for (index, _) in text.enumerated() {
            let isCovered = coveredRanges.contains { $0.contains(index) }
            if !isCovered {
                let nsRange = NSRange(location: index, length: 1)
                
                // Check if this character is within a highlighted range
                let isInHighlight = highlightedNSRanges.contains { nsRange in
                    index >= nsRange.location && index < nsRange.location + nsRange.length
                }
                
                // If in highlight, color is already black - skip
                if isInHighlight {
                    continue
                }
                
                // Find word before this position
                let wordBefore = sortedRanges.last { wordRange in
                    let wordEnd = text.distance(from: text.startIndex, to: wordRange.range.upperBound)
                    return wordEnd <= index
                }
                
                let color: UIColor
                if let wordBefore = wordBefore,
                   let lastSpoken = lastSpokenWordIndex,
                   wordBefore.wordIndex <= lastSpoken {
                    color = UIColor(themeColors.text)
                } else {
                    color = UIColor(themeColors.text.opacity(0.5))
                }
                result.addAttribute(.foregroundColor, value: color, range: nsRange)
            }
        }
        
        return result
    }
    
    /// Build NSRange array for explainable words (used by TappableTextView for hit testing)
    private func buildExplainableWordNSRanges() -> [(wordIndex: Int, range: NSRange)] {
        let text = sentence.text
        var ranges: [(wordIndex: Int, range: NSRange)] = []
        
        for (wordIndex, range) in sentence.wordRanges {
            guard explainableWordIndices.contains(wordIndex) else { continue }
            guard range.lowerBound >= text.startIndex,
                  range.upperBound <= text.endIndex,
                  range.lowerBound < range.upperBound else { continue }
            
            let startOffset = text.distance(from: text.startIndex, to: range.lowerBound)
            let length = text.distance(from: range.lowerBound, to: range.upperBound)
            let nsRange = NSRange(location: startOffset, length: length)
            
            ranges.append((wordIndex: wordIndex, range: nsRange))
        }
        
        return ranges
    }
    
    // Apply continuous highlight background (includes punctuation, text turns black)
    // Returns the highlight ranges for punctuation checking
    private func applyContinuousHighlight(to attributed: inout AttributedString, text: String, sortedRanges: [(wordIndex: Int, range: Range<String.Index>)]) -> [Range<Int>] {
        guard let lastSpoken = lastSpokenWordIndex else { return [] }
        
        // Find all words that should be highlighted (current word + all spoken words)
        var wordsToHighlight: [(wordIndex: Int, range: Range<String.Index>)] = []
        for (wordIndex, range) in sortedRanges {
            if wordIndex == currentWordIndex || wordIndex <= lastSpoken {
                wordsToHighlight.append((wordIndex, range))
            }
        }
        
        guard !wordsToHighlight.isEmpty else { return [] }
        
        // Group consecutive words (no line breaks between them) into continuous ranges
        // Include punctuation and spaces between words, AND leading punctuation before first word
        var continuousRanges: [Range<Int>] = []
        var currentStart: Int? = nil
        var currentEnd: Int? = nil
        
        // Check if first word has leading punctuation to include
        let firstWordRange = wordsToHighlight.first!.range
        let firstWordStartOffset = text.distance(from: text.startIndex, to: firstWordRange.lowerBound)
        
        // Look backward from first word to include leading punctuation and spaces
        var extendedStart = firstWordStartOffset
        if firstWordStartOffset > 0 {
            // Check if there's a line break before the first word
            let textBefore = String(text[text.startIndex..<firstWordRange.lowerBound])
            let hasLineBreakBefore = textBefore.contains("\n") || textBefore.contains("\r")
            
            if !hasLineBreakBefore {
                // No line break - include everything from the start of the sentence
                // This includes leading punctuation like " , at the start
                extendedStart = 0
            }
            // If there's a line break, keep extendedStart at firstWordStartOffset (don't include previous line)
        }
        
        for (index, (wordIndex, range)) in wordsToHighlight.enumerated() {
            let startOffset = text.distance(from: text.startIndex, to: range.lowerBound)
            let endOffset = text.distance(from: text.startIndex, to: range.upperBound)
            
            // For the first word, use the extended start that includes leading punctuation
            let actualStartOffset = (index == 0) ? extendedStart : startOffset
            
            // Check if there's a line break before this word
            let textBefore = String(text[text.startIndex..<range.lowerBound])
            let hasLineBreakBefore = textBefore.contains("\n") || textBefore.contains("\r")
            
            // CRITICAL FIX: Check if this word is consecutive with the previous word in the word map
            // If there's a gap in word indices, they should be separate highlights even if adjacent in text
            // This handles hyphenated words like "self-improvement" where "self" and "improvement" are separate words
            let isConsecutiveWord = index > 0 ? {
                let prevWordIndex = wordsToHighlight[index - 1].wordIndex
                // Words are consecutive if their indices are sequential (difference of 1)
                return wordIndex == prevWordIndex + 1
            }() : true
            
            // Find the next word or end of sentence to include punctuation
            var extendedEnd = endOffset
            if endOffset < text.count {
                // Look ahead to include punctuation and spaces until next word or line break
                let remainingText = String(text[text.index(text.startIndex, offsetBy: endOffset)...])
                
                // Check if the next word in sortedRanges is the next consecutive word in our highlight list
                // If not, we should stop at the hyphen/punctuation (don't include the next word)
                let nextWordInHighlight = index + 1 < wordsToHighlight.count ? wordsToHighlight[index + 1] : nil
                let isNextWordConsecutive = nextWordInHighlight != nil ? {
                    return nextWordInHighlight!.wordIndex == wordIndex + 1
                }() : false
                
                if let nextWordStart = sortedRanges.first(where: { wordRange in
                    let wordStart = text.distance(from: text.startIndex, to: wordRange.range.lowerBound)
                    return wordStart > endOffset
                }) {
                    let nextStart = text.distance(from: text.startIndex, to: nextWordStart.range.lowerBound)
                    
                    // If the next word is NOT consecutive in the word map, only include up to punctuation (hyphen)
                    // This keeps the hyphen with the first word but starts a new range for the second word
                    if !isNextWordConsecutive {
                        // Only include punctuation (like hyphen) but stop before the next word
                        // Find the first non-punctuation/non-space character (the start of next word)
                        // Note: textAfter is calculated but not used - kept for potential future debugging
                        let _ = String(text[text.index(text.startIndex, offsetBy: endOffset)..<text.index(text.startIndex, offsetBy: nextStart)])
                        // Include all punctuation and spaces, but stop at the word boundary
                        extendedEnd = nextStart
                    } else {
                        // Next word is consecutive - include everything up to (but not including) the next word
                        extendedEnd = nextStart
                    }
                } else {
                    // No more words, include to end of sentence
                    extendedEnd = text.count
                }
                
                // Stop at line breaks
                if let lineBreakIndex = remainingText.firstIndex(where: { $0 == "\n" || $0 == "\r" }) {
                    let lineBreakOffsetInRemaining = remainingText.distance(from: remainingText.startIndex, to: lineBreakIndex)
                    let lineBreakOffset = endOffset + lineBreakOffsetInRemaining
                    extendedEnd = min(extendedEnd, lineBreakOffset)
                }
            }
            
            // MODIFIED: Only continue range if words are consecutive in word map AND no line break
            // This prevents grouping separate words that happen to be adjacent in text (like hyphenated words)
            // The hyphen will still be included with the first word (via extendedEnd), but the second word starts a new range
            if let prevEnd = currentEnd, !hasLineBreakBefore, isConsecutiveWord, actualStartOffset <= prevEnd {
                // Continue current range (include spaces and punctuation between words)
                currentEnd = max(currentEnd ?? actualStartOffset, extendedEnd)
            } else {
                // Start new range (words are separate or have line break)
                if let start = currentStart, let end = currentEnd {
                    continuousRanges.append(start..<end)
                }
                currentStart = actualStartOffset
                currentEnd = extendedEnd
            }
        }
        
        // Add final range
        if let start = currentStart, let end = currentEnd {
            continuousRanges.append(start..<end)
        }
        
        // Apply highlight background to continuous ranges and make text black
        for range in continuousRanges {
            guard range.lowerBound >= 0 && range.upperBound <= text.count,
                  let attrStart = attributed.characters.index(attributed.characters.startIndex, offsetBy: range.lowerBound, limitedBy: attributed.characters.endIndex),
                  let attrEnd = attributed.characters.index(attrStart, offsetBy: range.upperBound - range.lowerBound, limitedBy: attributed.characters.endIndex) else {
                continue
            }
            
            let attrRange = attrStart..<attrEnd
            // Convert SwiftUI Color to UIColor for AttributedString
            if highlightColor != .none {
                attributed[attrRange].backgroundColor = UIColor(highlightColor.color)
                // Make text black inside highlights for visibility
                attributed[attrRange].foregroundColor = .black
            }
        }
        
        return continuousRanges
    }
    
}

// MARK: - Word Segment Model
struct WordSegment: Identifiable {
    let id: String
    let text: String
    let color: Color
}

// MARK: - Equatable Conformance for Performance
extension OptimizedSentenceView: Equatable {
    static func == (lhs: OptimizedSentenceView, rhs: OptimizedSentenceView) -> Bool {
        // PERFORMANCE: Only compare *sentence-local* word indices so unrelated sentences
        // don't re-render on every global word boundary.
        func sentenceMinMax(_ sentence: PrecomputedSentence) -> (min: Int, max: Int)? {
            // PrecomputedSentence.globalWordIndices are expected to be in order.
            guard let min = sentence.globalWordIndices.first,
                  let max = sentence.globalWordIndices.last else { return nil }
            return (min, max)
        }
        
        func effectiveCurrent(_ idx: Int?, sentence: PrecomputedSentence) -> Int? {
            guard let idx else { return nil }
            guard let mm = sentenceMinMax(sentence) else { return nil }
            return (idx >= mm.min && idx <= mm.max) ? idx : nil
        }
        
        func effectiveLastSpoken(_ idx: Int?, sentence: PrecomputedSentence) -> Int? {
            guard let idx else { return nil }
            guard let mm = sentenceMinMax(sentence) else { return nil }
            if idx < mm.min { return nil }
            return min(idx, mm.max)
        }

        // Marker positioning only matters for the *current* sentence (it is not rendered for others).
        // Include it in equality so Back-to-Sync / long-sentence jumps can move the marker even when
        // playback is paused (i.e., currentWordIndex may not be changing).
        let markerPositionIsEqual: Bool = {
            guard lhs.sentenceIndex == lhs.currentSentenceIndex else { return true }
            return abs(lhs.lineMarkerOffsetY - rhs.lineMarkerOffsetY) < 0.5
        }()
        
        // Two views are "equal" (don't need re-render) if:
        // 1. Same sentence
        // 2. Same sentence index and current sentence index (for finished sentence check)
        // 3. Same *effective* (sentence-local) current word index
        // 4. Same *effective* (sentence-local) last spoken word index
        // 5. Same text size
        // 6. Same highlight color
        // 7. Same explainable word indices (for highlighting)
        // 8. Same search matches (for search highlighting)
        // This allows SwiftUI to skip re-rendering sentences that haven't actually changed
        return lhs.sentence.id == rhs.sentence.id &&
               lhs.sentenceIndex == rhs.sentenceIndex &&
               lhs.currentSentenceIndex == rhs.currentSentenceIndex &&
               effectiveCurrent(lhs.currentWordIndex, sentence: lhs.sentence) == effectiveCurrent(rhs.currentWordIndex, sentence: rhs.sentence) &&
               effectiveLastSpoken(lhs.lastSpokenWordIndex, sentence: lhs.sentence) == effectiveLastSpoken(rhs.lastSpokenWordIndex, sentence: rhs.sentence) &&
               lhs.textSize == rhs.textSize &&
               lhs.highlightColor == rhs.highlightColor &&
               lhs.isBookmarked == rhs.isBookmarked &&
               lhs.explainableWordIndices == rhs.explainableWordIndices &&
               lhs.searchMatches.count == rhs.searchMatches.count &&
               lhs.containerWidth == rhs.containerWidth &&
               markerPositionIsEqual
    }
}

// MARK: - Optimized Audio Player (Singleton for Background Playback)
class OptimizedAudioPlayer: ObservableObject {
    // SINGLETON: Player must persist beyond view lifecycle for background playback
    static let shared = OptimizedAudioPlayer()
    
    @Published var isPlaying = false
    @Published var duration: Double = 0
    @Published var isLoading = false
    @Published var playbackSpeed: Double = 1.0
    
    // PERFORMANCE: Separate internal time tracking from UI updates
    // currentTime is accessed frequently by reader view (60fps) but should NOT trigger UI updates elsewhere
    private(set) var currentTime: Double = 0  // Internal, high-frequency tracking (not @Published)
    private(set) var displayTime: Double = 0  // UI-friendly, throttled (not @Published to prevent mini player flashing)
    
    // Mini Player metadata (exposed for external access)
    @Published private(set) var chapterTitle: String = ""
    @Published private(set) var bookTitle: String = ""
    @Published private(set) var coverURL: URL?
    @Published private(set) var bookId: String = ""
    @Published private(set) var chapterNumber: Int = 1
    
    // OPTIMIZATION: Store preloaded data for instant reader re-entry
    // When user returns to a book that's already playing, skip loading entirely
    private(set) var preloadedData: PreloadedReaderData?
    
    // MARK: - Last Played Session Persistence
    private let lastPlayedKey = "lastPlayedSession"
    
    /// Returns true if audio is actively playing (player exists and loaded)
    var hasActiveSession: Bool {
        return player != nil && !chapterTitle.isEmpty && duration > 0
    }
    
    /// Returns true if we have displayable session info (either active OR last-played)
    /// Use this for showing the mini player UI
    var hasDisplayableSession: Bool {
        return !chapterTitle.isEmpty && !bookTitle.isEmpty
    }
    
    /// Check if we have valid preloaded data for a specific book/chapter
    func hasPreloadedData(for bookId: String, chapterNumber: Int) -> Bool {
        guard let data = preloadedData else { return false }
        return data.book.id == bookId && (data.chapter.order + 1) == chapterNumber
    }
    
    /// Store preloaded data for later re-use
    func setPreloadedData(_ data: PreloadedReaderData) {
        self.preloadedData = data
    }
    
    /// Clear preloaded data (e.g., when loading a different book)
    func clearPreloadedData() {
        self.preloadedData = nil
    }
    
    var onTimeUpdate: ((Double, Double) -> Void)?

    // Now Playing metadata and state (internal)
    private var nowPlayingActivated = false

    private var player: AVPlayer?
    private var timeObserver: Any?
    private weak var timeObserverPlayer: AVPlayer? // Track which player the observer was added to
    private var durationObserver: NSKeyValueObservation?
    private var timeControlStatusObserver: NSKeyValueObservation?
    private var playbackEndObserver: NSObjectProtocol?
    private var playbackErrorObserver: NSObjectProtocol?
    
    // Progress bar updates (throttled for performance)
    // Word sync is now handled by CADisplayLink at 60fps in reader view
    // UI updates (mini player, etc.) throttled to 1fps to prevent app-wide lag
    private let progressUpdateInterval: Double = 1.0 // 1 second for UI updates
    private var lastDisplayTimeUpdate: Double = 0
    
    private init() {
        // Load last played session on init
        loadLastPlayedSession()
    }
    
    // MARK: - Last Played Session Storage
    
    /// Save current session info to UserDefaults for display on next launch
    func saveLastPlayedSession() {
        guard !bookId.isEmpty, !chapterTitle.isEmpty else { return }
        let sessionData: [String: Any] = [
            "bookId": bookId,
            "bookTitle": bookTitle,
            "chapterTitle": chapterTitle,
            "chapterNumber": chapterNumber,
            "coverURL": coverURL?.absoluteString ?? "",
            "currentTime": currentTime,
            "duration": duration
        ]
        UserDefaults.standard.set(sessionData, forKey: lastPlayedKey)
    }
    
    /// Load last played session from UserDefaults
    private func loadLastPlayedSession() {
        guard let sessionData = UserDefaults.standard.dictionary(forKey: lastPlayedKey) else { return }
        
        bookId = sessionData["bookId"] as? String ?? ""
        bookTitle = sessionData["bookTitle"] as? String ?? ""
        chapterTitle = sessionData["chapterTitle"] as? String ?? ""
        chapterNumber = sessionData["chapterNumber"] as? Int ?? 1
        currentTime = sessionData["currentTime"] as? Double ?? 0
        displayTime = currentTime  // Sync display time
        duration = sessionData["duration"] as? Double ?? 0
        
        if let urlString = sessionData["coverURL"] as? String, !urlString.isEmpty {
            coverURL = URL(string: urlString)
        }
    }
    
    /// Clear last played session (e.g., on logout)
    func clearLastPlayedSession() {
        UserDefaults.standard.removeObject(forKey: lastPlayedKey)
        bookId = ""
        bookTitle = ""
        chapterTitle = ""
        chapterNumber = 1
        coverURL = nil
        currentTime = 0
        displayTime = 0
        duration = 0
    }

    // MARK: - Now Playing Management

    private func activateNowPlayingIfNeeded() {
        guard !nowPlayingActivated, !chapterTitle.isEmpty else { return }

        NowPlayingController.shared.activateSession(
            chapterTitle: chapterTitle,
            bookTitle: bookTitle,
            coverURL: coverURL,
            duration: duration,
            play: { [weak self] in self?.play() },
            pause: { [weak self] in self?.pause() },
            seek: { [weak self] in self?.seek(to: $0) },
            currentTime: { [weak self] in self?.currentTime ?? 0 },
            isPlaying: { [weak self] in self?.isPlaying ?? false }
        )
        nowPlayingActivated = true
    }

    private func deactivateNowPlaying() {
        if nowPlayingActivated {
            NowPlayingController.shared.deactivateSession()
            nowPlayingActivated = false
        }
    }

    private func updateNowPlayingMetadata(force: Bool = false) {
        guard nowPlayingActivated else { return }
        NowPlayingController.shared.updatePlaybackState(
            elapsedTime: currentTime,
            isPlaying: isPlaying,
            force: force
        )
    }

    // OPTIMIZATION: Support loading from preloaded asset
    func load(asset: AVURLAsset, preloadedDuration: Double? = nil,
              chapterTitle: String = "", bookTitle: String = "", coverURL: URL? = nil,
              bookId: String = "", chapterNumber: Int = 1) async {
        // Store metadata for Mini Player and Now Playing
        await MainActor.run {
            self.chapterTitle = chapterTitle
            self.bookTitle = bookTitle
            self.coverURL = coverURL
            self.bookId = bookId
            self.chapterNumber = chapterNumber
            // Save for next app launch
            self.saveLastPlayedSession()
        }

        // Clean up previous player before loading new content
        await cleanupCurrentPlayer()

        await MainActor.run {
            isLoading = true
            // Use preloaded duration if available (instant!)
            if let preloadedDuration = preloadedDuration, preloadedDuration > 0 {
                self.duration = preloadedDuration
            }
        }
        
        let playerItem = AVPlayerItem(asset: asset)
        let newPlayer = AVPlayer(playerItem: playerItem)
        // Reduce perceived "first play" latency for spoken audio.
        // (Tradeoff: may increase risk of small stalls on poor networks.)
        newPlayer.automaticallyWaitsToMinimizeStalling = false
        
        await setupPlayerObservers(player: newPlayer, playerItem: playerItem)

        // Register Now Playing + remote commands during load (NOT on the play tap),
        // so the first Play press doesn't stall the main thread/UI updates.
        await MainActor.run { [weak self] in
            guard let self else { return }
            self.activateNowPlayingIfNeeded()
            self.updateNowPlayingMetadata(force: true)
        }
    }
    
    func load(url: URL, preloadedDuration: Double? = nil,
              chapterTitle: String = "", bookTitle: String = "", coverURL: URL? = nil,
              bookId: String = "", chapterNumber: Int = 1) async {
        // Store metadata for Mini Player and Now Playing
        await MainActor.run {
            self.chapterTitle = chapterTitle
            self.bookTitle = bookTitle
            self.coverURL = coverURL
            self.bookId = bookId
            self.chapterNumber = chapterNumber
            // Save for next app launch
            self.saveLastPlayedSession()
        }

        // Clean up previous player before loading new content
        await cleanupCurrentPlayer()

        await MainActor.run {
            isLoading = true
            // Use preloaded duration if available (instant!)
            if let preloadedDuration = preloadedDuration, preloadedDuration > 0 {
                self.duration = preloadedDuration
            }
        }
        
        let playerItem = AVPlayerItem(url: url)
        let newPlayer = AVPlayer(playerItem: playerItem)
        // Reduce perceived "first play" latency for spoken audio.
        // (Tradeoff: may increase risk of small stalls on poor networks.)
        newPlayer.automaticallyWaitsToMinimizeStalling = false
        
        await setupPlayerObservers(player: newPlayer, playerItem: playerItem)

        // Register Now Playing + remote commands during load (NOT on the play tap),
        // so the first Play press doesn't stall the main thread/UI updates.
        await MainActor.run { [weak self] in
            guard let self else { return }
            self.activateNowPlayingIfNeeded()
            self.updateNowPlayingMetadata(force: true)
        }
    }
    
    /// Clean up current player and observers (called before loading new content)
    private func cleanupCurrentPlayer() async {
        // Deactivate Now Playing before cleanup
        deactivateNowPlaying()
        await MainActor.run {
            // Remove time observer from the player that created it
            if let observer = timeObserver, let observerPlayer = timeObserverPlayer {
                observerPlayer.removeTimeObserver(observer)
                timeObserver = nil
                timeObserverPlayer = nil
            }
            
            // Remove notification observers
            if let observer = playbackEndObserver {
                NotificationCenter.default.removeObserver(observer)
                playbackEndObserver = nil
            }
            if let observer = playbackErrorObserver {
                NotificationCenter.default.removeObserver(observer)
                playbackErrorObserver = nil
            }
            
            // Invalidate duration observer
            durationObserver?.invalidate()
            durationObserver = nil

            // Invalidate player state observers
            timeControlStatusObserver?.invalidate()
            timeControlStatusObserver = nil
            
            // Stop and clear player
            player?.pause()
            player = nil
            
            // Reset state
            isPlaying = false
            currentTime = 0
            displayTime = 0
            duration = 0
        }
    }
    
    private func setupPlayerObservers(player: AVPlayer, playerItem: AVPlayerItem) async {
        
        // Observe errors to catch playback issues
        playbackErrorObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime,
            object: playerItem,
            queue: .main
        ) { [weak self] notification in
            if let error = notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error {
                print("⚠️ OptimizedAudioPlayer: Playback error: \(error.localizedDescription)")
            }
        }
        
        // Observe status for duration (fallback if not preloaded)
        durationObserver = playerItem.observe(\.status, options: [.new]) { [weak self] item, _ in
            if item.status == .readyToPlay {
                DispatchQueue.main.async {
                    // VALIDATE: Check if duration CMTime is valid before extracting seconds
                    let durationCMTime = item.duration
                    guard durationCMTime.isValid && durationCMTime.isNumeric else {
                        self?.isLoading = false
                        return
                    }
                    
                    let duration = durationCMTime.seconds
                    
                    // VALIDATE: Only use valid duration
                    if duration.isFinite && duration > 0 {
                        // Only update if we don't have a preloaded duration
                        if self?.duration == 0 || self?.duration == nil {
                            self?.duration = duration
                        }
                    }
                    self?.isLoading = false
                    
                    // Apply playback speed when ready (but don't auto-play)
                    // Only set rate if already playing, otherwise just store the speed
                    if let speed = self?.playbackSpeed, self?.isPlaying == true {
                        self?.player?.rate = Float(speed)
                    }
                }
            }
        }
        
        // Observe playback end
        playbackEndObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: playerItem,
            queue: .main
        ) { [weak self] _ in
            self?.isPlaying = false
        }
        
        await setupTimeObserver(player: player)
    }
    
    private func setupTimeObserver(player: AVPlayer) async {
        await MainActor.run {
            self.player = player
            self.isLoading = false

            // Keep `isPlaying` synchronized with the actual AVPlayer state.
            // This is critical for lock-screen toggle behavior: iOS can pause the player without
            // calling our `pause()`, and we must reflect that so MPRemoteCommandCenter handlers
            // don't get stuck calling "pause" when the UI shows "play".
            timeControlStatusObserver?.invalidate()
            timeControlStatusObserver = player.observe(\.timeControlStatus, options: [.initial, .new]) { [weak self] p, _ in
                guard let self = self else { return }
                DispatchQueue.main.async {
                    let isActuallyPlaying = p.timeControlStatus == .playing && (p.rate > 0)
                    if self.isPlaying != isActuallyPlaying {
                        self.isPlaying = isActuallyPlaying
                    }
                }
            }
            
            // Remove old time observer from the player that created it
            if let observer = timeObserver, let observerPlayer = timeObserverPlayer {
                observerPlayer.removeTimeObserver(observer)
                timeObserver = nil
                timeObserverPlayer = nil
            }
            
            // Low-frequency time observer for progress bar updates only (10fps)
            // Word sync is now handled by CADisplayLink at 60fps in OptimizedReaderView
            let interval = CMTime(seconds: progressUpdateInterval, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
            timeObserverPlayer = player // Track which player we're adding this to
            timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
                guard let self = self else { return }
                
                // VALIDATE: Check if CMTime itself is valid before extracting seconds
                guard time.isValid && time.isNumeric else {
                    return // Skip invalid CMTime
                }
                
                let currentTime = time.seconds
                
                // VALIDATE: Skip invalid time values to prevent FigFilePlayer errors
                guard currentTime.isFinite && currentTime >= 0 else {
                    return // Skip this update
                }
                
                // Update internal time tracking (high-frequency, not published)
                self.currentTime = currentTime
                
                // Update UI-friendly displayTime (throttled to prevent app-wide re-renders)
                // Only update if changed by at least 0.5 seconds to reduce UI churn
                if abs(currentTime - self.lastDisplayTimeUpdate) >= 0.5 {
                    self.displayTime = currentTime
                    self.lastDisplayTimeUpdate = currentTime
                }
                
                // Update Now Playing info periodically (throttled inside NowPlayingController)
                self.updateNowPlayingMetadata()
            }
        }
    }
    
    func play() {
        // Keep observers installed, but avoid doing heavy work on the tap path.
        AudioSessionController.shared.configureIfNeeded()

        guard let p = player else {
            isPlaying = false
            return
        }

        // Prefer immediate start to reduce perceived UI lag.
        if #available(iOS 10.0, *) {
            p.playImmediately(atRate: Float(playbackSpeed))
        } else {
            p.rate = Float(playbackSpeed)
            p.play()
        }

        // Optimistic UI update (observer will correct if needed).
        isPlaying = true

        // Force a single Now Playing update on the transition (remote commands already registered during load).
        updateNowPlayingMetadata(force: true)
    }
    
    func pause() {
        player?.pause()
        isPlaying = false

        // Update Now Playing state
        updateNowPlayingMetadata(force: true)
        
        // Save session state for mini player persistence on next launch
        saveLastPlayedSession()
    }
    
    func togglePlayPause() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }
    
    func seek(to time: Double) {
        // VALIDATE: Ensure time is valid before seeking to prevent FigFilePlayer errors
        guard time.isFinite && time >= 0 else {
            print("⚠️ OptimizedAudioPlayer: Invalid seek time \(time), ignoring")
            return
        }
        
        // VALIDATE: Ensure duration is valid before clamping
        let safeDuration = duration.isFinite && duration > 0 ? duration : 0
        
        // Clamp time to valid range
        let clampedTime = min(max(0, time), max(safeDuration, 0))
        
        // VALIDATE: Double-check clamped time is still valid
        guard clampedTime.isFinite && clampedTime >= 0 else {
            print("⚠️ OptimizedAudioPlayer: Clamped time is invalid \(clampedTime), ignoring")
            return
        }
        
        let cmTime = CMTime(seconds: clampedTime, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        
        // VALIDATE: Ensure CMTime is valid
        guard cmTime.isValid && cmTime.isNumeric else {
            print("⚠️ OptimizedAudioPlayer: Invalid CMTime created from \(clampedTime), ignoring")
            return
        }
        
        // Use tolerance to prevent errors
        player?.seek(to: cmTime, toleranceBefore: CMTime(seconds: 0.1, preferredTimescale: CMTimeScale(NSEC_PER_SEC)), toleranceAfter: CMTime(seconds: 0.1, preferredTimescale: CMTimeScale(NSEC_PER_SEC)))
        currentTime = clampedTime
        displayTime = clampedTime  // Update display time immediately on seek
        lastDisplayTimeUpdate = clampedTime
        
        // Note: onTimeUpdate callback removed - CADisplayLink handles word sync now
    }
    
    /// Seek to specific time and wait for completion
    /// Returns the actual time after seek completes (may differ slightly from target)
    func seekAndWait(to time: Double) async -> Double {
        // VALIDATE: Ensure time is valid before seeking
        guard time.isFinite && time >= 0 else {
            print("⚠️ OptimizedAudioPlayer: Invalid seek time \(time), ignoring")
            return getCurrentTime()
        }
        
        // VALIDATE: Ensure duration is valid before clamping
        let safeDuration = duration.isFinite && duration > 0 ? duration : 0
        
        // Clamp time to valid range
        let clampedTime = min(max(0, time), max(safeDuration, 0))
        
        // VALIDATE: Double-check clamped time is still valid
        guard clampedTime.isFinite && clampedTime >= 0 else {
            print("⚠️ OptimizedAudioPlayer: Clamped time is invalid \(clampedTime), ignoring")
            return getCurrentTime()
        }
        
        let cmTime = CMTime(seconds: clampedTime, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        
        // VALIDATE: Ensure CMTime is valid
        guard cmTime.isValid && cmTime.isNumeric else {
            print("⚠️ OptimizedAudioPlayer: Invalid CMTime created from \(clampedTime), ignoring")
            return getCurrentTime()
        }
        
        // Wait for seek to complete using completion handler
        guard let player = player else {
            // No player available, return current time
            return getCurrentTime()
        }
        
        return await withCheckedContinuation { continuation in
            player.seek(
                to: cmTime,
                toleranceBefore: CMTime(seconds: 0.1, preferredTimescale: CMTimeScale(NSEC_PER_SEC)),
                toleranceAfter: CMTime(seconds: 0.1, preferredTimescale: CMTimeScale(NSEC_PER_SEC)),
                completionHandler: { [weak self] finished in
                    // Get actual time after seek completes (whether successful or not)
                    let actualTime = self?.getCurrentTime() ?? clampedTime
                    self?.currentTime = actualTime
                    self?.displayTime = actualTime  // Update display time immediately on seek
                    self?.lastDisplayTimeUpdate = actualTime
                    continuation.resume(returning: actualTime)
                }
            )
        }
    }
    
    func stop() {
        pause()
        seek(to: 0)

        // Deactivate Now Playing when stopping
        deactivateNowPlaying()
    }
    
    // Set playback speed
    func setPlaybackSpeed(_ speed: Double) {
        playbackSpeed = speed
        // Apply immediately if player is available AND currently playing
        // Don't auto-play when speed changes - only update rate if already playing
        if let player = player, isPlaying {
            player.rate = Float(speed)
        }
    }
    
    // Get current time on demand (for word sync)
    func getCurrentTime() -> Double {
        guard let player = player else { return 0 }
        let time = player.currentTime()
        
        // VALIDATE: Check if CMTime itself is valid before extracting seconds
        guard time.isValid && time.isNumeric else {
            return 0
        }
        
        let seconds = time.seconds
        
        // VALIDATE: Return 0 if time is invalid to prevent FigFilePlayer errors
        guard seconds.isFinite && seconds >= 0 else {
            return 0
        }
        
        return seconds
    }
    
    // Note: No deinit needed for singleton - it lives for the app's lifetime.
    // Cleanup happens in cleanupCurrentPlayer() when loading new content.
}

// MARK: - DisplayLink Target Helper
private class DisplayLinkTarget: NSObject {
    private let minIntervalProvider: () -> CFTimeInterval
    private let callback: () -> Void
    private var lastFireTimestamp: CFTimeInterval = 0
    
    init(minIntervalProvider: @escaping () -> CFTimeInterval, callback: @escaping () -> Void) {
        self.minIntervalProvider = minIntervalProvider
        self.callback = callback
        super.init()
    }
    
    @objc func tick(_ displayLink: CADisplayLink) {
        let minInterval = minIntervalProvider()
        if minInterval > 0 {
            let ts = displayLink.timestamp
            if lastFireTimestamp > 0, (ts - lastFireTimestamp) < minInterval {
                return
            }
            lastFireTimestamp = ts
        }
        
        self.callback() // Explicitly use self to avoid warning
    }
}

// MARK: - Sync Gate (shared with DisplayLink throttling)
@MainActor
private final class ReaderSyncGate: ObservableObject {
    @Published var isUserDraggingScroll: Bool = false
    let isAgentDebugLoggingEnabled: Bool = false
}

// MARK: - Explanation Overlay View
/// Lightweight overlay showing context-specific term explanations
struct ExplanationOverlayView: View {
    let term: ExplainableTerm
    let themeColors: ThemeColors
    let isLightBackground: Bool
    let onDismiss: () -> Void
    
    var body: some View {
        ZStack {
            // Semi-transparent backdrop
            Color.black.opacity(0.3)
                .ignoresSafeArea()
                .onTapGesture {
                    onDismiss()
                }
            
            // Explanation card
            VStack(alignment: .leading, spacing: 12) {
                // Header with term and type badge
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(term.term)
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(themeColors.text)
                        
                        // Type badge
                        HStack(spacing: 4) {
                            Image(systemName: term.type.icon)
                                .font(.system(size: 11, weight: .semibold))
                            Text(term.type.displayName)
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundColor(themeColors.primary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(themeColors.primary.opacity(0.15))
                        .clipShape(Capsule())
                    }
                    
                    Spacer()
                    
                    // Close button
                    Button(action: onDismiss) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 24))
                            .foregroundColor(themeColors.textSecondary)
                    }
                }
                
                // Divider
                Rectangle()
                    .fill(themeColors.cardBorder)
                    .frame(height: 1)
                
                // Explanation text
                Text(term.shortExplanation)
                    .font(.system(size: 16, weight: .regular))
                    .foregroundColor(themeColors.text.opacity(0.9))
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(20)
            .background(themeColors.card.opacity(isLightBackground ? 0.98 : 0.95))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(themeColors.cardBorder, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.25), radius: 20, x: 0, y: 10)
            .frame(maxWidth: 340)
            .padding(.horizontal, 24)
        }
        .animation(.easeInOut(duration: 0.2), value: term.id)
    }
}



