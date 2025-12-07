//
//  SearchView.swift
//  ReadBetterApp3.0
//
//  Created by Ermin on 30/11/2025.
//

import SwiftUI

struct SearchView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @StateObject private var bookService = BookService.shared
    @State private var searchQuery: String = ""
    @State private var showGenres: Bool = true
    @State private var scrollOffset: CGFloat = 0
    
    private let genreCategories = [
        GenreCategory(
            name: "Fiction & Story Telling",
            colors: ["#FF6B6B", "#FF8E8E"],
            searchTerms: ["fiction", "novel", "story", "storytelling"]
        ),
        GenreCategory(
            name: "Self-Improvement\n& Growth",
            colors: ["#00B894", "#00CEC9"],
            searchTerms: ["self-help", "personal development", "psychology", "self-improvement", "growth"]
        ),
        GenreCategory(
            name: "Romance & Love",
            colors: ["#FFD93D", "#FFCC02"],
            searchTerms: ["romance", "love", "relationship"]
        ),
        GenreCategory(
            name: "Business & Money",
            colors: ["#A29BFE", "#6C5CE7"],
            searchTerms: ["business", "entrepreneurship", "leadership", "management", "money", "finance"]
        ),
        GenreCategory(
            name: "Philosophy",
            colors: ["#FDCB6E", "#E17055"],
            searchTerms: ["meditations", "thus spoke", "philosophy", "wisdom", "ethics", "existential"]
        ),
        GenreCategory(
            name: "Health & Wellness",
            colors: ["#55A3FF", "#74B9FF"],
            searchTerms: ["101", "new earth", "health", "wellness", "fitness", "meditation"]
        ),
        GenreCategory(
            name: "Biography",
            colors: ["#FD79A8", "#E84393"],
            searchTerms: ["biography", "memoir", "autobiography"]
        ),
        GenreCategory(
            name: "History",
            colors: ["#74B9FF", "#0984E3"],
            searchTerms: ["plato", "meditations", "history", "historical", "past", "civilization"]
        ),
        GenreCategory(
            name: "Sci-Fi & Fantasy",
            colors: ["#6C5CE7", "#A29BFE"],
            searchTerms: ["science fiction", "fantasy", "sci-fi", "magic"]
        ),
        GenreCategory(
            name: "True Crime & Mystery",
            colors: ["#4ECDC4", "#45B7A8"],
            searchTerms: ["mystery", "thriller", "crime", "detective", "true crime"]
        )
    ]
    
    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Header with Search Bar
                VStack(spacing: 20) {
                    HStack {
                        Text("Explore Books")
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundColor(themeManager.colors.text)
                        
                        Spacer()
                    }
                    
                    // Search Bar
                    HStack(spacing: 12) {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(themeManager.colors.textSecondary)
                        
                        TextField("Search for books, authors, genres...", text: $searchQuery)
                            .font(.system(size: 16))
                            .foregroundColor(themeManager.colors.text)
                            .onChange(of: searchQuery) { oldValue, newValue in
                                if !newValue.trimmingCharacters(in: .whitespaces).isEmpty {
                                    showGenres = false
                                    // Perform search
                                } else {
                                    showGenres = true
                                }
                            }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(themeManager.colors.card)
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(themeManager.colors.cardBorder, lineWidth: 1)
                    )
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 20)
                
                // Content
                VStack(spacing: 0) {
                    // Books Slider - Show available books
                    if !bookService.books.isEmpty {
                        booksSliderView
                            .padding(.bottom, 24)
                    }
                    
                    if showGenres {
                        genreContentView
                    } else if bookService.books.isEmpty {
                        emptySearchView
                    } else {
                        searchResultsView
                    }
                }
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
        // Books are already loaded in RootView, no need to fetch here
        // Only fetch on explicit search or pull-to-refresh
    }
    
    private var booksSliderView: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Available Books")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(themeManager.colors.text)
                .padding(.horizontal, 16)
            
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 16) {
                    ForEach(bookService.books) { book in
                        SearchBookCard(book: book)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }
    
    private var genreContentView: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Browse all")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(themeManager.colors.text)
                .padding(.horizontal, 16)
                .padding(.top, 20)
                .padding(.bottom, 20)
            
            // Featured Book Card (if available)
            if !bookService.books.isEmpty {
                FeaturedBookCard(book: bookService.books[0])
                    .padding(.horizontal, 16)
                    .padding(.bottom, 32)
            }
            
            // Genre Grid
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12)
            ], spacing: 12) {
                ForEach(genreCategories, id: \.name) { category in
                    GenreCategoryCard(category: category)
                }
            }
            .padding(.horizontal, 16)
        }
    }
    
    private var emptySearchView: some View {
        VStack(spacing: 16) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 64))
                .foregroundColor(themeManager.colors.textSecondary)
            
            Text("No books found for \"\(searchQuery)\"")
                .font(.system(size: 16))
                .foregroundColor(themeManager.colors.textSecondary)
                .multilineTextAlignment(.center)
            
            Button(action: {
                searchQuery = ""
                showGenres = true
            }) {
                Text("Browse Genres")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(themeManager.colors.text)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(themeManager.colors.card)
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(themeManager.colors.cardBorder, lineWidth: 1)
                    )
            }
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 40)
    }
    
    private var searchResultsView: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Search Results")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(themeManager.colors.text)
                .padding(.horizontal, 16)
            
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 16) {
                    ForEach(bookService.books.prefix(10)) { book in
                        SearchBookCard(book: book)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }
}

struct GenreCategory: Identifiable {
    let id = UUID()
    let name: String
    let colors: [String]
    let searchTerms: [String]
}

struct GenreCategoryCard: View {
    @EnvironmentObject var themeManager: ThemeManager
    let category: GenreCategory
    
    var body: some View {
        Button(action: {
            // Navigate to genre view
        }) {
            VStack(alignment: .leading, spacing: 12) {
                Text(category.name)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                Spacer()
                
                HStack(spacing: 8) {
                    ForEach(0..<2) { _ in
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.white.opacity(0.2))
                            .frame(width: 40, height: 60)
                    }
                }
            }
            .padding(16)
            .frame(height: 150)
            .background(
                LinearGradient(
                    colors: category.colors.map { Color(hex: $0) },
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .cornerRadius(16)
        }
    }
}

struct SearchBookCard: View {
    @EnvironmentObject var themeManager: ThemeManager
    @EnvironmentObject var router: AppRouter
    let book: Book
    
    private let cardWidth: CGFloat = 120
    private let coverHeight: CGFloat = 180
    
    var body: some View {
        Button(action: {
            router.navigate(to: .bookDetails(bookId: book.id))
        }) {
            VStack(alignment: .leading, spacing: 8) {
                // Cover - Use cached image loader (preloaded in background)
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(themeManager.colors.card)
                        .frame(width: cardWidth, height: coverHeight)
                    
                    if let coverUrl = book.coverUrl, let url = URL(string: coverUrl) {
                        CachedBookImage(
                            url: url,
                            placeholder: AnyView(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(themeManager.colors.card)
                                    .overlay {
                                        Image(systemName: "book.fill")
                                            .font(.system(size: 30))
                                            .foregroundColor(themeManager.colors.textSecondary.opacity(0.3))
                                    }
                            ),
                            targetSize: CGSize(width: cardWidth, height: coverHeight)
                        )
                        .aspectRatio(contentMode: .fill)
                        .frame(width: cardWidth, height: coverHeight)
                        .clipped()
                    } else {
                        Image(systemName: "book.fill")
                            .font(.system(size: 30))
                            .foregroundColor(themeManager.colors.textSecondary)
                    }
                }
                .frame(width: cardWidth, height: coverHeight)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
                
                // Title - Fixed width below cover
                Text(book.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(themeManager.colors.text)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(width: cardWidth, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                
                // Author - Fixed width below title
                Text(book.author)
                    .font(.system(size: 12))
                    .foregroundColor(themeManager.colors.textSecondary)
                    .lineLimit(1)
                    .frame(width: cardWidth, alignment: .leading)
            }
            .frame(width: cardWidth, alignment: .leading)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct FeaturedBookCard: View {
    @EnvironmentObject var themeManager: ThemeManager
    @EnvironmentObject var router: AppRouter
    let book: Book
    
    var body: some View {
        Button(action: {
            router.navigate(to: .bookDetails(bookId: book.id))
        }) {
            VStack(alignment: .leading, spacing: 16) {
                Text(book.title)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(2)
                
                Text(book.author.uppercased())
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white.opacity(0.9))
                
                Text("FEATURED • \(book.author.uppercased())")
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.8))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
            .background(
                LinearGradient(
                    colors: [
                        Color(hex: "#2c2c2e"),
                        Color(hex: "#3a3a3c"),
                        Color(hex: "#48484a")
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .cornerRadius(16)
            .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
        }
    }
}

