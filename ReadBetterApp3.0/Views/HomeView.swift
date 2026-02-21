//
//  HomeView.swift
//  ReadBetterApp3.0
//
//  Created for testing iOS 26 Liquid Glass and tab bar minimization
//

import SwiftUI
import Kingfisher

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
    @StateObject private var bookService = BookService.shared
    @StateObject private var quoteService = QuoteService(apiKey: Config.openAIAPIKey)
    
    // MARK: - Passed Parameters (no @EnvironmentObject triggers)
    let displayName: String
    let latestBookmark: Bookmark?
    let bookmarkBookTitle: String?
    let bookmarkChapterTitle: String?
    let continueReadingProgress: ReadingProgress?
    let ownedBooks: [Book]
    
    // MARK: - Navigation Closures
    var onProfileTap: () -> Void
    var onContinueReading: (String, Int, Double) -> Void
    var onBookTap: (String) -> Void
    
    // MARK: - Cached State
    @State private var greeting: String = ""
    
    private func formatDate(_ date: Date?) -> String {
        guard let date = date else { return "" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
    
    private func updateCachedData() {
        // Calculate greeting
        let hour = Calendar.current.component(.hour, from: Date())
        greeting = switch hour {
        case 5..<12: "Good Morning"
        case 12..<17: "Good Afternoon"
        case 17..<21: "Good Evening"
        default: "Good Night"
        }
    }
    
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0, pinnedViews: []) {
                // MARK: - Header Section
                headerSection
                    .padding(.top, 16)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
                
                // MARK: - Continue Reading Section Title
                Text("Continue Reading")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(themeManager.colors.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.top, 20)
                
                // MARK: - Continue Reading Card
                continueReadingCard
                    .padding(.top, 12)
                    .padding(.horizontal, 16)
                
                // MARK: - Daily Inspiration Card
                inspirationSection
                    .padding(.top, 16)
                    .padding(.horizontal, 16)
                
                // MARK: - Latest Bookmark Card
                bookmarkSection
                    .padding(.top, 16)
                    .padding(.horizontal, 16)
                
                // MARK: - Reading Statistics Card
                ReadingStatsCard()
                    .padding(.top, 16)
                    .padding(.horizontal, 16)
                
                // MARK: - Your Library Section
                yourLibrarySection
                    .padding(.top, 16)
                
                // MARK: - Spacer Cards (to make page ~2000pt)
                ForEach(0..<6, id: \.self) { index in
                    spacerCard(index: index + 2)
                        .padding(.top, 16)
                        .padding(.horizontal, 16)
                }
                
                // MARK: - Footer
                Text("© 2025 Read Better. All rights reserved.")
                    .font(.system(size: 12))
                    .foregroundColor(themeManager.colors.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 32)
                    .padding(.bottom, 100)
                    .padding(.horizontal, 16)
            }
        }
        .scrollIndicators(.hidden)
        .background {
            ZStack {
                themeManager.colors.background
                
                // Bottom edge fade
                VStack {
                    Spacer()
                    LinearGradient(
                        stops: [
                            .init(color: Color.clear, location: 0.0),
                            .init(color: Color.black.opacity(0.40), location: 0.6),
                            .init(color: Color.black.opacity(0.80), location: 1.0)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 120)
                    .ignoresSafeArea(edges: .bottom)
                }
            }
            .ignoresSafeArea()
        }
        .task {
            await quoteService.fetchDailyQuote()
        }
        .onAppear {
            updateCachedData()
        }
    }
    
    // MARK: - Header Section
    private var headerSection: some View {
        HStack {
            Text("\(greeting), \(displayName)")
                .font(.system(size: 16))
                .foregroundColor(themeManager.colors.textSecondary)
            
            Spacer()
            
            Button(action: onProfileTap) {
                Image(systemName: "person.fill")
                    .font(.system(size: 16))
                    .foregroundColor(themeManager.colors.text)
                    .frame(width: 40, height: 40)
                    .background {
                        if #available(iOS 26.0, *) {
                            Circle()
                                .fill(Color.clear)
                                .glassEffect(in: Circle())
                        } else {
                            Circle()
                                .fill(themeManager.colors.card)
                        }
                    }
            }
        }
    }
    
    // MARK: - Continue Reading Card
    private var continueReadingCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let progress = continueReadingProgress {
                ZStack {
                    // Blurred background cover
                    if let coverUrl = progress.bookCoverUrl, let url = URL(string: coverUrl) {
                        GeometryReader { geometry in
                            KFImage(url)
                                .placeholder { Color.clear }
                                .fade(duration: 0.2)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: geometry.size.width, height: geometry.size.height)
                                .clipped()
                                .blur(radius: 30)
                                .opacity(0.4)
                        }
                    }
                    
                    // Content
                    HStack(spacing: 16) {
                        VStack {
                            // Book Cover
                            if let coverUrl = progress.bookCoverUrl, let url = URL(string: coverUrl) {
                            KFImage(url)
                                .placeholder {
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(themeManager.colors.cardBorder)
                                        .overlay {
                                            Image(systemName: "book.fill")
                                                .font(.system(size: 24))
                                                .foregroundColor(themeManager.colors.textSecondary)
                                        }
                                }
                                .fade(duration: 0.2)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 100, height: 140)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
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
                        }
                        .onTapGesture {
                            onBookTap(progress.bookId)
                        }
                        
                        // Book Info
                        VStack(alignment: .leading, spacing: 8) {
                            Text(progress.bookTitle)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(themeManager.colors.text)
                                .lineLimit(2)
                            
                            Text("by \(progress.bookAuthor)")
                                .font(.system(size: 13))
                                .foregroundColor(themeManager.colors.textSecondary)
                                .lineLimit(1)
                            
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
                            
                            // Progress bar
                            VStack(alignment: .leading, spacing: 6) {
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
                        .onTapGesture {
                            onBookTap(progress.bookId)
                        }
                        
                        // Play button
                        Button(action: {
                            onContinueReading(progress.bookId, progress.currentChapterNumber, progress.currentTime)
                        }) {
                            ZStack {
                                Circle()
                                    .fill(themeManager.colors.primary)
                                    .frame(width: 44, height: 44)
                                Image(systemName: "play.fill")
                                    .font(.system(size: 16))
                                    .foregroundColor(themeManager.colors.primaryText)
                                    .offset(x: 2)
                            }
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    .padding(16)
                }
            } else {
                // Empty state
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
                .frame(maxWidth: .infinity)
                .frame(minHeight: 180)
                .padding(16)
            }
        }
        .background {
            if #available(iOS 26.0, *) {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(Color.clear)
                    .glassEffect(in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(themeManager.colors.card)
                    .overlay(
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .strokeBorder(themeManager.colors.cardBorder, lineWidth: 1)
                    )
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
    }
    
    // MARK: - Inspiration Section
    private var inspirationSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Daily Inspiration")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(themeManager.colors.text)
            
            if quoteService.isLoading {
                HStack(spacing: 20) {
                    ProgressView().scaleEffect(0.8)
                    Text("Loading quote...")
                        .font(.system(size: 14))
                        .foregroundColor(themeManager.colors.textSecondary)
                }
            } else if let quote = quoteService.currentQuote {
                VStack(alignment: .leading, spacing: 14) {
                    Text("\"\(quote.text)\"")
                        .font(.system(size: 14))
                        .foregroundColor(themeManager.colors.textSecondary)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("— \(quote.author)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(themeManager.colors.primary)
                        .lineLimit(1)
                }
            } else {
                Text("Unable to load quote")
                    .font(.system(size: 14))
                    .foregroundColor(themeManager.colors.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background {
            if #available(iOS 26.0, *) {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(Color.clear)
                    .glassEffect(in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(themeManager.colors.card)
                    .overlay(
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .strokeBorder(themeManager.colors.cardBorder, lineWidth: 1)
                    )
            }
        }
    }
    
    // MARK: - Bookmark Section
    private var bookmarkSection: some View {
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
            
            if let bookmark = latestBookmark {
                VStack(alignment: .leading, spacing: 8) {
                    Text("\"\(bookmark.text)\"")
                        .font(.system(size: 14))
                        .foregroundColor(themeManager.colors.textSecondary)
                        .lineLimit(3)
                    
                    HStack(spacing: 4) {
                        if let title = bookmarkBookTitle {
                            Text(title)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(themeManager.colors.primary)
                                .lineLimit(1)
                        }
                        if let chapter = bookmarkChapterTitle {
                            Text("•").font(.system(size: 12)).foregroundColor(themeManager.colors.textSecondary)
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
            } else {
                Text("Your bookmarks will appear here")
                    .font(.system(size: 14))
                    .foregroundColor(themeManager.colors.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background {
            if #available(iOS 26.0, *) {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(Color.clear)
                    .glassEffect(in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(themeManager.colors.card)
                    .overlay(
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .strokeBorder(themeManager.colors.cardBorder, lineWidth: 1)
                    )
            }
        }
    }
    
    // MARK: - Your Library Section
    private var yourLibrarySection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Your Library")
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
                                onBookTap(book.id)
                            }) {
                                VStack(alignment: .leading, spacing: 8) {
                                    // Book cover
                                    if let coverUrl = book.coverUrl, let url = URL(string: coverUrl) {
                                        KFImage(url)
                                            .placeholder {
                                                RoundedRectangle(cornerRadius: 8)
                                                    .fill(themeManager.colors.card)
                                                    .overlay {
                                                        Image(systemName: "book.fill")
                                                            .font(.system(size: 24))
                                                            .foregroundColor(themeManager.colors.textSecondary.opacity(0.3))
                                                    }
                                            }
                                            .fade(duration: 0.2)
                                            .resizable()
                                            .aspectRatio(contentMode: .fill)
                                            .frame(width: 100, height: 150)
                                            .clipShape(RoundedRectangle(cornerRadius: 8))
                                    } else {
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(themeManager.colors.card)
                                            .frame(width: 100, height: 150)
                                            .overlay {
                                                Image(systemName: "book.fill")
                                                    .font(.system(size: 24))
                                                    .foregroundColor(themeManager.colors.textSecondary)
                                            }
                                    }
                                    
                                    // Book title
                                    Text(book.title)
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(themeManager.colors.text)
                                        .lineLimit(2)
                                    
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
    
    // MARK: - Spacer Cards (to extend page length)
    private func spacerCard(index: Int) -> some View {
        let titles = [
            "Reading Statistics",
            "Weekly Goal",
            "Recommended Books",
            "Reading Streak",
            "Achievements",
            "Reading History",
            "Favorites",
            "Notes & Highlights"
        ]
        
        let icons = [
            "chart.bar.fill",
            "target",
            "star.fill",
            "flame.fill",
            "trophy.fill",
            "clock.fill",
            "heart.fill",
            "pencil.and.outline"
        ]
        
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: icons[index % icons.count])
                    .font(.system(size: 16))
                    .foregroundColor(themeManager.colors.primary)
                
                Text(titles[index % titles.count])
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(themeManager.colors.text)
            }
            
            Text("This is a placeholder card to extend the page length for testing tab bar minimization on scroll. Card \(index + 1) of 8.")
                .font(.system(size: 14))
                .foregroundColor(themeManager.colors.textSecondary)
                .lineSpacing(4)
            
            // Placeholder content
            HStack(spacing: 12) {
                ForEach(0..<3, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 8)
                        .fill(themeManager.colors.cardBorder.opacity(0.5))
                        .frame(height: 60)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background {
            if #available(iOS 26.0, *) {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(Color.clear)
                    .glassEffect(in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(themeManager.colors.card)
                    .overlay(
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .strokeBorder(themeManager.colors.cardBorder, lineWidth: 1)
                    )
            }
        }
    }
}
