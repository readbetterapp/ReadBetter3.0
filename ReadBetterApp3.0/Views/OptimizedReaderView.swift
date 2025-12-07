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
    
    var color: Color {
        switch self {
        case .none: return .clear
        case .yellow: return Color(red: 254/255, green: 240/255, blue: 138/255) // #fef08a
        case .blue: return Color(red: 147/255, green: 197/255, blue: 253/255) // #93c5fd
        case .green: return Color(red: 134/255, green: 239/255, blue: 172/255) // #86efac
        }
    }
    
    var displayName: String {
        switch self {
        case .none: return "None"
        case .yellow: return "Yellow"
        case .blue: return "Blue"
        case .green: return "Green"
        }
    }
}

// MARK: - Preference Keys for Position Tracking
struct SentencePositionPreferenceKey: PreferenceKey {
    static var defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}

struct ScrollViewHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct OptimizedReaderView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @EnvironmentObject var router: AppRouter
    @Environment(\.dismiss) private var dismiss
    
    let preloadedData: PreloadedReaderData
    
    @StateObject private var karaokeEngine = KaraokeEngine()
    @StateObject private var audioPlayer = OptimizedAudioPlayer()
    
    @State private var currentSentenceIndex: Int = 0
    @State private var displayLink: CADisplayLink?
    @State private var isScrubbing: Bool = false  // Track when user is scrubbing slider
    @State private var sliderValue: Double = 0  // Separate slider value to prevent fighting during scrubbing
    // Scroll proxy and closure storage
    @State private var scrollProxy: ScrollViewProxy? = nil
    @State private var scrollToSentence: ((Int) -> Void)? = nil
    @State private var pendingSeekTime: Double? = nil  // Store target time during scrubbing, apply when scrubbing ends
    @State private var frozenCurrentWordIndex: Int? = nil  // Frozen value for views during scrubbing (prevents re-renders)
    @State private var frozenLastSpokenWordIndex: Int? = nil  // Frozen value for views during scrubbing (prevents re-renders)
    
    // Haptic feedback for word locks
    @State private var hapticGenerator: UIImpactFeedbackGenerator?
    @State private var lastHapticWordIndex: Int? = nil
    
    // Optimization: Cache word-to-sentence mapping for O(1) lookup
    @State private var wordToSentenceMap: [Int: Int] = [:]  // wordIndex -> sentenceIndex
    @State private var lastScrollTime: Date = Date()
    private let scrollThrottleInterval: TimeInterval = 0.15  // Only scroll every 150ms
    
    // Position tracking for long sentences
    @State private var currentSentenceFrame: CGRect = .zero  // Track current sentence position
    @State private var scrollViewHeight: CGFloat = 0  // Track visible scroll view height
    @State private var scrollOffset: CGFloat = 0  // Track scroll offset for proper coordinate calculations
    @State private var lastPositionCheckTime: Date = Date()  // Throttle position checks
    
    // MARK: - Unified Scroll System
    enum ScrollMode {
        case none           // No special mode
        case playing        // Normal playback auto-scroll
        case scrubbing      // User is scrubbing (disable auto-scroll)
        case paused         // Paused (centered scroll allowed)
        case scrubbingEnded // Just finished scrubbing (disable for 1 second)
    }
    
    enum ScrollPriority: Int {
        case low = 1        // Position check for long sentences
        case normal = 2     // Normal sentence change
        case high = 3       // Scrubbing end, pause centering
        case critical = 4   // Emergency (shouldn't happen)
    }
    
    struct ScrollRequest {
        let sentenceIndex: Int
        let priority: ScrollPriority
        let anchor: UnitPoint
        let animated: Bool
        let reason: String  // For debugging
    }
    
    @State private var scrollMode: ScrollMode = .none
    @State private var pendingScrollRequest: ScrollRequest? = nil
    @State private var disableAutoScrollUntil: Date? = nil  // Disable auto-scroll briefly after scrubbing to prevent competing scrolls
    @State private var lastPauseScrollTime: Date? = nil  // Track last pause scroll to prevent duplicates
    
    // Chapter navigation
    var onChapterChange: ((Int) -> Void)?
    
    // Settings state with UserDefaults persistence
    @State private var textSize: TextSize = .medium
    @State private var playbackSpeed: Double = 1.0
    @State private var highlightColor: HighlightColor = .none
    @State private var readerBackgroundColor: ReaderBackgroundColor = .light
    @State private var isMenuExpanded: Bool = true
    @State private var activeSubmenu: SubmenuType? = nil
    @State private var isChapterDropdownOpen: Bool = false  // Track chapter dropdown visibility
    
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
    
    var body: some View {
        ZStack {
            readerColors.background
                .ignoresSafeArea()
                .animation(.easeInOut(duration: 0.4), value: readerBackgroundColor) // Smooth fade transition
            
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
                // Header
                headerView
                    .zIndex(100) // Ensure header is above content
                
                // Text Display
                ScrollViewReader { proxy in
                    ScrollView {
                        // Track scroll view height
                        GeometryReader { scrollGeometry in
                            Color.clear
                                .preference(
                                    key: ScrollViewHeightPreferenceKey.self,
                                    value: scrollGeometry.size.height
                                )
                        }
                        .frame(height: 0)
                        
                        LazyVStack(alignment: .leading, spacing: 20) {
                            ForEach(Array(preloadedData.sentences.enumerated()), id: \.element.id) { index, sentence in
                                OptimizedSentenceView(
                                    sentence: sentence,
                                    sentenceIndex: index,
                                    currentSentenceIndex: currentSentenceIndex,
                                    currentWordIndex: karaokeEngine.currentWordIndex,
                                    lastSpokenWordIndex: karaokeEngine.lastSpokenWordIndex,
                                    themeColors: readerColors,
                                    textSize: textSize.fontSize,
                                    highlightColor: highlightColor,
                                    indexedWords: preloadedData.indexedWords,
                                    onSentenceTap: {
                                        // Tap-to-seek: jump to sentence's start time
                                        let seekTime = sentence.startTime
                                        
                                        audioPlayer.seek(to: seekTime)
                                        Task { @MainActor in
                                            karaokeEngine.resetSearchState()
                                            karaokeEngine.updateTime(seekTime, duration: audioPlayer.duration)
                                            
                                            // Request scroll to tapped sentence
                                            if let proxy = scrollProxy {
                                                requestScroll(
                                                    sentenceIndex: index,
                                                    priority: .high,
                                                    anchor: .top,
                                                    animated: true,
                                                    reason: "Tapped sentence \(index)",
                                                    proxy: proxy
                                                )
                                            }
                                            
                                            hapticGenerator?.impactOccurred(intensity: 0.5)
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
                        .padding(.vertical, 24)
                        .padding(.bottom, 100)
                    }
                    .coordinateSpace(name: "scroll")
                    .scrollIndicators(.hidden)
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
                        
                        // Store scroll closure for compatibility (uses unified system internally)
                        scrollToSentence = { sentenceIndex in
                            if let proxy = scrollProxy {
                                requestScroll(
                                    sentenceIndex: sentenceIndex,
                                    priority: .high,
                                    anchor: .top,
                                    animated: true,
                                    reason: "Scroll closure called",
                                    proxy: proxy
                                )
                            }
                        }
                    }
                    .onPreferenceChange(SentencePositionPreferenceKey.self) { frame in
                        // Only update frame if it's valid and for the current sentence
                        // This prevents false updates from other sentences
                        guard frame != .zero else { return }
                        // CRITICAL FIX: Use DispatchQueue.main.async for stronger deferral - guarantees next runloop tick
                        // Capture proxy explicitly for async closure
                        let capturedProxy = proxy
                        DispatchQueue.main.async {
                            currentSentenceFrame = frame
                            
                            // Trigger position check when frame updates (only if we have a valid word index)
                            // Only check if we're not scrubbing and have a valid word
                            guard !isScrubbing, let wordIndex = karaokeEngine.currentWordIndex else { return }
                            checkAndScrollIfNeeded(proxy: capturedProxy, wordIndex: wordIndex)
                        }
                    }
                    .onPreferenceChange(ScrollViewHeightPreferenceKey.self) { height in
                        // CRITICAL FIX: Use DispatchQueue.main.async for stronger deferral - guarantees next runloop tick
                        DispatchQueue.main.async {
                            scrollViewHeight = height
                        }
                    }
                    .onPreferenceChange(ScrollOffsetPreferenceKey.self) { value in
                        // Track scroll offset for proper coordinate calculations
                        DispatchQueue.main.async {
                            scrollOffset = -value // Invert to get positive scroll down value
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
                            
                            // Trigger haptic feedback when word changes during normal playback
                            if wordIndex != lastHapticWordIndex {
                                hapticGenerator?.impactOccurred(intensity: 0.7)
                                lastHapticWordIndex = wordIndex
                            }
                            
                            // Find sentence for current word using unified scroll system
                            // ALWAYS use time-based lookup for consistency (word-to-sentence map can be wrong)
                            let currentTime = getCurrentAudioTime()
                            guard let sentenceIndex = findSentenceAtTime(currentTime) else {
                                return // No sentence found at this time
                            }
                            
                            // Only scroll if sentence actually changed
                            guard sentenceIndex != currentSentenceIndex else {
                                return // Already on correct sentence
                            }
                            
                            // Request scroll through unified system
                            requestScroll(
                                sentenceIndex: sentenceIndex,
                                priority: .normal,
                                animated: true,
                                reason: "Word changed to \(wordIndex)",
                                proxy: capturedProxy
                            )
                            // NOTE: Position-based scrolling for long sentences is handled by preference change handler
                            // (onPreferenceChange(SentencePositionPreferenceKey)) to avoid double-firing
                        }
                    }
                    .onChange(of: isScrubbing) { oldValue, newValue in
                        // CRITICAL FIX: Use DispatchQueue.main.async for stronger deferral - guarantees next runloop tick
                        DispatchQueue.main.async {
                            if newValue {
                                // Scrubbing started - update mode and prepare haptic
                                scrollMode = .scrubbing
                                hapticGenerator?.prepare()
                            } else {
                                // Scrubbing ended - update mode and reset haptic tracking
                                scrollMode = .scrubbingEnded
                                disableAutoScrollUntil = Date().addingTimeInterval(1.0)
                                lastHapticWordIndex = nil
                                
                                // Reset to playing mode after disable period
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                                    scrollMode = .playing
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
                        }
                    }
                    .onChange(of: audioPlayer.isPlaying) { oldValue, newValue in
                        // Update scroll mode when playback state changes
                        DispatchQueue.main.async {
                            if newValue {
                                // Started playing - set mode to playing (unless scrubbing)
                                if scrollMode != .scrubbing && scrollMode != .scrubbingEnded {
                                    scrollMode = .playing
                                }
                            } else {
                                // Paused - set mode to paused
                                if scrollMode != .scrubbing {
                                    scrollMode = .paused
                                }
                            }
                        }
                    }
                }
                
                // Playback Controls
                playbackControls
            }
            
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
            // Load saved settings from UserDefaults
            loadSettings()
            
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
            karaokeEngine.setAudioTimeGetter { [weak audioPlayer] in
                audioPlayer?.getCurrentTime() ?? 0
            }
            
            // Setup CADisplayLink for 60fps word sync updates (replaces AVPlayer time observer)
            // Use a closure-based target to access view properties
            let target = DisplayLinkTarget { [weak karaokeEngine, weak audioPlayer] in
                Task { @MainActor in
                    guard let engine = karaokeEngine, let player = audioPlayer else { return }
                    let currentTime = player.getCurrentTime()
                    engine.updateTime(currentTime, duration: player.duration)
                }
            }
            
            let newDisplayLink = CADisplayLink(target: target, selector: #selector(DisplayLinkTarget.tick))
            newDisplayLink.preferredFramesPerSecond = 60
            newDisplayLink.add(to: .main, forMode: .common)
            displayLink = newDisplayLink
            
            // Load pre-built data instantly (no computation!)
            karaokeEngine.loadPrebuiltData(
                indexedWords: preloadedData.indexedWords,
                sentences: preloadedData.sentences,
                totalWords: preloadedData.totalWords
            )
            
                // OPTIMIZATION: Reuse preloaded asset if available, otherwise load from URL
            Task {
                if let preloadedAsset = preloadedData.audioAsset {
                    await audioPlayer.load(asset: preloadedAsset, preloadedDuration: preloadedData.audioDuration)
                } else {
                    await audioPlayer.load(url: preloadedData.audioURL, preloadedDuration: preloadedData.audioDuration)
                }
                // Ensure audio doesn't auto-play - explicitly pause FIRST
                audioPlayer.pause()
                // Then apply saved playback speed (won't trigger play since isPlaying is false)
                audioPlayer.setPlaybackSpeed(playbackSpeed)
            }
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
        .onDisappear {
            // Clean up CADisplayLink
            displayLink?.invalidate()
            displayLink = nil
            
            audioPlayer.stop()
            // Clean up timers
            karaokeEngine.reset()
        }
    }
    
    // MARK: - Header
    private var headerView: some View {
        HStack {
            Button(action: {
                audioPlayer.stop()
                // Navigate FIRST to replace ReaderLoadingView in navigation stack
                // This prevents any flash of ReaderLoadingView
                router.replace(with: .bookDetails(bookId: preloadedData.book.id))
                // Then dismiss immediately - now it dismisses to BookDetailsView, not ReaderLoadingView
                dismiss()
            }) {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(readerColors.text)
                    .frame(width: 40, height: 40)
                    .background(readerColors.card)
                    .clipShape(Circle())
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
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(readerColors.text) // Match X button color
                            .frame(width: 32, height: 32)
                            .background(readerColors.card)
                            .clipShape(Circle())
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
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(readerColors.text) // Match X button color
                            .frame(width: 32, height: 32)
                            .background(readerColors.card)
                            .clipShape(Circle())
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
    }
    
    // MARK: - Chapter Navigation
    private func goToPreviousChapter() {
        guard hasPreviousChapter else { return }
        audioPlayer.stop()
        let prevChapterOrder = preloadedData.book.chapters.sorted { $0.order < $1.order }[currentChapterIndex - 1].order
        // Navigate immediately to prevent showing "ready page"
        router.replace(with: .reader(bookId: preloadedData.book.id, chapterNumber: prevChapterOrder + 1))
        dismiss()
    }
    
    private func goToNextChapter() {
        guard hasNextChapter else { return }
        audioPlayer.stop()
        let nextChapterOrder = preloadedData.book.chapters.sorted { $0.order < $1.order }[currentChapterIndex + 1].order
        // Navigate immediately to prevent showing "ready page"
        router.replace(with: .reader(bookId: preloadedData.book.id, chapterNumber: nextChapterOrder + 1))
        dismiss()
    }
    
    private func goToChapter(_ chapterOrder: Int) {
        audioPlayer.stop()
        // Close dropdown
        isChapterDropdownOpen = false
        // Navigate immediately to prevent showing "ready page"
        // This ensures ReaderLoadingView appears right away, no intermediate view flash
        router.replace(with: .reader(bookId: preloadedData.book.id, chapterNumber: chapterOrder + 1))
        dismiss()
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
        .background(readerColors.card)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(readerColors.cardBorder, lineWidth: 1)
        )
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
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                isMenuExpanded = false
                            }
                        }) {
                            Image(systemName: "chevron.down")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(readerColors.text)
                        }
                        Spacer()
                    }
                    .padding(.bottom, 8) // Even spacing above and below (matches spacing: 16 in VStack)
                    
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
                                                    
                                                    // CRITICAL: Reset engine's search state for large jumps to force binary search
                                                    // This prevents slow sequential fast-forward when jumping far ahead
                                                    // Check if this is a large jump (more than 5 seconds difference)
                                                    let timeDifference = abs(targetTime - actualTime)
                                                    if timeDifference > 5.0 {
                                                        karaokeEngine.resetSearchState()
                                                    }
                                                    
                                                    // CRITICAL FIX: Always find the last word that should be marked as spoken
                                                    // This ensures ALL words up to current position are black, not white
                                                    // For large jumps, this is essential to prevent white words and incorrect highlighting
                                                    let indexedWords = karaokeEngine.getIndexedWords()
                                                    var lastSpokenWordIndex: Int? = nil
                                                    var lastSpokenWordEndTime: Double = 0
                                                    
                                                    // Find the last word that ends at or before actual time
                                                    // This marks all words up to current position as spoken
                                                    for word in indexedWords.reversed() {
                                                        if word.end <= actualTime && word.end.isFinite && word.start.isFinite {
                                                            lastSpokenWordIndex = word.id
                                                            lastSpokenWordEndTime = word.end
                                                            break
                                                        }
                                                    }
                                                    
                                                    // CRITICAL FIX: Update to last spoken word's end time FIRST
                                                    // This sets lastSpokenWordIndex correctly for all words up to current position
                                                    // This prevents white words and sentences ahead being highlighted incorrectly
                                                    if let lastSpoken = lastSpokenWordIndex {
                                                        karaokeEngine.updateTime(lastSpokenWordEndTime, duration: duration)
                                                    }
                                                    
                                                    // Now update to actual time to set currentWordIndex correctly
                                                    // This ensures the current word is highlighted correctly
                                                    karaokeEngine.updateTime(actualTime, duration: duration)
                                                    
                                                    // Check for word change and trigger haptic feedback
                                                    if let currentWord = karaokeEngine.currentWordIndex,
                                                       currentWord != lastHapticWordIndex {
                                                        hapticGenerator?.impactOccurred(intensity: 0.7)
                                                        lastHapticWordIndex = currentWord
                                                    }
                                                    
                                                    // Find sentence at scrubbed position and request scroll
                                                    // Use unified scroll system with high priority
                                                    // Use stored scrollProxy since we're in nested Task closure
                                                    if let sentenceIndex = findSentenceAtTime(actualTime),
                                                       let scrollProxy = scrollProxy {
                                                        requestScroll(
                                                            sentenceIndex: sentenceIndex,
                                                            priority: .high,
                                                            anchor: .top,  // Always top after scrubbing
                                                            animated: false,  // Instant scroll
                                                            reason: "Scrubbing ended at \(String(format: "%.2f", actualTime))s",
                                                            proxy: scrollProxy
                                                        )
                                                    }
                                                    
                                                    // Clear pending seek time
                                                    pendingSeekTime = nil
                                                    
                                                    // Sync slider value to actual audio time after seek completes
                                                    sliderValue = actualTime
                                                    
                                                    // CADisplayLink was never paused, so no need to resume
                                                    // Everything is now synchronized to the new position
                                                }
                                            }
                                        }
                                    }
                                )
                                .tint(readerColors.primary) // Thumb color
                                .background(Color.clear) // Transparent background so custom track shows
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
                            let currentTime = audioPlayer.getCurrentTime()
                            guard currentTime.isFinite && currentTime >= 0 else { return }
                            
                            let newTime = max(0, currentTime - 10)
                            audioPlayer.seek(to: newTime)
                            // Reset word sync and trigger update after seek
                            Task { @MainActor in
                                karaokeEngine.resetSearchState()
                                let updatedTime = audioPlayer.getCurrentTime()
                                karaokeEngine.updateTime(updatedTime, duration: audioPlayer.duration)
                                
                                // Update scroll to new position
                                if let sentenceIndex = findSentenceAtTime(updatedTime),
                                   let proxy = scrollProxy {
                                    requestScroll(
                                        sentenceIndex: sentenceIndex,
                                        priority: .high,
                                        anchor: .top,
                                        animated: true,
                                        reason: "Rewind 10s",
                                        proxy: proxy
                                    )
                                }
                            }
                        }) {
                            Image(systemName: "gobackward.10")
                                .font(.system(size: 24))
                                .foregroundColor(readerColors.text)
                        }
                        
                        // Play/Pause
                        Button(action: {
                            let wasPlaying = audioPlayer.isPlaying
                            audioPlayer.togglePlayPause()
                            
                            // CRITICAL FIX: Update word highlighting and centering when pausing OR playing
                            Task { @MainActor in
                                let currentTime = audioPlayer.getCurrentTime()
                                
                                // Always update word highlighting to reflect current position
                                // This ensures highlighting is correct when paused
                                let indexedWords = karaokeEngine.getIndexedWords()
                                var lastSpokenWordIndex: Int? = nil
                                var lastSpokenWordEndTime: Double = 0
                                
                                // Find the last word that ends at or before current time
                                for word in indexedWords.reversed() {
                                    if word.end <= currentTime && word.end.isFinite && word.start.isFinite {
                                        lastSpokenWordIndex = word.id
                                        lastSpokenWordEndTime = word.end
                                        break
                                    }
                                }
                                
                                // Update to last spoken word's end time FIRST to set lastSpokenWordIndex correctly
                                if let lastSpoken = lastSpokenWordIndex {
                                    karaokeEngine.updateTime(lastSpokenWordEndTime, duration: audioPlayer.duration)
                                }
                                
                                // Now update to current time to set currentWordIndex correctly
                                karaokeEngine.updateTime(currentTime, duration: audioPlayer.duration)
                                
                                // Update scroll mode and request scroll if paused
                                if !audioPlayer.isPlaying {
                                    scrollMode = .paused
                                    
                                    // CRITICAL FIX: Only scroll on pause once per pause event
                                    // Prevent multiple scrolls when pause button is tapped multiple times
                                    let now = Date()
                                    if let lastPause = lastPauseScrollTime, now.timeIntervalSince(lastPause) < 0.5 {
                                        // Already scrolled recently on pause, skip
                                        return
                                    }
                                    lastPauseScrollTime = now
                                    
                                    if let sentenceIndex = findSentenceAtTime(currentTime),
                                       let proxy = scrollProxy {
                                        // Request centered scroll when paused
                                        requestScroll(
                                            sentenceIndex: sentenceIndex,
                                            priority: .high,
                                            anchor: .center,  // Center when paused
                                            animated: true,
                                            reason: "Paused at \(String(format: "%.2f", currentTime))s",
                                            proxy: proxy
                                        )
                                    }
                                } else {
                                    scrollMode = .playing
                                    // Clear pause scroll tracking when playing resumes
                                    lastPauseScrollTime = nil
                                }
                            }
                        }) {
                            Circle()
                                .fill(readerColors.primary)
                                .frame(width: 64, height: 64)
                                .overlay {
                                    Image(systemName: audioPlayer.isPlaying ? "pause.fill" : "play.fill")
                                        .font(.system(size: 24, weight: .semibold))
                                        .foregroundColor(readerColors.primaryText)
                                }
                        }
                        
                        // Forward 10s
                        Button(action: {
                            let currentTime = audioPlayer.getCurrentTime()
                            guard currentTime.isFinite && currentTime >= 0 else { return }
                            
                            let newTime = min(audioPlayer.duration, currentTime + 10)
                            audioPlayer.seek(to: newTime)
                            // Reset word sync and trigger update after seek
                            Task { @MainActor in
                                karaokeEngine.resetSearchState()
                                let updatedTime = audioPlayer.getCurrentTime()
                                karaokeEngine.updateTime(updatedTime, duration: audioPlayer.duration)
                                
                                // Update scroll to new position
                                if let sentenceIndex = findSentenceAtTime(updatedTime),
                                   let proxy = scrollProxy {
                                    requestScroll(
                                        sentenceIndex: sentenceIndex,
                                        priority: .high,
                                        anchor: .top,
                                        animated: true,
                                        reason: "Forward 10s",
                                        proxy: proxy
                                    )
                                }
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
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            isMenuExpanded = true
                        }
                    }) {
                        Image(systemName: "chevron.up")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(readerColors.text)
                    }
                    Spacer()
                }
                .padding(.vertical, 8)
            }
        }
        .background(readerColors.card)
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(readerColors.cardBorder),
            alignment: .top
        )
    }
    
    // MARK: - Settings Button Row
    private var settingsButtonRow: some View {
        HStack(spacing: 16) {
            // Playback Speed button
            Button(action: {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    activeSubmenu = .speed
                }
            }) {
                Circle()
                    .fill(readerColors.card)
                    .frame(width: 44, height: 44)
                    .overlay {
                        Image(systemName: "speedometer")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(readerColors.text)
                    }
            }
            
            // Text Size button
            Button(action: {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    activeSubmenu = .textSize
                }
            }) {
                Circle()
                    .fill(readerColors.card)
                    .frame(width: 44, height: 44)
                    .overlay {
                        Image(systemName: "textformat.size")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(readerColors.text)
                    }
            }
            
            // Highlight Color button
            Button(action: {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    activeSubmenu = .highlight
                }
            }) {
                Circle()
                    .fill(readerColors.card)
                    .frame(width: 44, height: 44)
                    .overlay {
                        Image(systemName: "paintbrush.fill")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(highlightColor == .none ? readerColors.text : highlightColor.color)
                    }
            }
            
            // Background Color button
            Button(action: {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    activeSubmenu = .background
                }
            }) {
                Circle()
                    .fill(readerColors.card)
                    .frame(width: 44, height: 44)
                    .overlay {
                        Image(systemName: "paintpalette.fill")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(readerColors.text) // Always use text color for visibility
                    }
                    .overlay(alignment: .topTrailing) {
                        // Small color indicator circle in corner
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
                Circle()
                    .fill(readerColors.card)
                    .frame(width: 44, height: 44)
                    .overlay {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(readerColors.text)
                    }
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
                    Circle()
                        .fill(playbackSpeed == speed ? readerColors.primary : readerColors.card)
                        .frame(width: 44, height: 44)
                        .overlay {
                            Text(String(format: "%.2fx", speed))
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(playbackSpeed == speed ? readerColors.primaryText : readerColors.text)
                        }
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
                    Circle()
                        .fill(textSize == size ? readerColors.primary : readerColors.card)
                        .frame(width: 44, height: 44)
                        .overlay {
                            Text(size.rawValue)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(textSize == size ? readerColors.primaryText : readerColors.text)
                        }
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
                    Circle()
                        .fill(highlightColor == color ? readerColors.primary : readerColors.card)
                        .frame(width: 44, height: 44)
                        .overlay {
                            if color == .none {
                                Image(systemName: "xmark")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(highlightColor == color ? readerColors.primaryText : readerColors.text)
                            } else {
                                Circle()
                                    .fill(color.color)
                                    .frame(width: 24, height: 24)
                            }
                        }
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
                        .fill(Color.white) // Always use white background for visibility
                        .frame(width: 44, height: 44)
                        .overlay {
                            // Show the actual color in a circle
                            Circle()
                                .fill(color.color)
                                .frame(width: 28, height: 28)
                                .overlay {
                                    // Add border if selected
                                    if readerBackgroundColor == color {
                                        Circle()
                                            .stroke(readerColors.primary, lineWidth: 2)
                                    }
                                }
                        }
                }
            }
        }
    }
    
    // MARK: - Check Position and Scroll if Needed (for long sentences)
    private func checkAndScrollIfNeeded(proxy: ScrollViewProxy, wordIndex: Int?) {
        guard let wordIndex = wordIndex else {
            return
        }
        
        // Use time-based lookup to find sentence (more reliable than word-to-sentence map)
        let currentTime = getCurrentAudioTime()
        guard let sentenceIndex = findSentenceAtTime(currentTime),
              sentenceIndex == currentSentenceIndex else {
            return  // Only check position for current sentence
        }
        
        // Prevent scrolling during sentence transitions
        guard !isScrubbing else { return }
        
        // Validate that we have valid frame data
        guard currentSentenceFrame != .zero else { return }
        
        // Throttle position checks (reduced to 100ms for more responsive scrolling)
        let now = Date()
        guard now.timeIntervalSince(lastPositionCheckTime) >= 0.1 else {
            return
        }
        
        // CRITICAL FIX: Use DispatchQueue.main.async for stronger deferral - guarantees next runloop tick
        // Capture proxy explicitly for async closure
        let capturedProxy = proxy
        DispatchQueue.main.async {
            lastPositionCheckTime = now
            
            // Calculate menu height based on state
            // Adjust these values based on your actual menu heights
            let menuHeight: CGFloat = isMenuExpanded ? 200 : 60
            let headerHeight: CGFloat = 64  // Header height
            
            // Calculate visible area (screen height minus menu)
            let visibleHeight = scrollViewHeight > 0 ? scrollViewHeight : UIScreen.main.bounds.height
            guard visibleHeight > 0 else { return }  // Ensure we have valid height
            
            let availableHeight = visibleHeight - menuHeight
            
            // Calculate sentence position
            let sentenceBottom = currentSentenceFrame.maxY
            let sentenceTop = currentSentenceFrame.minY
            let sentenceHeight = sentenceBottom - sentenceTop
            
            // Validate sentence frame is reasonable
            guard sentenceBottom > sentenceTop, sentenceBottom > 0 else { return }
            
            let scrollThreshold: CGFloat = 100  // Threshold for earlier activation
            var shouldScroll = false
            var scrollAnchor: UnitPoint = .top
            
            // CRITICAL FIX: Now we have scroll offset, we can properly calculate visible position
            // The frame from .named("scroll") gives position in content space
            // We convert to screen space using: screenY = contentY - scrollOffset
            
            // Calculate sentence position in screen/visible coordinates
            let sentenceTopOnScreen = sentenceTop - scrollOffset
            let sentenceBottomOnScreen = sentenceBottom - scrollOffset
            
            // PRIORITY 1: If sentence is taller than available height, always keep top visible
            // This handles very long sentences that extend beyond the screen
            if sentenceHeight > availableHeight {
                // Sentence is taller than visible area - ensure top stays visible
                if sentenceTopOnScreen < headerHeight || sentenceTopOnScreen > availableHeight {
                    shouldScroll = true
                    scrollAnchor = .top
                }
                // Also check if bottom is getting cut off by menu
                else if sentenceBottomOnScreen > availableHeight - scrollThreshold {
                    shouldScroll = true
                    scrollAnchor = .top
                }
            }
            // PRIORITY 2: Sentence starts above the visible area (out of view at top)
            else if sentenceTopOnScreen < headerHeight {
                shouldScroll = true
                scrollAnchor = .top  // Scroll to show sentence start
            }
            // PRIORITY 3: Sentence starts below the visible area (out of view at bottom)
            else if sentenceTopOnScreen > availableHeight {
                shouldScroll = true
                scrollAnchor = .top  // Scroll to show sentence start
            }
            // PRIORITY 4: Sentence bottom is getting close to menu (within threshold)
            else if sentenceBottomOnScreen > availableHeight - scrollThreshold && sentenceTopOnScreen < availableHeight {
                shouldScroll = true
                scrollAnchor = .top
            }
            
            if shouldScroll {
                // Request scroll through unified system with low priority
                // This ensures normal sentence changes take precedence
                requestScroll(
                    sentenceIndex: sentenceIndex,
                    priority: .low,
                    anchor: scrollAnchor,
                    animated: true,
                    reason: "Long sentence position check",
                    proxy: capturedProxy
                )
            }
        }
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
    
    // MARK: - Unified Scroll System
    
    /// Request a scroll through the unified scroll system
    /// All scroll requests go through this function to prevent conflicts
    private func requestScroll(
        sentenceIndex: Int,
        priority: ScrollPriority,
        anchor: UnitPoint? = nil,
        animated: Bool = true,
        reason: String,
        proxy: ScrollViewProxy
    ) {
        // Validate sentence index
        guard sentenceIndex >= 0 && sentenceIndex < preloadedData.sentences.count else {
            print("⚠️ Scroll request denied: Invalid sentence index \(sentenceIndex)")
            return
        }
        
        // Check if scrolling is allowed
        guard shouldAllowScroll() else {
            print("🚫 Scroll denied: \(reason) - mode: \(scrollMode)")
            return
        }
        
        // Check throttle
        guard shouldThrottleScroll() else {
            print("⏸️ Scroll throttled: \(reason)")
            return
        }
        
        // Determine anchor if not provided
        let scrollAnchor = anchor ?? determineAnchor(for: scrollMode)
        
        // Create request
        let request = ScrollRequest(
            sentenceIndex: sentenceIndex,
            priority: priority,
            anchor: scrollAnchor,
            animated: animated,
            reason: reason
        )
        
        // Process request
        processScrollRequest(request, proxy: proxy)
    }
    
    /// Check if scrolling is currently allowed based on mode and disable flags
    private func shouldAllowScroll() -> Bool {
        // Check disableAutoScrollUntil first
        if let disableUntil = disableAutoScrollUntil, Date() < disableUntil {
            return false
        }
        
        // Then check mode
        switch scrollMode {
        case .none, .playing, .paused:
            return true
        case .scrubbing, .scrubbingEnded:
            return false
        }
    }
    
    /// Check if scroll should be throttled (rate limiting)
    private func shouldThrottleScroll() -> Bool {
        let now = Date()
        let timeSinceLastScroll = now.timeIntervalSince(lastScrollTime)
        return timeSinceLastScroll >= scrollThrottleInterval
    }
    
    /// Determine scroll anchor based on current mode
    private func determineAnchor(for mode: ScrollMode) -> UnitPoint {
        switch mode {
        case .playing, .none, .scrubbing, .scrubbingEnded:
            return UnitPoint(x: 0.5, y: 0.0)  // Top anchor (consistent position for playback)
        case .paused:
            return UnitPoint(x: 0.5, y: 0.5)  // Center anchor when paused
        }
    }
    
    /// Process scroll request with priority system
    private func processScrollRequest(_ request: ScrollRequest, proxy: ScrollViewProxy) {
        // If there's a pending request, compare priorities
        if let pending = pendingScrollRequest {
            if request.priority.rawValue > pending.priority.rawValue {
                // New request has higher priority, replace
                print("🔄 Replacing pending scroll (\(pending.reason)) with higher priority (\(request.reason))")
                pendingScrollRequest = request
                executeScroll(request, proxy: proxy)
            } else {
                // Pending has higher or equal priority, ignore new request
                print("⏭️ Ignoring scroll request (\(request.reason)) - pending (\(pending.reason)) has higher/equal priority")
            }
            return
        }
        
        // No pending request, execute immediately
        pendingScrollRequest = request
        executeScroll(request, proxy: proxy)
    }
    
    /// Execute the scroll request
    private func executeScroll(_ request: ScrollRequest, proxy: ScrollViewProxy) {
        // Update state
        currentSentenceIndex = request.sentenceIndex
        lastScrollTime = Date()
        pendingScrollRequest = nil
        
        // Execute scroll
        let scrollID = "\(request.sentenceIndex)-\(readerBackgroundColor.rawValue)"
        
        // Debug: Show anchor in readable format
        let anchorDesc = request.anchor == UnitPoint(x: 0.5, y: 0.0) ? "top" : 
                        request.anchor == UnitPoint(x: 0.5, y: 0.5) ? "center" : 
                        "\(request.anchor)"
        print("📍 Executing scroll: \(request.reason) - sentence \(request.sentenceIndex), anchor: \(anchorDesc)")
        
        if request.animated {
            withAnimation(.easeInOut(duration: 0.3)) {
                proxy.scrollTo(scrollID, anchor: request.anchor)
            }
        } else {
            proxy.scrollTo(scrollID, anchor: request.anchor)
        }
    }
    
    // MARK: - Helper Methods
    
    /// Get current audio time safely (validates finite and positive)
    private func getCurrentAudioTime() -> Double {
        let time = audioPlayer.getCurrentTime()
        guard time.isFinite && time >= 0 else { return 0 }
        return time
    }
    
    // MARK: - Format Time
    private func formatTime(_ seconds: Double) -> String {
        guard !seconds.isNaN && !seconds.isInfinite else { return "0:00" }
        let totalSeconds = Int(seconds)
        let minutes = totalSeconds / 60
        let secs = totalSeconds % 60
        return String(format: "%d:%02d", minutes, secs)
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
    let currentSentenceIndex: Int
    let currentWordIndex: Int?
    let lastSpokenWordIndex: Int?
    let themeColors: ThemeColors
    let textSize: CGFloat
    let highlightColor: HighlightColor
    let indexedWords: [IndexedWord]
    let onSentenceTap: () -> Void
    
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
    
    var body: some View {
        // Use AttributedString for reliable text display, but build it efficiently
        Text(buildAttributedString())
            .lineSpacing(textSize * 0.4) // Proportional line spacing (8pt for 20pt = 0.4 ratio)
            .fixedSize(horizontal: false, vertical: true)
            .opacity(isFinishedSentence ? 0.5 : 1.0) // Apply 50% opacity to finished sentences
            .contentShape(Rectangle()) // Make entire text area tappable
            .onTapGesture {
                // Tap-to-seek: jump to sentence start
                onSentenceTap()
            }
            .onAppear {
                // Build base string once on first appearance
                let currentThemeHash = themeColors.text.hashValue
                if baseAttributedString == nil || cachedTextSize != textSize || cachedThemeColorHash != currentThemeHash {
                    buildBaseAttributedString()
                    cachedTextSize = textSize
                    cachedThemeColorHash = currentThemeHash
                }
            }
            .onChange(of: textSize) { oldValue, newValue in
                // CRITICAL FIX: Defer state modifications to avoid "modifying state during view update" warning
                Task { @MainActor in
                    // Invalidate cache when text size changes
                    baseAttributedString = nil
                    cachedTextSize = newValue
                    buildBaseAttributedString()
                }
            }
            .onChange(of: themeColors.text) { oldValue, newValue in
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
        
        // Apply word colors efficiently
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
        }
        
        // Apply continuous highlight background for spoken/current words (includes punctuation)
        // Get highlight ranges to check punctuation
        var highlightRanges: [Range<Int>] = []
        if highlightColor != .none {
            highlightRanges = applyContinuousHighlight(to: &attributed, text: text, sortedRanges: sortedRanges)
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
                
                // Find the word before this position
                let wordBefore = sortedRanges.last { wordRange in
                    let wordEnd = text.distance(from: text.startIndex, to: wordRange.range.upperBound)
                    return wordEnd <= index
                }
                
                // Check if punctuation is within a highlight range
                let isInHighlight = highlightRanges.contains { $0.contains(index) }
                
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
        // Two views are "equal" (don't need re-render) if:
        // 1. Same sentence
        // 2. Same sentence index and current sentence index (for finished sentence check)
        // 3. Same current word index
        // 4. Same last spoken word index
        // 5. Same text size
        // 6. Same highlight color
        // This allows SwiftUI to skip re-rendering sentences that haven't actually changed
        return lhs.sentence.id == rhs.sentence.id &&
               lhs.sentenceIndex == rhs.sentenceIndex &&
               lhs.currentSentenceIndex == rhs.currentSentenceIndex &&
               lhs.currentWordIndex == rhs.currentWordIndex &&
               lhs.lastSpokenWordIndex == rhs.lastSpokenWordIndex &&
               lhs.textSize == rhs.textSize &&
               lhs.highlightColor == rhs.highlightColor
    }
}

// MARK: - Optimized Audio Player
class OptimizedAudioPlayer: ObservableObject {
    @Published var isPlaying = false
    @Published var currentTime: Double = 0
    @Published var duration: Double = 0
    @Published var isLoading = false
    @Published var playbackSpeed: Double = 1.0
    
    var onTimeUpdate: ((Double, Double) -> Void)?
    
    private var player: AVPlayer?
    private var timeObserver: Any?
    private var durationObserver: NSKeyValueObservation?
    
    // Progress bar updates only (throttled to 10fps)
    // Word sync is now handled by CADisplayLink at 60fps
    private let progressUpdateInterval: Double = 0.1 // 10fps for progress bar only
    
    // OPTIMIZATION: Support loading from preloaded asset
    func load(asset: AVURLAsset, preloadedDuration: Double? = nil) async {
        await MainActor.run {
            isLoading = true
            // Use preloaded duration if available (instant!)
            if let preloadedDuration = preloadedDuration, preloadedDuration > 0 {
                self.duration = preloadedDuration
            }
        }
        
        let playerItem = AVPlayerItem(asset: asset)
        let newPlayer = AVPlayer(playerItem: playerItem)
        
        await setupPlayerObservers(player: newPlayer, playerItem: playerItem)
    }
    
    func load(url: URL, preloadedDuration: Double? = nil) async {
        await MainActor.run {
            isLoading = true
            // Use preloaded duration if available (instant!)
            if let preloadedDuration = preloadedDuration, preloadedDuration > 0 {
                self.duration = preloadedDuration
            }
        }
        
        let playerItem = AVPlayerItem(url: url)
        let newPlayer = AVPlayer(playerItem: playerItem)
        
        await setupPlayerObservers(player: newPlayer, playerItem: playerItem)
    }
    
    private func setupPlayerObservers(player: AVPlayer, playerItem: AVPlayerItem) async {
        
        // Observe errors to catch playback issues
        NotificationCenter.default.addObserver(
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
        NotificationCenter.default.addObserver(
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
            
            // Remove old time observer
            if let observer = timeObserver {
                self.player?.removeTimeObserver(observer)
            }
            
            // Low-frequency time observer for progress bar updates only (10fps)
            // Word sync is now handled by CADisplayLink at 60fps in OptimizedReaderView
            let interval = CMTime(seconds: progressUpdateInterval, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
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
                
                // Update progress bar only (word sync handled by CADisplayLink)
                self.currentTime = currentTime
                // Note: onTimeUpdate callback removed - CADisplayLink handles word sync now
            }
        }
    }
    
    func play() {
        // Apply playback speed before playing
        player?.rate = Float(playbackSpeed)
        player?.play()
        isPlaying = true
    }
    
    func pause() {
        player?.pause()
        isPlaying = false
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
                    continuation.resume(returning: actualTime)
                }
            )
        }
    }
    
    func stop() {
        pause()
        seek(to: 0)
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
    
    deinit {
        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
        }
        durationObserver?.invalidate()
        NotificationCenter.default.removeObserver(self)
    }
}

// MARK: - DisplayLink Target Helper
private class DisplayLinkTarget: NSObject {
    private let callback: () -> Void
    
    init(callback: @escaping () -> Void) {
        self.callback = callback
        super.init()
    }
    
    @objc func tick() {
        self.callback() // Explicitly use self to avoid warning
    }
}


