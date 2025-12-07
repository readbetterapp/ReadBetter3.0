//
//  CustomTabBar.swift
//  ReadBetterApp3.0
//
//  Created by Ermin on 30/11/2025.
//

import SwiftUI

struct CustomTabBar: View {
    @EnvironmentObject var themeManager: ThemeManager
    @Binding var selectedTab: TabContainerView.TabItem
    @Binding var showSearch: Bool
    @State private var isCollapsed = false
    @State private var lastScrollY: CGFloat = 0
    @State private var currentTab: TabContainerView.TabItem = .home
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Main tab bar container - animates width
                HStack {
                    AnimatedTabBarContainer(
                        isCollapsed: isCollapsed,
                        selectedTab: $selectedTab,
                        screenWidth: geometry.size.width
                    )
                    Spacer()
                }
                .padding(.leading, 20)
                
                // Search button - fixed position on the right
                HStack {
                    Spacer()
                    GlassButton(
                        icon: "magnifyingglass",
                        isActive: selectedTab == .search,
                        action: {
                            selectedTab = .search
                        }
                    )
                }
                .padding(.trailing, 20)
            }
            .frame(maxWidth: .infinity)
        }
        .frame(height: 76)
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("TabBarScroll"))) { notification in
            if let scrollY = notification.userInfo?["scrollY"] as? CGFloat {
                handleScroll(scrollY: scrollY)
            }
        }
        .onChange(of: selectedTab) { oldValue, newValue in
            // Reset collapsed state and scroll position when switching tabs
            if oldValue != newValue {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85, blendDuration: 0)) {
                    isCollapsed = false
                }
                lastScrollY = 0
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
    
    private func handleScroll(scrollY: CGFloat) {
        let scrollDelta = scrollY - lastScrollY
        
        // Collapse when scrolling down past threshold
        let shouldCollapse = scrollY > 50 && scrollDelta > 0 && !isCollapsed
        // Expand when scrolling up or at top
        let shouldExpand = (scrollY < 30 || scrollDelta < -10) && isCollapsed
        
        if shouldCollapse || shouldExpand {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85, blendDuration: 0)) {
                if shouldCollapse {
                    isCollapsed = true
                } else if shouldExpand {
                    isCollapsed = false
                }
            }
        }
        
        lastScrollY = scrollY
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
        fullWidth / 3.0  // Evenly divide among 3 tabs
    }
    
    private var homeTabCollapsedWidth: CGFloat {
        40
    }
    
    var body: some View {
        GlassMorphicView {
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
        .frame(width: isCollapsed ? collapsedWidth : fullWidth, height: 76)
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
    
    var body: some View {
        Button(action: action) {
            GlassMorphicView {
                Image(systemName: icon)
                    .font(.system(size: 24))
                    .foregroundColor(isActive ? Color(hex: "#FF383C") : themeManager.colors.text)
            }
            .frame(width: 76, height: 76)
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

