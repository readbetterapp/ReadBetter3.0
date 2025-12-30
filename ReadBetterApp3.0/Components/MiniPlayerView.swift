//
//  MiniPlayerView.swift
//  ReadBetterApp3.0
//
//  Mini player component for background audio playback control.
//  Displays in two modes: expanded (floating above tab bar) and collapsed (inline with tab bar).
//

import SwiftUI

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

// MARK: - Expanded Mini Player (Floating above tab bar)
struct MiniPlayerExpanded: View {
    @EnvironmentObject var themeManager: ThemeManager
    @ObservedObject var audioPlayer: OptimizedAudioPlayer
    let onTap: () -> Void
    var animationNamespace: Namespace.ID?
    
    var body: some View {
        VStack(spacing: 0) {
            // Main content
            HStack(spacing: 12) {
                // Book cover with matched geometry for Spotify-style animation
                Group {
                    if let coverURL = audioPlayer.coverURL {
                        AsyncImage(url: coverURL) { image in
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        } placeholder: {
                            coverPlaceholder
                        }
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
            
            // Progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background track
                    Rectangle()
                        .fill(themeManager.colors.cardBorder)
                        .frame(height: 3)
                    
                    // Progress track
                    Rectangle()
                        .fill(themeManager.colors.primary)
                        .frame(width: geometry.size.width * progressPercent, height: 3)
                }
            }
            .frame(height: 3)
        }
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
                        AsyncImage(url: coverURL) { image in
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        } placeholder: {
                            coverPlaceholder
                        }
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
    
    var body: some View {
        GlassMorphicView {
            HStack(spacing: 10) {
                // Small book cover (tappable to open reader) with matched geometry
                Button(action: onTap) {
                    Group {
                        if let coverURL = audioPlayer.coverURL {
                            AsyncImage(url: coverURL) { image in
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                            } placeholder: {
                                coverPlaceholder
                            }
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
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
        }
        .frame(height: 76)
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

