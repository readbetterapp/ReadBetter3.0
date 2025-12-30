//
//  HomeView.swift
//  ReadBetterApp3.0
//
//  Created by Ermin on 30/11/2025.
//

import SwiftUI

// Environment key for hiding tab bar
struct HideTabBarKey: EnvironmentKey {
    static let defaultValue: Binding<Bool> = .constant(false)
}

extension EnvironmentValues {
    var hideTabBar: Binding<Bool> {
        get { self[HideTabBarKey.self] }
        set { self[HideTabBarKey.self] = newValue }
    }
}

struct HomeView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @EnvironmentObject var bookmarkService: BookmarkService
    @StateObject private var bookService = BookService.shared
    @State private var scrollOffset: CGFloat = 0
    @State private var showBookmarkOverlay = false
    @Environment(\.hideTabBar) private var hideTabBar
    
    var latestBookmark: Bookmark? {
        bookmarkService.recentBookmarks(limit: 1).first
    }
    
    var bookTitle: String? {
        guard let bookmark = latestBookmark else { return nil }
        return bookService.books.first(where: { $0.id == bookmark.bookId })?.title
    }
    
    var chapterTitle: String? {
        guard let bookmark = latestBookmark else { return nil }
        return bookService.books
            .first(where: { $0.id == bookmark.bookId })?
            .chapters
            .first(where: { $0.id == bookmark.chapterId })?
            .title
    }
    
    var body: some View {
        ZStack {
            ScrollView {
                VStack(spacing: 0) {
                    // Header
                    HomeHeaderView()
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                        .padding(.bottom, 12)
                    
                    // Divider
                    Rectangle()
                        .fill(themeManager.colors.divider)
                        .frame(height: 1)
                        .padding(.horizontal, 16)
                    
                    // Continue Reading Section
                    ContinueReadingSection()
                        .padding(.top, 20)
                    
                    // Inspiration Card
                    InspirationCard()
                        .padding(.top, 20)
                    
                    // Latest Bookmark Card
                    LatestBookmarkCard(showOverlay: $showBookmarkOverlay)
                        .padding(.top, 20)
                    
                    // Learning Path Section
                    LearningPathSection()
                        .padding(.top, 20)
                    
                    // Recently Added Section
                    RecentlyAddedSection()
                        .padding(.top, 20)
                    
                    // Copyright Footer
                    CopyrightFooter()
                        .padding(.top, 20)
                        .padding(.bottom, 120) // Extra padding for tab bar
                }
                .overlay(
                    GeometryReader { geometry in
                        Color.clear
                            .preference(
                                key: ScrollOffsetPreferenceKey.self,
                                value: geometry.frame(in: .named("scroll")).minY
                            )
                    }
                )
            }
            .coordinateSpace(name: "scroll")
            .onPreferenceChange(ScrollOffsetPreferenceKey.self) { value in
                let offset = -value // Invert to get positive scroll down value
                scrollOffset = offset
                
                // Send notification with scroll position
                NotificationCenter.default.post(
                    name: NSNotification.Name("TabBarScroll"),
                    object: nil,
                    userInfo: ["scrollY": max(0, offset)]
                )
            }
            .scrollIndicators(.hidden)
            .background(themeManager.colors.background)
            
            // Bookmark overlay with fade animation
            if showBookmarkOverlay, let bookmark = latestBookmark {
                BookmarkOverlay(
                    bookmark: bookmark,
                    bookTitle: bookTitle,
                    chapterTitle: chapterTitle,
                    isPresented: $showBookmarkOverlay
                )
                .transition(.opacity)
                .zIndex(100)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: showBookmarkOverlay)
        .onChange(of: showBookmarkOverlay) { _, newValue in
            hideTabBar.wrappedValue = newValue
        }
    }
}

struct HomeHeaderView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @EnvironmentObject var router: AppRouter
    @EnvironmentObject var authManager: AuthManager
    
    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12:
            return "Good Morning"
        case 12..<17:
            return "Good Afternoon"
        case 17..<21:
            return "Good Evening"
        default:
            return "Good Night"
        }
    }
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(greeting), \(authManager.displayName)")
                    .font(.system(size: 16))
                    .foregroundColor(themeManager.colors.textSecondary)
            }
            
            Spacer()
            
            Button(action: {
                router.navigate(to: .profile)
            }) {
                Circle()
                    .fill(themeManager.colors.card)
                    .frame(width: 40, height: 40)
                    .overlay {
                        Image(systemName: "person.fill")
                            .foregroundColor(themeManager.colors.text)
                    }
            }
        }
    }
}

struct ContinueReadingSection: View {
    @EnvironmentObject var themeManager: ThemeManager
    @EnvironmentObject var router: AppRouter
    @EnvironmentObject var readingProgressService: ReadingProgressService
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Continue Reading")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(themeManager.colors.text)
                .padding(.horizontal, 16)
            
            if let progress = readingProgressService.mostRecentProgress {
                // Active reading card
                ContinueReadingCard(progress: progress)
                    .padding(.horizontal, 16)
            } else {
                // Empty state
                RoundedRectangle(cornerRadius: 16)
                    .fill(
                        LinearGradient(
                            colors: [themeManager.colors.card, themeManager.colors.card.opacity(0.8)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(height: 180)
                    .overlay {
                        VStack(spacing: 12) {
                            Image(systemName: "book.closed")
                                .font(.system(size: 40))
                                .foregroundColor(themeManager.colors.textSecondary.opacity(0.5))
                            
                            Text("No book in progress")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(themeManager.colors.textSecondary)
                            
                            Text("Start reading to see your progress here")
                                .font(.system(size: 14))
                                .foregroundColor(themeManager.colors.textSecondary.opacity(0.7))
                        }
                    }
                    .padding(.horizontal, 16)
            }
        }
    }
}

struct ContinueReadingCard: View {
    @EnvironmentObject var themeManager: ThemeManager
    @EnvironmentObject var router: AppRouter
    
    let progress: ReadingProgress
    
    var body: some View {
        HStack(spacing: 16) {
                // Book Cover
                if let coverUrl = progress.bookCoverUrl, let url = URL(string: coverUrl) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        case .failure(_), .empty:
                            RoundedRectangle(cornerRadius: 8)
                                .fill(themeManager.colors.cardBorder)
                                .overlay {
                                    Image(systemName: "book.fill")
                                        .font(.system(size: 24))
                                        .foregroundColor(themeManager.colors.textSecondary)
                                }
                        @unknown default:
                            RoundedRectangle(cornerRadius: 8)
                                .fill(themeManager.colors.cardBorder)
                        }
                    }
                    .frame(width: 100, height: 140)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .shadow(color: .black.opacity(0.2), radius: 4, x: 2, y: 3)
                } else {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(themeManager.colors.cardBorder)
                        .frame(width: 100, height: 140)
                        .overlay {
                            Image(systemName: "book.fill")
                                .font(.system(size: 24))
                                .foregroundColor(themeManager.colors.textSecondary)
                        }
                }
                
                // Book Info
                VStack(alignment: .leading, spacing: 8) {
                    Text(progress.bookTitle)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(themeManager.colors.text)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    
                    Text("by \(progress.bookAuthor)")
                        .font(.system(size: 13))
                        .foregroundColor(themeManager.colors.textSecondary)
                        .lineLimit(1)
                    
                    // Chapter info
                    HStack(spacing: 4) {
                        Image(systemName: "bookmark.fill")
                            .font(.system(size: 10))
                            .foregroundColor(themeManager.colors.primary)
                        
                        Text(progress.currentChapterTitle)
                            .font(.system(size: 12))
                            .foregroundColor(themeManager.colors.textSecondary)
                            .lineLimit(1)
                    }
                    
                    Spacer()
                    
                    // Progress bar and time
                    VStack(alignment: .leading, spacing: 6) {
                        // Progress bar
                        GeometryReader { geometry in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(themeManager.colors.cardBorder)
                                    .frame(height: 6)
                                
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(themeManager.colors.primary)
                                    .frame(width: geometry.size.width * CGFloat(progress.percentComplete / 100), height: 6)
                            }
                        }
                        .frame(height: 6)
                        
                        // Stats row
                        HStack {
                            Text("\(Int(progress.percentComplete))% complete")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(themeManager.colors.primary)
                            
                            Spacer()
                            
                            Text(progress.timeRemainingFormatted)
                                .font(.system(size: 11))
                                .foregroundColor(themeManager.colors.textSecondary)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
                // Play button
                Button(action: {
                    // Only the play button should jump directly into the book.
                    router.navigate(to: .readerAt(
                        bookId: progress.bookId,
                        chapterNumber: progress.currentChapterNumber,
                        startTime: progress.currentTime
                    ))
                }) {
                    ZStack {
                        Circle()
                            .fill(themeManager.colors.primary)
                            .frame(width: 44, height: 44)
                        
                        Image(systemName: "play.fill")
                            .font(.system(size: 16))
                            .foregroundColor(themeManager.colors.primaryText)
                            .offset(x: 2) // Visual centering for play icon
                    }
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(16)
            .background(themeManager.colors.card)
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(themeManager.colors.cardBorder, lineWidth: 1)
            )
        .contentShape(Rectangle())
        .onTapGesture {
            // Tapping the card navigates to Book Details (not the reader).
            router.navigate(to: .bookDetails(bookId: progress.bookId))
        }
    }
}

struct InspirationCard: View {
    @EnvironmentObject var themeManager: ThemeManager
    @StateObject private var quoteService = QuoteService(apiKey: Config.openAIAPIKey)
    
    var body: some View {
        RoundedRectangle(cornerRadius: 16)
            .fill(themeManager.colors.card)
            .frame(minHeight: 120)
            .overlay(alignment: .leading) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Daily Inspiration")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(themeManager.colors.text)
                    
                    if quoteService.isLoading {
                        HStack(spacing: 8) {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("Loading quote...")
                                .font(.system(size: 14))
                                .foregroundColor(themeManager.colors.textSecondary)
                        }
                    } else if let quote = quoteService.currentQuote {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\"\(quote.text)\"")
                                .font(.system(size: 14))
                                .foregroundColor(themeManager.colors.textSecondary)
                                .lineLimit(3)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                            
                            Text("— \(quote.author)")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(themeManager.colors.primary)
                                .lineLimit(1)
                        }
                    } else if let error = quoteService.lastError {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.system(size: 12))
                                    .foregroundColor(themeManager.colors.primary)
                                
                                Text("Unable to load quote")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(themeManager.colors.text)
                            }
                            
                            Text(error)
                                .font(.system(size: 12))
                                .foregroundColor(themeManager.colors.textSecondary)
                                .lineLimit(2)
                        }
                    }
                }
                .padding(20)
            }
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(themeManager.colors.cardBorder, lineWidth: 1)
            )
            .padding(.horizontal, 16)
            .task {
                await quoteService.fetchDailyQuote()
            }
    }
}

struct LatestBookmarkCard: View {
    @EnvironmentObject var themeManager: ThemeManager
    @EnvironmentObject var bookmarkService: BookmarkService
    @StateObject private var bookService = BookService.shared
    @Binding var showOverlay: Bool
    
    var latestBookmark: Bookmark? {
        bookmarkService.recentBookmarks(limit: 1).first
    }
    
    var bookTitle: String? {
        guard let bookmark = latestBookmark else { return nil }
        return bookService.books.first(where: { $0.id == bookmark.bookId })?.title
    }
    
    var chapterTitle: String? {
        guard let bookmark = latestBookmark else { return nil }
        return bookService.books
            .first(where: { $0.id == bookmark.bookId })?
            .chapters
            .first(where: { $0.id == bookmark.chapterId })?
            .title
    }
    
    private func formatDate(_ date: Date?) -> String {
        guard let date = date else { return "" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
    
    var body: some View {
        Button(action: {
            if latestBookmark != nil {
                showOverlay = true
            }
        }) {
            RoundedRectangle(cornerRadius: 16)
                .fill(themeManager.colors.card)
                .frame(minHeight: 120)
                .overlay(alignment: .leading) {
                    if let bookmark = latestBookmark {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Latest Bookmark")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundColor(themeManager.colors.text)
                                
                                Spacer()
                                
                                Image(systemName: "bookmark.fill")
                                    .font(.system(size: 14))
                                    .foregroundColor(themeManager.colors.primary)
                            }
                            
                            Text("\"\(bookmark.text)\"")
                                .font(.system(size: 14))
                                .foregroundColor(themeManager.colors.textSecondary)
                                .lineLimit(3)
                                .multilineTextAlignment(.leading)
                            
                            HStack(spacing: 4) {
                                if let title = bookTitle {
                                    Text(title)
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(themeManager.colors.primary)
                                        .lineLimit(1)
                                }
                                
                                if let chapter = chapterTitle {
                                    Text("•")
                                        .font(.system(size: 12))
                                        .foregroundColor(themeManager.colors.textSecondary)
                                    
                                    Text(chapter)
                                        .font(.system(size: 12))
                                        .foregroundColor(themeManager.colors.textSecondary)
                                        .lineLimit(1)
                                }
                            }
                            
                            if let updatedAt = bookmark.updatedAt ?? bookmark.createdAt {
                                Text(formatDate(updatedAt))
                                    .font(.system(size: 11))
                                    .foregroundColor(themeManager.colors.textSecondary.opacity(0.7))
                            }
                        }
                        .padding(20)
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Latest Bookmark")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(themeManager.colors.text)
                            
                            Text("Your bookmarks will appear here")
                                .font(.system(size: 14))
                                .foregroundColor(themeManager.colors.textSecondary)
                        }
                        .padding(20)
                    }
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(themeManager.colors.cardBorder, lineWidth: 1)
                )
                .padding(.horizontal, 16)
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(latestBookmark == nil)
    }
}

// MARK: - Bookmark Overlay

struct BookmarkOverlay: View {
    @EnvironmentObject var themeManager: ThemeManager
    let bookmark: Bookmark
    let bookTitle: String?
    let chapterTitle: String?
    @Binding var isPresented: Bool
    
    private func formatDate(_ date: Date?) -> String {
        guard let date = date else { return "" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    var body: some View {
        ZStack {
            // Blurred background - shows home page content blurred behind
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()
                .onTapGesture {
                    isPresented = false
                }
            
            // Bookmark content card
            VStack(spacing: 0) {
                // Header
                HStack {
                    Image(systemName: "bookmark.fill")
                        .font(.system(size: 20))
                        .foregroundColor(themeManager.colors.primary)
                    
                    Text("Bookmark")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(themeManager.colors.text)
                    
                    Spacer()
                    
                    Button(action: {
                        isPresented = false
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 28))
                            .foregroundColor(themeManager.colors.textSecondary.opacity(0.6))
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 16)
                
                // Divider
                Rectangle()
                    .fill(themeManager.colors.divider)
                    .frame(height: 1)
                    .padding(.horizontal, 24)
                
                // Quote content
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        // The bookmarked text
                        Text("\"\(bookmark.text)\"")
                            .font(.system(size: 18))
                            .foregroundColor(themeManager.colors.text)
                            .multilineTextAlignment(.leading)
                            .lineSpacing(6)
                            .padding(.top, 20)
                        
                        // Book and chapter info
                        VStack(alignment: .leading, spacing: 8) {
                            if let title = bookTitle {
                                HStack(spacing: 8) {
                                    Image(systemName: "book.fill")
                                        .font(.system(size: 12))
                                        .foregroundColor(themeManager.colors.primary)
                                    
                                    Text(title)
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundColor(themeManager.colors.primary)
                                }
                            }
                            
                            if let chapter = chapterTitle {
                                HStack(spacing: 8) {
                                    Image(systemName: "text.book.closed")
                                        .font(.system(size: 12))
                                        .foregroundColor(themeManager.colors.textSecondary)
                                    
                                    Text(chapter)
                                        .font(.system(size: 14))
                                        .foregroundColor(themeManager.colors.textSecondary)
                                }
                            }
                            
                            if let date = bookmark.updatedAt ?? bookmark.createdAt {
                                HStack(spacing: 8) {
                                    Image(systemName: "clock")
                                        .font(.system(size: 12))
                                        .foregroundColor(themeManager.colors.textSecondary.opacity(0.7))
                                    
                                    Text("Saved \(formatDate(date))")
                                        .font(.system(size: 13))
                                        .foregroundColor(themeManager.colors.textSecondary.opacity(0.7))
                                }
                            }
                        }
                        .padding(.top, 8)
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
                }
            }
            .background(themeManager.colors.card)
            .cornerRadius(24)
            .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 10)
            .padding(.horizontal, 24)
            .padding(.vertical, 60)
        }
        .transition(.opacity)
    }
}

struct LearningPathSection: View {
    @EnvironmentObject var themeManager: ThemeManager
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Learning Path")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(themeManager.colors.text)
                .padding(.horizontal, 16)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(0..<3) { _ in
                        RoundedRectangle(cornerRadius: 12)
                            .fill(themeManager.colors.card)
                            .frame(width: 120, height: 160)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }
}

struct RecentlyAddedSection: View {
    @EnvironmentObject var themeManager: ThemeManager
    @EnvironmentObject var ownershipService: BookOwnershipService
    @EnvironmentObject var router: AppRouter
    @StateObject private var bookService = BookService.shared
    
    var ownedBooks: [Book] {
        let owned = bookService.books.filter { ownershipService.isBookOwned(bookId: $0.id) }
        // Sort by most recently added (using createdAt if available, otherwise keep order)
        return Array(owned.prefix(10))
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("My Library")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(themeManager.colors.text)
                .padding(.horizontal, 16)
            
            if ownedBooks.isEmpty {
                // Empty state
                VStack(spacing: 12) {
                    Image(systemName: "books.vertical")
                        .font(.system(size: 40))
                        .foregroundColor(themeManager.colors.textSecondary.opacity(0.5))
                    
                    Text("Unlock books to build your library")
                        .font(.system(size: 14))
                        .foregroundColor(themeManager.colors.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 150)
                .padding(.horizontal, 16)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 16) {
                        ForEach(ownedBooks) { book in
                            Button(action: {
                                router.navigate(to: .bookDetails(bookId: book.id))
                            }) {
                                VStack(alignment: .leading, spacing: 8) {
                                    // Book Cover
                                    if let coverUrl = book.coverUrl, let url = URL(string: coverUrl) {
                                        AsyncImage(url: url) { phase in
                                            switch phase {
                                            case .success(let image):
                                                image
                                                    .resizable()
                                                    .aspectRatio(contentMode: .fill)
                                            case .failure(_), .empty:
                                                RoundedRectangle(cornerRadius: 8)
                                                    .fill(themeManager.colors.card)
                                                    .overlay {
                                                        Image(systemName: "book.fill")
                                                            .font(.system(size: 24))
                                                            .foregroundColor(themeManager.colors.textSecondary.opacity(0.3))
                                                    }
                                            @unknown default:
                                                RoundedRectangle(cornerRadius: 8)
                                                    .fill(themeManager.colors.card)
                                            }
                                        }
                                        .frame(width: 100, height: 150)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                        .shadow(color: .black.opacity(0.2), radius: 4, x: 2, y: 3)
                                    } else {
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(themeManager.colors.card)
                                            .frame(width: 100, height: 150)
                                            .overlay {
                                                Image(systemName: "book.fill")
                                                    .font(.system(size: 24))
                                                    .foregroundColor(themeManager.colors.textSecondary)
                                            }
                                            .shadow(color: .black.opacity(0.2), radius: 4, x: 2, y: 3)
                                    }
                                    
                                    // Book Title
                                    Text(book.title)
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(themeManager.colors.text)
                                        .lineLimit(2)
                                        .multilineTextAlignment(.leading)
                                    
                                    // Author
                                    Text(book.author)
                                        .font(.system(size: 11))
                                        .foregroundColor(themeManager.colors.textSecondary)
                                        .lineLimit(1)
                                }
                                .frame(width: 100)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
        }
    }
}

struct CopyrightFooter: View {
    @EnvironmentObject var themeManager: ThemeManager
    
    var body: some View {
        Text("© 2025 Read Better. All rights reserved.")
            .font(.system(size: 12))
            .foregroundColor(themeManager.colors.textSecondary)
            .padding(.horizontal, 16)
    }
}
