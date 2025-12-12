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
            case .descriptionReader(let bookId):
                ReaderLoadingView(bookId: bookId, chapterNumber: nil, isDescription: true)
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
    @State private var selectedTab: TabItem = .home
    @State private var showSearch = false // Keep for compatibility but not used for sheet anymore
    
    enum TabItem {
        case home
        case library
        case bookmarks
        case search
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
                
                // Custom Tab Bar - positioned at bottom with safe area
                VStack {
                    Spacer()
                    CustomTabBar(
                        selectedTab: $selectedTab,
                        showSearch: $showSearch
                    )
                    .padding(.bottom, geometry.safeAreaInsets.bottom)
                }
                .allowsHitTesting(true)
            }
        }
        .navigationBarHidden(true)
        .navigationBarBackButtonHidden(true)
        .ignoresSafeArea(.keyboard, edges: .bottom)
    }
}

