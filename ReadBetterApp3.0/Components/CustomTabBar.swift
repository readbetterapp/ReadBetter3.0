//
//  CustomTabBar.swift
//  ReadBetterApp3.0
//
//  Created by Ermin on 30/11/2025.
//

import SwiftUI

struct CustomTabBar: View {
    @EnvironmentObject var themeManager: ThemeManager
    @ObservedObject var audioPlayer = OptimizedAudioPlayer.shared
    @Binding var selectedTab: TabContainerView.TabItem
    @Binding var showSearch: Bool
    @Binding var isCollapsed: Bool  // Expose collapsed state for mini player coordination
    let onMiniPlayerTap: () -> Void
    var animationNamespace: Namespace.ID? = nil  // Optional animation namespace for Spotify-style expand
    @State private var currentTab: TabContainerView.TabItem = .home
    
    private var showMiniPlayerCollapsed: Bool {
        isCollapsed && audioPlayer.hasActiveSession
    }
    
    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                // Main tab bar container (Home, Library, Bookmarks)
                AnimatedTabBarContainer(
                    isCollapsed: isCollapsed,
                    selectedTab: $selectedTab,
                    screenWidth: geometry.size.width
                )
                
                // Collapsed Mini Player - expands to fill space between Home and Search
                if showMiniPlayerCollapsed {
                    MiniPlayerCollapsedBubble(
                        audioPlayer: audioPlayer,
                        onTap: onMiniPlayerTap,
                        animationNamespace: animationNamespace
                    )
                    .frame(maxWidth: .infinity) // Expand to fill available space
                    .padding(.horizontal, 12) // 12px gap on each side
                    .transition(.scale.combined(with: .opacity))
                } else {
                    Spacer()
                }
                
                // Search button - fixed position on the right
                GlassButton(
                    icon: "magnifyingglass",
                    isActive: selectedTab == .search,
                    action: {
                        selectedTab = .search
                    }
                )
            }
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity)
            .animation(.spring(response: 0.35, dampingFraction: 0.85, blendDuration: 0), value: showMiniPlayerCollapsed)
        }
        .frame(height: 76)
        .onChange(of: selectedTab) { oldValue, newValue in
            // Reset collapsed state when switching tabs
            if oldValue != newValue {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85, blendDuration: 0)) {
                    isCollapsed = false
                }
                currentTab = newValue
            }
        }
        .onChange(of: showSearch) { oldValue, newValue in
            // Legacy support - if showSearch is set, navigate to search tab
            if newValue {
                selectedTab = .search
            }
        }
    }
}

struct AnimatedTabBarContainer: View {
    @EnvironmentObject var themeManager: ThemeManager
    let isCollapsed: Bool
    @Binding var selectedTab: TabContainerView.TabItem
    let screenWidth: CGFloat
    
    private var fullWidth: CGFloat {
        screenWidth - 32 - 108 // Account for margins and search button
    }
    
    private var collapsedWidth: CGFloat {
        80
    }
    
    private var tabExpandedWidth: CGFloat {
        fullWidth / 4.0  // Evenly divide among 4 tabs
    }
    
    private var homeTabCollapsedWidth: CGFloat {
        40
    }
    
    private var tabBarContent: some View {
        HStack(spacing: 0) {
            // Home Tab
            TabBarButton(
                icon: "house.fill",
                label: "Home",
                isSelected: selectedTab == .home,
                width: isCollapsed ? homeTabCollapsedWidth : tabExpandedWidth,
                showLabel: !isCollapsed,
                action: {
                    selectedTab = .home
                }
            )
            
            // Library Tab
            if !isCollapsed {
                TabBarButton(
                    icon: "books.vertical.fill",
                    label: "Library",
                    isSelected: selectedTab == .library,
                    width: tabExpandedWidth,
                    showLabel: true,
                    action: {
                        selectedTab = .library
                    }
                )
                .transition(.opacity.combined(with: .scale))
            }
            
            // Bookmarks Tab
            if !isCollapsed {
                TabBarButton(
                    icon: "bookmark.fill",
                    label: "Bookmarks",
                    isSelected: selectedTab == .bookmarks,
                    width: tabExpandedWidth,
                    showLabel: true,
                    action: {
                        selectedTab = .bookmarks
                    }
                )
                .transition(.opacity.combined(with: .scale))
            }
        }
    }
    
    private var glassTintColor: Color {
        themeManager.isDarkMode 
            ? Color(white: 0.3).opacity(0.4) // Uniform mid-grey for dark mode
            : Color(white: 0.5).opacity(0.3) // Subtle grey for light mode
    }
    
    var body: some View {
        Group {
            if #available(iOS 26.0, *) {
                // iOS 26+ Liquid Glass effect
                tabBarContent
                    .frame(width: isCollapsed ? collapsedWidth : fullWidth, height: 76)
                    .glassEffect(.regular.tint(glassTintColor), in: RoundedRectangle(cornerRadius: 38))
            } else {
                // Fallback for iOS 25 and earlier
                GlassMorphicView {
                    tabBarContent
                }
                .frame(width: isCollapsed ? collapsedWidth : fullWidth, height: 76)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85, blendDuration: 0), value: isCollapsed)
        .animation(.spring(response: 0.35, dampingFraction: 0.85, blendDuration: 0), value: selectedTab)
    }
}

struct TabBarButton: View {
    @EnvironmentObject var themeManager: ThemeManager
    let icon: String
    let label: String
    let isSelected: Bool
    let width: CGFloat?
    let showLabel: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 22))
                    .foregroundColor(isSelected ? Color(hex: "#FF383C") : themeManager.colors.textSecondary)
                
                if showLabel {
                    Text(label)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(isSelected ? Color(hex: "#FF383C") : themeManager.colors.textSecondary)
                }
            }
            .frame(width: width, height: 60)
        }
    }
}

struct GlassButton: View {
    @EnvironmentObject var themeManager: ThemeManager
    let icon: String
    let isActive: Bool
    let action: () -> Void
    
    private var glassTintColor: Color {
        themeManager.isDarkMode 
            ? Color(white: 0.3).opacity(0.4) // Uniform mid-grey for dark mode
            : Color(white: 0.5).opacity(0.3) // Subtle grey for light mode
    }
    
    var body: some View {
        Button(action: action) {
            if #available(iOS 26.0, *) {
                // iOS 26+ Liquid Glass effect
                Image(systemName: icon)
                    .font(.system(size: 24))
                    .foregroundColor(isActive ? Color(hex: "#FF383C") : themeManager.colors.text)
                    .frame(width: 76, height: 76)
                    .glassEffect(.regular.tint(glassTintColor), in: RoundedRectangle(cornerRadius: 38))
            } else {
                // Fallback for iOS 25 and earlier
                GlassMorphicView {
                    Image(systemName: icon)
                        .font(.system(size: 24))
                        .foregroundColor(isActive ? Color(hex: "#FF383C") : themeManager.colors.text)
                }
                .frame(width: 76, height: 76)
            }
        }
    }
}

struct GlassMorphicView<Content: View>: View {
    @EnvironmentObject var themeManager: ThemeManager
    let content: Content
    
    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }
    
    var body: some View {
        ZStack {
            // Background with blur
            RoundedRectangle(cornerRadius: 38)
                .fill(themeManager.isDarkMode 
                    ? Color.black.opacity(0.3) 
                    : Color.white.opacity(0.08))
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 38))
            
            // Gradient overlay
            RoundedRectangle(cornerRadius: 38)
                .fill(
                    LinearGradient(
                        colors: gradientColors,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .padding(2)
            
            // Border
            RoundedRectangle(cornerRadius: 38)
                .strokeBorder(
                    themeManager.isDarkMode 
                        ? Color.white.opacity(0.4) 
                        : Color.white.opacity(0.8),
                    lineWidth: 1
                )
            
            // Inner border
            RoundedRectangle(cornerRadius: 37)
                .strokeBorder(
                    themeManager.isDarkMode 
                        ? Color.white.opacity(0.2) 
                        : Color.white.opacity(0.6),
                    lineWidth: 1
                )
                .padding(1)
            
            // Content
            content
        }
        .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)
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

