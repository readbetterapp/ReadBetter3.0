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
    @StateObject private var learningPathService = LearningPathService.shared
    @StateObject private var readingStatsService = ReadingStatsService.shared
    @State private var isReady = false
    @State private var showSplash = true
    @State private var splashBackgroundOpacity: Double = 1.0
    @State private var logoOffset: CGFloat = UIScreen.main.bounds.height * 0.3
    @State private var showPersistentLogo = true
    @State private var logoOpacity: Double = 1.0
    @State private var useThemeTextColor = false
    @State private var showLearningPathOnboarding = false
    @State private var hasPlayedInitialAnimation = false
    @State private var isCheckingOnboarding = true // New: Track if we're still checking
    @State private var hasSkippedWelcome = false // Track if anonymous user skipped welcome
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                mainContentLayer
                splashLayer
                logoLayer(geometry: geometry)
            }
        }
        .onAppear {
            // Initialize app and pre-load books
            Task {
                // Start fetching books immediately in background
                do {
                    try await bookService.fetchBooks(useCache: true, forceRefresh: false)
                    print("✅ Books pre-loaded on app launch")
                } catch {
                    print("⚠️ Failed to pre-load books: \(error)")
                }
                
                // Wait for AuthManager to be ready (includes session validation for deleted users)
                while !authManager.isReady {
                    try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
                }
                
                // Now bind services to current user (after validation is complete)
                await MainActor.run {
                    bookmarkService.setUser(uid: authManager.uid)
                    readingProgressService.setUser(uid: authManager.uid, isAnonymous: authManager.isAnonymous)
                    learningPathService.setUser(uid: authManager.uid)
                    readingStatsService.setUser(uid: authManager.uid, isAnonymous: authManager.isAnonymous)
                    isReady = true
                }
                
                // If user is signed in, check if they need onboarding
                if !authManager.isAnonymous {
                    // Wait a bit for learningPathService to load preferences
                    try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
                    
                    await MainActor.run {
                        // Check if onboarding is needed
                        if learningPathService.userPreferences == nil {
                            // Clear any stale navigation before showing onboarding
                            router.path.removeLast(router.path.count)
                            showLearningPathOnboarding = true
                        }
                        isCheckingOnboarding = false
                    }
                } else {
                    // Anonymous user - no onboarding check needed
                    await MainActor.run {
                        isCheckingOnboarding = false
                    }
                }
                
                // Hold splash for 3 seconds, then animate transition
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                
                await MainActor.run {
                    // If user is signed in (not anonymous), just fade to home/onboarding
                    // If anonymous, do the slide-up animation to onboarding
                    if authManager.isAnonymous {
                        // Logo slides up from center (current offset) to final top position (offset = 0)
                        withAnimation(.easeOut(duration: 0.5)) {
                            logoOffset = 0 // Slide to final position
                        }
                        
                        // Fade splash background slightly after slide begins
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            withAnimation(.easeInOut(duration: 0.5)) {
                                splashBackgroundOpacity = 0
                                useThemeTextColor = true // Transition "Better" text to theme color
                            }
                        }
                    } else {
                        // Signed in user: just fade out everything
                        withAnimation(.easeInOut(duration: 0.6)) {
                            splashBackgroundOpacity = 0
                            logoOpacity = 0
                        }
                    }
                }
                
                // Remove splash/logo after animations complete
                try? await Task.sleep(nanoseconds: 800_000_000)
                await MainActor.run {
                    showSplash = false
                    // Keep logo visible for anonymous users (onboarding), hide for signed-in users
                    if !authManager.isAnonymous {
                        showPersistentLogo = false
                    }
                    // Mark that initial animation has played
                    hasPlayedInitialAnimation = true
                }
            }
        }
        .onChange(of: authManager.uid) { _, newUid in
            bookmarkService.setUser(uid: newUid)
            readingProgressService.setUser(uid: newUid, isAnonymous: authManager.isAnonymous)
            learningPathService.setUser(uid: newUid)
            readingStatsService.setUser(uid: newUid, isAnonymous: authManager.isAnonymous)
            
            // Check if we should show Learning Path onboarding for newly signed-in users
            if newUid != nil && !authManager.isAnonymous {
                isCheckingOnboarding = true
                checkForOnboarding()
            }
        }
        .onChange(of: learningPathService.userPreferences) { _, newPreferences in
            // When preferences load, update onboarding state
            if isCheckingOnboarding && !authManager.isAnonymous {
                if newPreferences == nil {
                    // Clear any stale navigation before showing onboarding
                    router.path.removeLast(router.path.count)
                    showLearningPathOnboarding = true
                }
                isCheckingOnboarding = false
            }
        }
        .onChange(of: router.path) { _, newPath in
            // Show/hide the persistent logo based on navigation
            if newPath.isEmpty && authManager.isAnonymous && !hasSkippedWelcome && hasPlayedInitialAnimation {
                // Back to WelcomeView - show logo with slide transition
                withAnimation(.easeInOut(duration: 0.35)) {
                    showPersistentLogo = true
                    logoOpacity = 1.0
                    logoOffset = 0
                    useThemeTextColor = true
                }
            } else if !newPath.isEmpty && showPersistentLogo {
                // Navigating away from WelcomeView - hide logo with transition
                withAnimation(.easeInOut(duration: 0.35)) {
                    showPersistentLogo = false
                }
            }
        }
        .onChange(of: hasSkippedWelcome) { _, skipped in
            // Hide logo when user skips welcome
            if skipped {
                withAnimation(.easeInOut(duration: 0.35)) {
                    showPersistentLogo = false
                }
                // Clear any saved session for guest users
                OptimizedAudioPlayer.shared.clearLastPlayedSession()
            }
        }
        .onChange(of: authManager.isAnonymous) { _, isAnonymous in
            // If user becomes anonymous (signed out or deleted), show welcome page
            if isAnonymous && isReady && hasPlayedInitialAnimation {
                // Reset onboarding state - user should see welcome, not onboarding
                showLearningPathOnboarding = false
                isCheckingOnboarding = false
                hasSkippedWelcome = false // Reset skip state so they see welcome again
                
                // Show logo with transition to match page transition
                withAnimation(.easeInOut(duration: 0.35)) {
                    showPersistentLogo = true
                    logoOpacity = 1.0
                    logoOffset = 0 // Already at top position
                    useThemeTextColor = true
                    splashBackgroundOpacity = 0
                }
            } else if !isAnonymous {
                // User signed in - reset skip state
                hasSkippedWelcome = false
            }
        }
        .onChange(of: learningPathService.shouldShowOnboarding) { _, shouldShow in
            // Handle request to show onboarding from elsewhere in the app (e.g., empty state card)
            if shouldShow && !authManager.isAnonymous && !showLearningPathOnboarding {
                router.path.removeLast(router.path.count)
                withAnimation(.easeInOut(duration: 0.4)) {
                    showLearningPathOnboarding = true
                }
                // Reset the flag
                learningPathService.shouldShowOnboarding = false
            }
        }
        .preferredColorScheme(themeManager.isDarkMode ? .dark : .light)
    }
    
    // MARK: - Extracted View Layers
    
    @ViewBuilder
    private var mainContentLayer: some View {
        if isReady && !isCheckingOnboarding {
            mainContentView
                .environmentObject(themeManager)
                .environmentObject(router)
                .environmentObject(authManager)
                .environmentObject(bookmarkService)
                .environmentObject(ownershipService)
                .environmentObject(readingProgressService)
                .environmentObject(learningPathService)
                .environmentObject(readingStatsService)
                .animation(.easeInOut(duration: 0.4), value: showLearningPathOnboarding)
        } else {
            Color(themeManager.colors.background)
                .ignoresSafeArea()
        }
    }
    
    @ViewBuilder
    private var mainContentView: some View {
        if authManager.isAnonymous && !hasSkippedWelcome {
            // Anonymous user who hasn't skipped - show welcome
            NavigationStack(path: $router.path) {
                WelcomeView(onSkip: {
                    withAnimation(.easeInOut(duration: 0.4)) {
                        hasSkippedWelcome = true
                    }
                })
                    .navigationDestination(for: AppRoute.self) { route in
                        destinationView(for: route)
                    }
            }
            .transition(.opacity)
        } else if authManager.isAnonymous && hasSkippedWelcome {
            // Anonymous user who skipped - show tabs directly (not nested in NavigationStack)
            TabContainerView()
                .transition(.move(edge: .leading).combined(with: .opacity))
        } else if showLearningPathOnboarding {
            NavigationStack(path: $router.path) {
                OnboardingContainerView(onComplete: {
                    withAnimation(.easeInOut(duration: 0.4)) {
                        showLearningPathOnboarding = false
                    }
                })
                .environmentObject(themeManager)
                .environmentObject(learningPathService)
                .navigationDestination(for: AppRoute.self) { route in
                    destinationView(for: route)
                }
                .navigationBarHidden(true)
            }
            .transition(.move(edge: .trailing).combined(with: .opacity))
        } else {
            // IMPORTANT: TabView must be at the root for iOS 26 tabBarMinimizeBehavior.
            // NavigationStacks live INSIDE each tab.
            TabContainerView()
                .transition(.move(edge: .leading).combined(with: .opacity))
        }
    }
    
    @ViewBuilder
    private var splashLayer: some View {
        if showSplash {
            Color.white
                .ignoresSafeArea()
                .opacity(splashBackgroundOpacity)
        }
    }
    
    @ViewBuilder
    private func logoLayer(geometry: GeometryProxy) -> some View {
        if showPersistentLogo {
            let safeAreaTop = geometry.safeAreaInsets.top
            let skipButtonHeight: CGFloat = 20 + 36
            let spacerHeight = max(0, geometry.size.height * 0.12 - 150)
            let logoTopPosition = safeAreaTop + skipButtonHeight + spacerHeight
            
            VStack {
                Spacer()
                    .frame(height: logoTopPosition)
                
                logoContent
                
                Spacer()
            }
            .offset(y: logoOffset)
            .opacity(logoOpacity)
        }
    }
    
    private var logoContent: some View {
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
                .opacity(useThemeTextColor ? 0 : 1)
                .overlay(
                    Text("Better")
                        .font(.system(size: 36, weight: .bold))
                        .foregroundColor(themeManager.colors.text)
                        .padding(.leading, 8)
                        .opacity(useThemeTextColor ? 1 : 0)
                )
        }
    }
    
    private func checkForOnboarding() {
        // Wait for preferences to load, then check if onboarding is needed
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if !authManager.isAnonymous && learningPathService.userPreferences == nil {
                // Clear any stale navigation before showing onboarding
                router.path.removeLast(router.path.count)
                showLearningPathOnboarding = true
            }
            isCheckingOnboarding = false
        }
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
                // Find the genre category and show filtered results
                GenreFilteredView(genreName: category)
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
        .environmentObject(learningPathService)
        .environmentObject(readingStatsService)
    }
}

// Tab Container View - Using Native TabView for iOS 26 Liquid Glass
struct TabContainerView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @EnvironmentObject var router: AppRouter
    @EnvironmentObject var authManager: AuthManager
    @EnvironmentObject var bookmarkService: BookmarkService
    @EnvironmentObject var ownershipService: BookOwnershipService
    @EnvironmentObject var readingProgressService: ReadingProgressService
    @EnvironmentObject var learningPathService: LearningPathService
    @ObservedObject var audioPlayer = OptimizedAudioPlayer.shared
    @ObservedObject var bookService = BookService.shared
    @State private var selectedTab: TabItem = .home
    @State private var hideTabBar = false
    @State private var searchQuery: String = "" // For .searchable on Search tab
    
    // MARK: - Computed HomeView Data
    private var homeViewData: (
        latestBookmark: Bookmark?,
        bookmarkBookTitle: String?,
        bookmarkChapterTitle: String?,
        continueReadingProgress: ReadingProgress?,
        ownedBooks: [Book]
    ) {
        // Get latest bookmark
        let latestBookmark = bookmarkService.recentBookmarks(limit: 1).first
        
        // Get bookmark book title
        var bookmarkBookTitle: String?
        var bookmarkChapterTitle: String?
        if let bookmark = latestBookmark {
            bookmarkBookTitle = bookService.books.first(where: { $0.id == bookmark.bookId })?.title
            bookmarkChapterTitle = bookService.books
                .first(where: { $0.id == bookmark.bookId })?
                .chapters
                .first(where: { $0.id == bookmark.chapterId })?
                .title
        }
        
        // Get continue reading progress
        var continueReadingProgress: ReadingProgress?
        if let progress = readingProgressService.mostRecentProgress,
           ownershipService.isBookOwned(bookId: progress.bookId) {
            continueReadingProgress = progress
        }
        
        // Get owned books
        let owned = bookService.books.filter { ownershipService.isBookOwned(bookId: $0.id) }
        let ownedBooks = Array(owned.prefix(10))
        
        return (latestBookmark, bookmarkBookTitle, bookmarkChapterTitle, continueReadingProgress, ownedBooks)
    }
    
    // MARK: - Separate Navigation Paths per Tab (required for TabView at root)
    @State private var homePath = NavigationPath()
    @State private var libraryPath = NavigationPath()
    @State private var bookmarksPath = NavigationPath()
    @State private var searchPath = NavigationPath()
    
    // MARK: - Spotify-style Animation Namespace
    @Namespace private var miniPlayerAnimation
    
    enum TabItem: Int, Hashable {
        case home = 0
        case library = 1
        case bookmarks = 2
        case search = 3
    }
    
    // Get binding to current tab's navigation path
    private var currentPath: Binding<NavigationPath> {
        switch selectedTab {
        case .home: return $homePath
        case .library: return $libraryPath
        case .bookmarks: return $bookmarksPath
        case .search: return $searchPath
        }
    }
    
    // Check if current tab is at its root (no pushed destinations)
    // Directly check path count for reliability
    private var isCurrentTabAtRoot: Bool {
        switch selectedTab {
        case .home: return homePath.isEmpty
        case .library: return libraryPath.isEmpty
        case .bookmarks: return bookmarksPath.isEmpty
        case .search: return searchPath.isEmpty
        }
    }
    
    // Show mini player ONLY when:
    // 1. We have a displayable session (book was played)
    // 2. Current tab has no pushed destinations (at root)
    // 3. Tab bar is not hidden
    // 4. Reader is not expanded from mini player
    private var showMiniPlayer: Bool {
        let hasSession = audioPlayer.hasDisplayableSession
        let atRoot = isCurrentTabAtRoot
        let tabBarVisible = !hideTabBar
        let notExpanded = !router.isReaderExpandedFromMiniPlayer
        
        return hasSession && atRoot && tabBarVisible && notExpanded
    }
    
    var body: some View {
        // IMPORTANT: TabView must be ROOT (not wrapped in ZStack) for iOS 26 tabBarMinimizeBehavior
        // Use .overlay() instead of ZStack for the expanded reader overlay
        Group {
            if #available(iOS 26.0, *) {
                ios26TabView
            } else {
                legacyTabView
            }
        }
        // MARK: - Spotify-style Expanded Reader Overlay (attached via overlay, not ZStack)
        .overlay(alignment: .bottom) {
            if router.isReaderExpandedFromMiniPlayer, let preloadedData = audioPlayer.preloadedData {
                ExpandedReaderOverlay(
                    preloadedData: preloadedData,
                    animationNamespace: miniPlayerAnimation,
                    initialSeekTime: router.readerOverlayInitialSeekTime,
                    onCollapse: {
                        router.readerOverlayInitialSeekTime = nil
                        router.collapseReaderToMiniPlayer()
                    }
                )
                .ignoresSafeArea()
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85, blendDuration: 0), value: showMiniPlayer)
        .animation(.easeInOut(duration: 0.25), value: hideTabBar)
        .navigationBarHidden(true)
        .navigationBarBackButtonHidden(true)
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .onReceive(router.$path) { newPath in
            // When a view calls router.navigate(to:), route it into the current tab's NavigationStack.
            if !newPath.isEmpty {
                currentPath.wrappedValue = newPath
                DispatchQueue.main.async {
                    router.path = NavigationPath()
                }
            }
        }
        .onReceive(router.$backNavigationSignal) { signal in
            if signal == -1 {
                currentPath.wrappedValue = NavigationPath()
            } else if signal > 0 && !currentPath.wrappedValue.isEmpty {
                currentPath.wrappedValue.removeLast()
            }
        }
    }

    // MARK: - iOS 26+ Native TabView with Liquid Glass
    @available(iOS 26.0, *)
    private var ios26TabView: some View {
        TabView(selection: $selectedTab) {
            Tab("Home", systemImage: "house.fill", value: .home) {
                NavigationStack(path: $homePath) {
                    HomeView(
                        displayName: authManager.displayName,
                        latestBookmark: homeViewData.latestBookmark,
                        bookmarkBookTitle: homeViewData.bookmarkBookTitle,
                        bookmarkChapterTitle: homeViewData.bookmarkChapterTitle,
                        continueReadingProgress: homeViewData.continueReadingProgress,
                        ownedBooks: homeViewData.ownedBooks,
                        onProfileTap: { router.navigate(to: .profile) },
                        onContinueReading: { bookId, chapter, time in
                            router.navigate(to: .readerAt(bookId: bookId, chapterNumber: chapter, startTime: time))
                        },
                        onBookTap: { bookId in
                            router.navigate(to: .bookDetails(bookId: bookId))
                        }
                    )
                    .navigationDestination(for: AppRoute.self) { route in
                        destinationWithHiddenTabBar(for: route)
                    }
                }
            }
            
            Tab("Library", systemImage: "books.vertical.fill", value: .library) {
                NavigationStack(path: $libraryPath) {
                    LibraryView()
                        .navigationDestination(for: AppRoute.self) { route in
                            destinationWithHiddenTabBar(for: route)
                        }
                }
            }
            
            Tab("Bookmarks", systemImage: "bookmark.fill", value: .bookmarks) {
                NavigationStack(path: $bookmarksPath) {
                    BookmarksView()
                        .navigationDestination(for: AppRoute.self) { route in
                            destinationWithHiddenTabBar(for: route)
                        }
                }
            }
            
            // Search tab - using role: .search for iOS 26 search expansion behavior
            Tab(value: .search, role: .search) {
                NavigationStack(path: $searchPath) {
                    SearchView(searchQuery: $searchQuery)
                        .navigationBarTitleDisplayMode(.inline)
                        .searchable(text: $searchQuery, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search books, authors, genres...")
                        .navigationDestination(for: AppRoute.self) { route in
                            destinationWithHiddenTabBar(for: route)
                        }
                }
            } label: {
                Label("Search", systemImage: "magnifyingglass")
            }
        }
        .tabViewStyle(.sidebarAdaptable) // REQUIRED for Apple Music-style collapse behavior
        .tint(Color(hex: "#FF383C"))
        .tabBarMinimizeBehavior(.onScrollDown) // Native system handles all scroll tracking
        .modifier(TabViewBottomAccessoryWrapper(isEnabled: showMiniPlayer, audioPlayer: audioPlayer, onTap: expandReaderFromMiniPlayer))
    }
    
    // MARK: - Legacy TabView for older iOS
    private var legacyTabView: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $selectedTab) {
                NavigationStack(path: $homePath) {
                    HomeView(
                        displayName: authManager.displayName,
                        latestBookmark: homeViewData.latestBookmark,
                        bookmarkBookTitle: homeViewData.bookmarkBookTitle,
                        bookmarkChapterTitle: homeViewData.bookmarkChapterTitle,
                        continueReadingProgress: homeViewData.continueReadingProgress,
                        ownedBooks: homeViewData.ownedBooks,
                        onProfileTap: { router.navigate(to: .profile) },
                        onContinueReading: { bookId, chapter, time in
                            router.navigate(to: .readerAt(bookId: bookId, chapterNumber: chapter, startTime: time))
                        },
                        onBookTap: { bookId in
                            router.navigate(to: .bookDetails(bookId: bookId))
                        }
                    )
                    .environment(\.hideTabBar, $hideTabBar)
                    .navigationDestination(for: AppRoute.self) { route in
                        destinationWithHiddenTabBar(for: route)
                    }
                }
                .tabItem { Label("Home", systemImage: "house.fill") }
                .tag(TabItem.home)
                
                NavigationStack(path: $libraryPath) {
                    LibraryView()
                        .environment(\.hideTabBar, $hideTabBar)
                        .navigationDestination(for: AppRoute.self) { route in
                            destinationWithHiddenTabBar(for: route)
                        }
                }
                .tabItem { Label("Library", systemImage: "books.vertical.fill") }
                .tag(TabItem.library)
                
                NavigationStack(path: $bookmarksPath) {
                    BookmarksView()
                        .environment(\.hideTabBar, $hideTabBar)
                        .navigationDestination(for: AppRoute.self) { route in
                            destinationWithHiddenTabBar(for: route)
                        }
                }
                .tabItem { Label("Bookmarks", systemImage: "bookmark.fill") }
                .tag(TabItem.bookmarks)
                
                NavigationStack(path: $searchPath) {
                    SearchView(searchQuery: $searchQuery)
                        .environment(\.hideTabBar, $hideTabBar)
                        .navigationDestination(for: AppRoute.self) { route in
                            destinationWithHiddenTabBar(for: route)
                        }
                }
                .tabItem { Label("Search", systemImage: "magnifyingglass") }
                .tag(TabItem.search)
            }
            .tint(Color(hex: "#FF383C"))
            
            // Floating mini player for legacy iOS
            if showMiniPlayer {
                VStack {
                    Spacer()
                    MiniPlayerExpanded(
                        audioPlayer: audioPlayer,
                        onTap: expandReaderFromMiniPlayer,
                        animationNamespace: miniPlayerAnimation
                    )
                    .padding(.horizontal, 20)
                    .padding(.bottom, 90)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                .allowsHitTesting(!router.isReaderExpandedFromMiniPlayer)
            }
        }
    }
    
    // MARK: - Navigation Destination (hides tab bar)
    @ViewBuilder
    private func destinationWithHiddenTabBar(for route: AppRoute) -> some View {
        Group {
            switch route {
            case .welcome:
                WelcomeView()
            case .login:
                LoginView()
            case .tabs:
                EmptyView()
            case .bookDetails(let bookId):
                BookDetailsView(bookId: bookId)
            case .genre(let category):
                GenreFilteredView(genreName: category)
            case .reader(let bookId, let chapterNumber):
                ReaderLoadingView(bookId: bookId, chapterNumber: chapterNumber)
            case .readerAt(let bookId, let chapterNumber, let startTime):
                ReaderLoadingView(bookId: bookId, chapterNumber: chapterNumber, initialSeekTime: startTime)
            case .descriptionReader(let bookId):
                ReaderLoadingView(bookId: bookId, chapterNumber: nil, isDescription: true)
            case .descriptionReaderAt(let bookId, let startTime):
                ReaderLoadingView(bookId: bookId, chapterNumber: nil, isDescription: true, initialSeekTime: startTime)
            case .sampleReader(let bookId):
                ZStack {
                    themeManager.colors.background.ignoresSafeArea()
                    Text("Sample Reader: \(bookId)")
                        .foregroundColor(themeManager.colors.text)
                }
            case .profile:
                ProfileView()
            }
        }
        .toolbar(.hidden, for: .tabBar)
        .environmentObject(themeManager)
        .environmentObject(router)
        .environmentObject(authManager)
        .environmentObject(bookmarkService)
        .environmentObject(ownershipService)
        .environmentObject(readingProgressService)
        .environmentObject(learningPathService)
        .environmentObject(ReadingStatsService.shared)
    }
    
    // MARK: - Spotify-style Expand from Mini Player
    private func expandReaderFromMiniPlayer() {
        // If we have preloaded data (audio is actively playing), use Spotify-style expand
        if audioPlayer.hasActiveSession && audioPlayer.preloadedData != nil {
            router.expandReaderFromMiniPlayer()
            return
        }
        
        // Fallback: navigate to reader (either resume saved session or active session)
        navigateToReader()
    }
    
    private func navigateToReader() {
        // Navigate to the reader at the saved/current playback position
        // Works for both active sessions and saved/restored sessions (mini player on app launch)
        guard audioPlayer.hasDisplayableSession, !audioPlayer.bookId.isEmpty else { return }
        router.navigate(to: .readerAt(
            bookId: audioPlayer.bookId,
            chapterNumber: audioPlayer.chapterNumber,
            startTime: audioPlayer.currentTime
        ))
    }
}

private struct TabViewBottomAccessoryWrapper: ViewModifier {
    let isEnabled: Bool
    let audioPlayer: OptimizedAudioPlayer
    let onTap: () -> Void

    func body(content: Content) -> some View {
        if #available(iOS 26.1, *) {
            content
                .tabViewBottomAccessory(isEnabled: isEnabled) {
                    // Native iOS 26 mini player - uses system's automatic collapse behavior
                    MiniPlayerAccessoryContent(
                        audioPlayer: audioPlayer,
                        showContent: true,
                        onTap: onTap
                    )
                }
        } else {
            content
        }
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
    let initialSeekTime: Double?
    let onCollapse: () -> Void
    
    // Start off-screen (full screen height below)
    @State private var slideOffset: CGFloat = UIScreen.main.bounds.height
    @State private var dragOffset: CGFloat = 0
    @State private var isDragging: Bool = false
    
    // Threshold for dismissing via drag
    private let dismissThreshold: CGFloat = 150
    
    var body: some View {
        // Full reader - exactly as it appears when loaded fresh
        OptimizedReaderView(
            preloadedData: preloadedData,
            initialSeekTime: initialSeekTime,
            isOverlayMode: true,
            animationNamespace: animationNamespace,
            onDismiss: dismissWithAnimation
        )
        .offset(y: slideOffset + dragOffset)
        .gesture(
            DragGesture()
                .onChanged { value in
                    guard slideOffset == 0 else { return } // Only when fully visible
                    // Only allow downward drag
                    if value.translation.height > 0 {
                        isDragging = true
                        dragOffset = value.translation.height
                    }
                }
                .onEnded { value in
                    guard slideOffset == 0 else { return }
                    isDragging = false
                    if value.translation.height > dismissThreshold {
                        dismissWithAnimation()
                    } else {
                        // Snap back
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            dragOffset = 0
                        }
                    }
                }
        )
        .onAppear {
            // Animate slide up from bottom
            withAnimation(.spring(response: 0.4, dampingFraction: 0.9)) {
                slideOffset = 0
            }
        }
    }
    
    private func dismissWithAnimation() {
        // Animate slide down off screen
        withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) {
            slideOffset = UIScreen.main.bounds.height
            dragOffset = 0
        }
        // Call onCollapse after animation completes
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            onCollapse()
        }
    }
}

