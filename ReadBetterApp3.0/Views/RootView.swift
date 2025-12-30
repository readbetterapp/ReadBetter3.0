//
//  RootView.swift
//  ReadBetterApp3.0
//
//  Created by Ermin on 30/11/2025.
//

import SwiftUI

struct RootView: View {
    @StateObject private var themeManager = ThemeManager()
    @StateObject private var router = AppRouter()
    @StateObject private var bookService = BookService.shared // Add this
    @StateObject private var authManager = AuthManager()
    @StateObject private var bookmarkService = BookmarkService()
    @StateObject private var ownershipService = BookOwnershipService.shared
    @StateObject private var readingProgressService = ReadingProgressService.shared
    @State private var isReady = false
    @State private var showSplash = true
    @State private var splashOpacity: Double = 1.0
    
    var body: some View {
        ZStack {
            if isReady {
                NavigationStack(path: $router.path) {
                    WelcomeView()
                        .navigationDestination(for: AppRoute.self) { route in
                            destinationView(for: route)
                        }
                }
                .environmentObject(themeManager)
                .environmentObject(router)
                .environmentObject(authManager)
                .environmentObject(bookmarkService)
                .environmentObject(ownershipService)
                .environmentObject(readingProgressService)
            } else {
                Color(themeManager.colors.background)
                    .ignoresSafeArea()
            }
            
            if showSplash {
                SplashView()
                    .opacity(splashOpacity)
                    .transition(.opacity)
            }
        }
        .onAppear {
            // Bind services to current user
            bookmarkService.setUser(uid: authManager.uid)
            readingProgressService.setUser(uid: authManager.uid)
            
            // Initialize app and pre-load books
            Task {
                // Start fetching books immediately in background
                do {
                    try await bookService.fetchBooks(useCache: true, forceRefresh: false)
                    print("✅ Books pre-loaded on app launch")
                } catch {
                    print("⚠️ Failed to pre-load books: \(error)")
                }
                
                await MainActor.run { isReady = true }
                
                // Hold splash for 3 seconds, then fade out smoothly
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                
                await MainActor.run {
                    withAnimation(.easeInOut(duration: 0.6)) {
                        splashOpacity = 0
                    }
                }
                
                // Remove splash view after fade completes
                try? await Task.sleep(nanoseconds: 700_000_000)
                await MainActor.run { showSplash = false }
            }
        }
        .onChange(of: authManager.uid) { _, newUid in
            bookmarkService.setUser(uid: newUid)
            readingProgressService.setUser(uid: newUid)
        }
        .preferredColorScheme(themeManager.isDarkMode ? .dark : .light)
    }
    
    @ViewBuilder
    private func destinationView(for route: AppRoute) -> some View {
        Group {
            switch route {
            case .welcome:
                WelcomeView()
            case .login:
                LoginView()
            case .tabs:
                TabContainerView()
            case .bookDetails(let bookId):
                BookDetailsView(bookId: bookId)
            case .genre(let category):
                // Placeholder for genre
                ZStack {
                    themeManager.colors.background.ignoresSafeArea()
                    Text("Genre: \(category)")
                        .foregroundColor(themeManager.colors.text)
                }
            case .reader(let bookId, let chapterNumber):
                ReaderLoadingView(bookId: bookId, chapterNumber: chapterNumber)
            case .readerAt(let bookId, let chapterNumber, let startTime):
                ReaderLoadingView(bookId: bookId, chapterNumber: chapterNumber, initialSeekTime: startTime)
            case .descriptionReader(let bookId):
                ReaderLoadingView(bookId: bookId, chapterNumber: nil, isDescription: true)
            case .descriptionReaderAt(let bookId, let startTime):
                ReaderLoadingView(bookId: bookId, chapterNumber: nil, isDescription: true, initialSeekTime: startTime)
            case .sampleReader(let bookId):
                // Placeholder for sample reader
                ZStack {
                    themeManager.colors.background.ignoresSafeArea()
                    Text("Sample Reader: \(bookId)")
                        .foregroundColor(themeManager.colors.text)
                }
            case .profile:
                ProfileView()
            }
        }
        .environmentObject(themeManager)
        .environmentObject(router)
        .environmentObject(authManager)
        .environmentObject(bookmarkService)
        .environmentObject(ownershipService)
        .environmentObject(readingProgressService)
    }
}

// Simple splash screen shown while initial data loads
private struct SplashView: View {
    var body: some View {
        ZStack {
            Color.white
                .ignoresSafeArea()
            
            HStack(spacing: 4) {
                Text("Read")
                    .font(.system(size: 36, weight: .bold))
                    .foregroundColor(.black)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(ThemeColors.brand)
                
                Text("Better")
                    .font(.system(size: 36, weight: .bold))
                    .foregroundColor(.black)
                    .padding(.leading, 8)
            }
        }
    }
}

// Tab Container View
struct TabContainerView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @EnvironmentObject var router: AppRouter
    @EnvironmentObject var authManager: AuthManager
    @EnvironmentObject var bookmarkService: BookmarkService
    @EnvironmentObject var ownershipService: BookOwnershipService
    @EnvironmentObject var readingProgressService: ReadingProgressService
    @ObservedObject var audioPlayer = OptimizedAudioPlayer.shared
    @State private var selectedTab: TabItem = .home
    @State private var showSearch = false // Keep for compatibility but not used for sheet anymore
    @State private var isTabBarCollapsed = false
    @State private var hideTabBar = false
    
    // MARK: - Spotify-style Animation Namespace
    @Namespace private var miniPlayerAnimation
    
    enum TabItem {
        case home
        case library
        case bookmarks
        case search
    }
    
    // Show expanded mini player when tab bar is NOT collapsed and audio is playing
    // Hide when reader is expanded from mini player
    private var showExpandedMiniPlayer: Bool {
        !isTabBarCollapsed && audioPlayer.hasActiveSession && !router.isReaderExpandedFromMiniPlayer
    }
    
    // Show mini player in tab bar when collapsed and audio is playing
    // Hide when reader is expanded from mini player
    private var showCollapsedMiniPlayer: Bool {
        isTabBarCollapsed && audioPlayer.hasActiveSession && !router.isReaderExpandedFromMiniPlayer
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                // Main content based on selected tab
                Group {
                    switch selectedTab {
                    case .home:
                        HomeView()
                            .id("home")
                    case .library:
                        LibraryView()
                            .id("library")
                    case .bookmarks:
                        BookmarksView()
                            .id("bookmarks")
                    case .search:
                        SearchView()
                            .id("search")
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea(edges: .bottom)
                .environment(\.hideTabBar, $hideTabBar)
                
                // Mini Player + Tab Bar stack
                if !hideTabBar && !router.isReaderExpandedFromMiniPlayer {
                    VStack(spacing: 8) {
                        Spacer()
                        
                        // Expanded Mini Player (floating above tab bar when not collapsed)
                        if showExpandedMiniPlayer {
                            MiniPlayerExpanded(
                                audioPlayer: audioPlayer,
                                onTap: expandReaderFromMiniPlayer,
                                animationNamespace: miniPlayerAnimation
                            )
                            .padding(.horizontal, 20)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                        
                        // Custom Tab Bar
                        CustomTabBar(
                            selectedTab: $selectedTab,
                            showSearch: $showSearch,
                            isCollapsed: $isTabBarCollapsed,
                            onMiniPlayerTap: expandReaderFromMiniPlayer,
                            animationNamespace: miniPlayerAnimation
                        )
                        .padding(.bottom, geometry.safeAreaInsets.bottom)
                    }
                    .allowsHitTesting(true)
                    .transition(.opacity)
                }
                
                // MARK: - Spotify-style Expanded Reader Overlay
                if router.isReaderExpandedFromMiniPlayer, let preloadedData = audioPlayer.preloadedData {
                    ExpandedReaderOverlay(
                        preloadedData: preloadedData,
                        animationNamespace: miniPlayerAnimation,
                        onCollapse: {
                            router.collapseReaderToMiniPlayer()
                        }
                    )
                    .transition(.identity) // No transition - internal animation handles expand/collapse
                    .zIndex(100)
                }
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.85, blendDuration: 0), value: showExpandedMiniPlayer)
            .animation(.easeInOut(duration: 0.25), value: hideTabBar)
            .animation(.spring(response: 0.5, dampingFraction: 0.85), value: router.isReaderExpandedFromMiniPlayer)
        }
        .navigationBarHidden(true)
        .navigationBarBackButtonHidden(true)
        .ignoresSafeArea(.keyboard, edges: .bottom)
    }
    
    // MARK: - Spotify-style Expand from Mini Player
    private func expandReaderFromMiniPlayer() {
        // Only expand if we have preloaded data (audio is playing)
        guard audioPlayer.hasActiveSession, audioPlayer.preloadedData != nil else {
            // Fallback to navigation if no preloaded data
            navigateToReader()
            return
        }
        router.expandReaderFromMiniPlayer()
    }
    
    private func navigateToReader() {
        // Navigate to the reader at the current playback position (fallback)
        guard audioPlayer.hasActiveSession else { return }
        router.navigate(to: .readerAt(
            bookId: audioPlayer.bookId,
            chapterNumber: audioPlayer.chapterNumber,
            startTime: audioPlayer.currentTime
        ))
    }
}

// MARK: - Expanded Reader Overlay (Spotify-style)
struct ExpandedReaderOverlay: View {
    @EnvironmentObject var themeManager: ThemeManager
    @EnvironmentObject var router: AppRouter
    @EnvironmentObject var authManager: AuthManager
    @EnvironmentObject var bookmarkService: BookmarkService
    @EnvironmentObject var readingProgressService: ReadingProgressService
    
    let preloadedData: PreloadedReaderData
    let animationNamespace: Namespace.ID
    let onCollapse: () -> Void
    
    @State private var isExpanded: Bool = false
    @State private var dragOffset: CGFloat = 0
    @State private var isDragging: Bool = false
    
    // Threshold for dismissing via drag
    private let dismissThreshold: CGFloat = 150
    
    // Mini player dimensions (match MiniPlayerExpanded)
    private let miniPlayerHeight: CGFloat = 72
    private let miniPlayerHorizontalPadding: CGFloat = 20
    private let miniPlayerBottomOffset: CGFloat = 100 // Distance from bottom (tab bar + spacing)
    
    var body: some View {
        GeometryReader { geometry in
            let screenHeight = geometry.size.height
            let screenWidth = geometry.size.width
            
            // Calculate the collapsed frame (mini player position)
            let collapsedWidth = screenWidth - (miniPlayerHorizontalPadding * 2)
            let collapsedHeight = miniPlayerHeight
            let collapsedY = screenHeight - miniPlayerBottomOffset - collapsedHeight
            
            ZStack {
                // Background that fades in
                themeManager.colors.background
                    .ignoresSafeArea()
                    .opacity(isExpanded ? backgroundOpacity : 0)
                
                // Reader content with expand/collapse animation
                OptimizedReaderView(
                    preloadedData: preloadedData,
                    initialSeekTime: nil,
                    isOverlayMode: true,
                    animationNamespace: animationNamespace,
                    onDismiss: collapseAndDismiss
                )
                .frame(
                    width: isExpanded ? screenWidth : collapsedWidth,
                    height: isExpanded ? screenHeight + geometry.safeAreaInsets.top + geometry.safeAreaInsets.bottom : collapsedHeight
                )
                .clipShape(RoundedRectangle(cornerRadius: isExpanded ? 0 : 16))
                .offset(y: isExpanded ? dragOffset : collapsedY)
                .shadow(color: .black.opacity(isExpanded ? 0 : 0.3), radius: 8, x: 0, y: 4)
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            guard isExpanded else { return }
                            // Only allow downward drag
                            if value.translation.height > 0 {
                                isDragging = true
                                dragOffset = value.translation.height
                            }
                        }
                        .onEnded { value in
                            guard isExpanded else { return }
                            isDragging = false
                            if value.translation.height > dismissThreshold {
                                collapseAndDismiss()
                            } else {
                                // Snap back
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                    dragOffset = 0
                                }
                            }
                        }
                )
            }
            .ignoresSafeArea()
        }
        .onAppear {
            // Trigger expand animation
            withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
                isExpanded = true
            }
        }
    }
    
    private func collapseAndDismiss() {
        // Animate collapse
        withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
            isExpanded = false
            dragOffset = 0
        }
        // Dismiss after animation completes
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            onCollapse()
        }
    }
    
    private var backgroundOpacity: Double {
        let progress = min(dragOffset / dismissThreshold, 1.0)
        return 1.0 - (progress * 0.5)
    }
}

