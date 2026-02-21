//
//  MiniPlayerView.swift
//  ReadBetterApp3.0
//
//  Mini player component for background audio playback control.
//  Displays in two modes: expanded (floating above tab bar) and collapsed (inline with tab bar).
//

import SwiftUI
import Kingfisher

// MARK: - Animation Namespace for Spotify-style expand/collapse
struct MiniPlayerAnimationNamespace {
    static let coverArtID = "miniPlayerCoverArt"
}

// MARK: - Helper Extension for Optional Matched Geometry
extension View {
    @ViewBuilder
    func applyMatchedGeometry(id: String, namespace: Namespace.ID?) -> some View {
        if let namespace = namespace {
            self.matchedGeometryEffect(id: id, in: namespace)
        } else {
            self
        }
    }
}

// MARK: - Mini Player View
struct MiniPlayerView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @ObservedObject var audioPlayer = OptimizedAudioPlayer.shared
    
    let isCollapsed: Bool
    let onTap: () -> Void
    var animationNamespace: Namespace.ID?
    
    var body: some View {
        if isCollapsed {
            MiniPlayerCollapsed(audioPlayer: audioPlayer, onTap: onTap, animationNamespace: animationNamespace)
        } else {
            MiniPlayerExpanded(audioPlayer: audioPlayer, onTap: onTap, animationNamespace: animationNamespace)
        }
    }
}

// MARK: - Mini Player Accessory Content (iOS 26+ tabViewBottomAccessory)
// This view always renders content to support native tab bar collapse behavior
// Like Apple Music, it shows "Not Playing" when no audio is active
@available(iOS 26.0, *)
struct MiniPlayerAccessoryContent: View {
    @EnvironmentObject var themeManager: ThemeManager
    @ObservedObject var audioPlayer: OptimizedAudioPlayer
    @Environment(\.tabViewBottomAccessoryPlacement) private var accessoryPlacement
    let showContent: Bool // Whether to show content (false on pushed views)
    let onTap: () -> Void
    
    private var hasActiveContent: Bool {
        audioPlayer.hasDisplayableSession
    }
    
    var body: some View {
        // Only show accessory when at tab root
        if showContent {
            // Adapt UI based on whether tab bar is expanded or collapsed
            switch accessoryPlacement {
            case .expanded:
                expandedView
            case .inline:
                inlineView
            @unknown default:
                expandedView
            }
        }
    }
    
    // Full mini player when tab bar is expanded
    private var expandedView: some View {
        ZStack {
            // Blurred background cover (softer than Continue Reading)
            if hasActiveContent, let coverURL = audioPlayer.coverURL {
                KFImage(coverURL)
                    .cacheOriginalImage()
                    .fade(duration: 0.2)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .blur(radius: 40)
                    .opacity(0.15)
            }
            
            // Tap area for expanding reader (entire background)
            if hasActiveContent {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        onTap()
                    }
            }
            
            // Content
            HStack(spacing: 12) {
                // Music note icon or book cover
                Button(action: { if hasActiveContent { onTap() } }) {
                    if hasActiveContent, let coverURL = audioPlayer.coverURL {
                        KFImage(coverURL)
                            .placeholder { coverPlaceholder }
                            .cacheOriginalImage()
                            .fade(duration: 0.2)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 44, height: 44)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    } else {
                        // "Not Playing" state - show music note like Apple Music
                        RoundedRectangle(cornerRadius: 8)
                            .fill(themeManager.colors.card)
                            .frame(width: 44, height: 44)
                            .overlay {
                                Image(systemName: "music.note")
                                    .font(.system(size: 20))
                                    .foregroundColor(themeManager.colors.textSecondary)
                            }
                    }
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(!hasActiveContent)
                
                // Title - either book info or "Not Playing"
                Button(action: { if hasActiveContent { onTap() } }) {
                    VStack(alignment: .leading, spacing: 2) {
                        if hasActiveContent {
                            Text(audioPlayer.chapterTitle)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(themeManager.colors.text)
                                .lineLimit(1)
                            
                            Text(audioPlayer.bookTitle)
                                .font(.system(size: 12))
                                .foregroundColor(themeManager.colors.textSecondary)
                                .lineLimit(1)
                        } else {
                            Text("Not Playing")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(themeManager.colors.textSecondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(!hasActiveContent)
                
                // Play/Pause button
                Button(action: {
                    if hasActiveContent {
                        audioPlayer.togglePlayPause()
                    }
                }) {
                    Image(systemName: audioPlayer.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(hasActiveContent ? themeManager.colors.text : themeManager.colors.textSecondary)
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(!hasActiveContent)
                
                // Forward button - skip 15 seconds
                Button(action: {
                    if hasActiveContent {
                        audioPlayer.seek(to: audioPlayer.currentTime + 15)
                    }
                }) {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(hasActiveContent ? themeManager.colors.text : themeManager.colors.textSecondary)
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(!hasActiveContent)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }
    
    // Compact mini player when tab bar is collapsed/inline
    private var inlineView: some View {
        ZStack {
            // Blurred background cover (very soft)
            if hasActiveContent, let coverURL = audioPlayer.coverURL {
                KFImage(coverURL)
                    .cacheOriginalImage()
                    .fade(duration: 0.2)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .blur(radius: 45)
                    .opacity(0.1)
            }
            
            // Tap area for expanding reader (entire background)
            if hasActiveContent {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        onTap()
                    }
            }
            
            // Content
            HStack(spacing: 12) {
                // Cover art (left side, tappable to expand)
                Button(action: { if hasActiveContent { onTap() } }) {
                    if hasActiveContent, let coverURL = audioPlayer.coverURL {
                        KFImage(coverURL)
                            .placeholder { coverPlaceholder }
                            .cacheOriginalImage()
                            .fade(duration: 0.2)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 36, height: 36)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    } else {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(themeManager.colors.card)
                            .frame(width: 36, height: 36)
                            .overlay {
                                Image(systemName: "music.note")
                                    .font(.system(size: 16))
                                    .foregroundColor(themeManager.colors.textSecondary)
                            }
                    }
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(!hasActiveContent)
                
                // Chapter title (middle, tappable to expand, truncates with ...)
                Button(action: { if hasActiveContent { onTap() } }) {
                    if hasActiveContent {
                        Text(audioPlayer.chapterTitle)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(themeManager.colors.text)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    } else {
                        Text("Not Playing")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(themeManager.colors.textSecondary)
                    }
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(!hasActiveContent)
                .frame(maxWidth: .infinity, alignment: .leading)
                
                // Playback controls (right side)
                HStack(spacing: 8) {
                    // Play/Pause button (compact)
                    Button(action: {
                        if hasActiveContent {
                            audioPlayer.togglePlayPause()
                        }
                    }) {
                        Image(systemName: audioPlayer.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(hasActiveContent ? themeManager.colors.text : themeManager.colors.textSecondary)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .disabled(!hasActiveContent)
                    
                    // Forward button (compact)
                    Button(action: {
                        if hasActiveContent {
                            audioPlayer.seek(to: audioPlayer.currentTime + 15)
                        }
                    }) {
                        Image(systemName: "forward.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(hasActiveContent ? themeManager.colors.text : themeManager.colors.textSecondary)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .disabled(!hasActiveContent)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
    }
    
    private var coverPlaceholder: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(themeManager.colors.cardBorder)
            .overlay {
                Image(systemName: "book.fill")
                    .font(.system(size: 18))
                    .foregroundColor(themeManager.colors.textSecondary)
            }
    }
}

// MARK: - Native Mini Player Accessory (iOS 26+ tabViewBottomAccessory)
@available(iOS 26.0, *)
struct NativeMiniPlayerAccessory: View {
    @EnvironmentObject var themeManager: ThemeManager
    @ObservedObject var audioPlayer: OptimizedAudioPlayer
    let onTap: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            // Book cover
            Button(action: onTap) {
                if let coverURL = audioPlayer.coverURL {
                    KFImage(coverURL)
                        .placeholder { coverPlaceholder }
                        .cacheOriginalImage()
                        .fade(duration: 0.2)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 44, height: 44)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    coverPlaceholder
                        .frame(width: 44, height: 44)
                }
            }
            .buttonStyle(PlainButtonStyle())
            
            // Title and subtitle
            Button(action: onTap) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(audioPlayer.chapterTitle)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(themeManager.colors.text)
                        .lineLimit(1)
                    
                    Text(audioPlayer.bookTitle)
                        .font(.system(size: 12))
                        .foregroundColor(themeManager.colors.textSecondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(PlainButtonStyle())
            
            // Play/Pause button
            Button(action: {
                audioPlayer.togglePlayPause()
            }) {
                Image(systemName: audioPlayer.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(themeManager.colors.text)
            }
            .buttonStyle(PlainButtonStyle())
            
            // Forward button - skip 15 seconds
            Button(action: {
                audioPlayer.seek(to: audioPlayer.currentTime + 15)
            }) {
                Image(systemName: "forward.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(themeManager.colors.text)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
    
    private var coverPlaceholder: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(themeManager.colors.cardBorder)
            .overlay {
                Image(systemName: "book.fill")
                    .font(.system(size: 18))
                    .foregroundColor(themeManager.colors.textSecondary)
            }
    }
}

// MARK: - Expanded Mini Player (Floating above tab bar)
struct MiniPlayerExpanded: View {
    @EnvironmentObject var themeManager: ThemeManager
    @ObservedObject var audioPlayer: OptimizedAudioPlayer
    let onTap: () -> Void
    var animationNamespace: Namespace.ID?
    
    private var glassTintColor: Color {
        themeManager.isDarkMode 
            ? Color(white: 0.3).opacity(0.4) // Uniform mid-grey for dark mode
            : Color(white: 0.5).opacity(0.3) // Subtle grey for light mode
    }
    
    private var miniPlayerContent: some View {
        VStack(spacing: 0) {
            // Main content
            HStack(spacing: 12) {
                // Book cover with matched geometry for Spotify-style animation
                Group {
                if let coverURL = audioPlayer.coverURL {
                    KFImage(coverURL)
                        .placeholder { coverPlaceholder }
                        .cacheOriginalImage()
                        .fade(duration: 0.2)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 48, height: 48)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    coverPlaceholder
                        .frame(width: 48, height: 48)
                }
                }
                .applyMatchedGeometry(id: MiniPlayerAnimationNamespace.coverArtID, namespace: animationNamespace)
                
                // Title and subtitle
                VStack(alignment: .leading, spacing: 2) {
                    Text(audioPlayer.chapterTitle)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(themeManager.colors.text)
                        .lineLimit(1)
                    
                    Text(audioPlayer.bookTitle)
                        .font(.system(size: 12))
                        .foregroundColor(themeManager.colors.textSecondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
                // Play/Pause button
                Button(action: {
                    audioPlayer.togglePlayPause()
                }) {
                    Circle()
                        .fill(themeManager.colors.primary)
                        .frame(width: 40, height: 40)
                        .overlay {
                            Image(systemName: audioPlayer.isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(themeManager.colors.primaryText)
                                .offset(x: audioPlayer.isPlaying ? 0 : 2) // Visual centering for play icon
                        }
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            
            // Progress bar - with padding to stay inside rounded corners
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background track
                    Capsule()
                        .fill(themeManager.colors.cardBorder)
                        .frame(height: 3)
                    
                    // Progress track
                    Capsule()
                        .fill(themeManager.colors.primary)
                        .frame(width: max(3, geometry.size.width * progressPercent), height: 3)
                }
            }
            .frame(height: 3)
            .padding(.horizontal, 16)
            .padding(.bottom, 10)
        }
    }
    
    var body: some View {
        Group {
            if #available(iOS 26.0, *) {
                // iOS 26+ Liquid Glass effect
                miniPlayerContent
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .glassEffect(.regular.tint(glassTintColor), in: RoundedRectangle(cornerRadius: 16))
            } else {
                // Fallback for iOS 25 and earlier
                miniPlayerContent
                    .background(
                        GlassMorphicBackground()
                            .environmentObject(themeManager)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(
                                themeManager.isDarkMode
                                    ? Color.white.opacity(0.2)
                                    : Color.white.opacity(0.6),
                                lineWidth: 1
                            )
                    )
            }
        }
        .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
        .contentShape(Rectangle())
        .onTapGesture {
            onTap()
        }
    }
    
    private var progressPercent: CGFloat {
        guard audioPlayer.duration > 0 else { return 0 }
        return CGFloat(audioPlayer.currentTime / audioPlayer.duration)
    }
    
    private var coverPlaceholder: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(themeManager.colors.cardBorder)
            .overlay {
                Image(systemName: "book.fill")
                    .font(.system(size: 20))
                    .foregroundColor(themeManager.colors.textSecondary)
            }
    }
}

// MARK: - Collapsed Mini Player (Inline with Home icon) - Used inside tab bar container
struct MiniPlayerCollapsed: View {
    @EnvironmentObject var themeManager: ThemeManager
    @ObservedObject var audioPlayer: OptimizedAudioPlayer
    let onTap: () -> Void
    var animationNamespace: Namespace.ID?
    
    var body: some View {
        HStack(spacing: 8) {
            // Small book cover (tappable to open reader) with matched geometry
            Button(action: onTap) {
                Group {
                if let coverURL = audioPlayer.coverURL {
                    KFImage(coverURL)
                        .placeholder { coverPlaceholder }
                        .cacheOriginalImage()
                        .fade(duration: 0.2)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 40, height: 40)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    coverPlaceholder
                        .frame(width: 40, height: 40)
                }
                }
                .applyMatchedGeometry(id: MiniPlayerAnimationNamespace.coverArtID, namespace: animationNamespace)
            }
            .buttonStyle(PlainButtonStyle())
            
            // Play/Pause button
            Button(action: {
                audioPlayer.togglePlayPause()
            }) {
                Circle()
                    .fill(themeManager.colors.primary)
                    .frame(width: 36, height: 36)
                    .overlay {
                        Image(systemName: audioPlayer.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(themeManager.colors.primaryText)
                            .offset(x: audioPlayer.isPlaying ? 0 : 1) // Visual centering for play icon
                    }
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 10)
    }
    
    private var coverPlaceholder: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(themeManager.colors.cardBorder)
            .overlay {
                Image(systemName: "book.fill")
                    .font(.system(size: 16))
                    .foregroundColor(themeManager.colors.textSecondary)
            }
    }
}

// MARK: - Collapsed Mini Player Bubble (Separate glass container between Home and Search)
struct MiniPlayerCollapsedBubble: View {
    @EnvironmentObject var themeManager: ThemeManager
    @ObservedObject var audioPlayer: OptimizedAudioPlayer
    let onTap: () -> Void
    var animationNamespace: Namespace.ID?
    
    private var glassTintColor: Color {
        themeManager.isDarkMode 
            ? Color(white: 0.3).opacity(0.4) // Uniform mid-grey for dark mode
            : Color(white: 0.5).opacity(0.3) // Subtle grey for light mode
    }
    
    private var bubbleContent: some View {
        HStack(spacing: 10) {
            // Small book cover (tappable to open reader) with matched geometry
            Button(action: onTap) {
                Group {
                if let coverURL = audioPlayer.coverURL {
                    KFImage(coverURL)
                        .placeholder { coverPlaceholder }
                        .cacheOriginalImage()
                        .fade(duration: 0.2)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 44, height: 44)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                } else {
                    coverPlaceholder
                        .frame(width: 44, height: 44)
                }
                }
                .applyMatchedGeometry(id: MiniPlayerAnimationNamespace.coverArtID, namespace: animationNamespace)
            }
            .buttonStyle(PlainButtonStyle())
            
            Spacer() // Push play button to the right
            
            // Play/Pause button
            Button(action: {
                audioPlayer.togglePlayPause()
            }) {
                Circle()
                    .fill(themeManager.colors.primary)
                    .frame(width: 40, height: 40)
                    .overlay {
                        Image(systemName: audioPlayer.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(themeManager.colors.primaryText)
                            .offset(x: audioPlayer.isPlaying ? 0 : 1) // Visual centering for play icon
                    }
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
    
    var body: some View {
        Group {
            if #available(iOS 26.0, *) {
                // iOS 26+ Liquid Glass effect
                bubbleContent
                    .frame(maxWidth: .infinity, maxHeight: 76)
                    .glassEffect(.regular.tint(glassTintColor), in: RoundedRectangle(cornerRadius: 38))
            } else {
                // Fallback for iOS 25 and earlier
                GlassMorphicView {
                    bubbleContent
                }
                .frame(maxWidth: .infinity, maxHeight: 76)
            }
        }
    }
    
    private var coverPlaceholder: some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(themeManager.colors.cardBorder)
            .overlay {
                Image(systemName: "book.fill")
                    .font(.system(size: 18))
                    .foregroundColor(themeManager.colors.textSecondary)
            }
    }
}

// MARK: - Glass Morphic Background (Reusable)
struct GlassMorphicBackground: View {
    @EnvironmentObject var themeManager: ThemeManager
    
    var body: some View {
        ZStack {
            // Background with blur
            RoundedRectangle(cornerRadius: 16)
                .fill(themeManager.isDarkMode
                    ? Color.black.opacity(0.3)
                    : Color.white.opacity(0.08))
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
            
            // Gradient overlay
            RoundedRectangle(cornerRadius: 16)
                .fill(
                    LinearGradient(
                        colors: gradientColors,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .padding(2)
        }
    }
    
    private var gradientColors: [Color] {
        if themeManager.isDarkMode {
            return [
                Color.white.opacity(0.1),
                Color.white.opacity(0.05),
                Color.white.opacity(0.02),
                Color.black.opacity(0.3)
            ]
        } else {
            return [
                Color.white.opacity(0.3),
                Color.white.opacity(0.1),
                Color.white.opacity(0.05),
                Color.black.opacity(0.1)
            ]
        }
    }
}

