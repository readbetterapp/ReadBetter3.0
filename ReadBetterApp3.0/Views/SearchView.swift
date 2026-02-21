//
//  SearchView.swift
//  ReadBetterApp3.0
//
//  Created by Ermin on 30/11/2025.
//

import SwiftUI

struct SearchView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @EnvironmentObject var router: AppRouter
    @StateObject private var bookService = BookService.shared
    @Binding var searchQuery: String // Bound to native search bar
    @State private var showGenres: Bool = true
    @State private var scrollOffset: CGFloat = 0
    
    // Sync with parent searchable bar if using native search
    @Environment(\.isSearching) private var isSearching
    @Environment(\.dismissSearch) private var dismissSearch
    
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
        // Using List as scroll container (like Apple Music) for tab bar collapse
        List {
            // Header - Main title
            HStack {
                Text("Search for your next read")
                    .font(.system(size: 28, weight: .semibold))
                    .lineSpacing(-2)
                    .foregroundColor(themeManager.colors.text)
                
                Spacer()
            }
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 20, trailing: 16))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            
            // Books Slider - Show available books
            if !bookService.books.isEmpty {
                booksSliderView
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 24, trailing: 0))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
            
            // Content section
            Group {
                if let selectedGenre = bookService.selectedGenre, !bookService.filteredBooks.isEmpty {
                    genreFilteredView(genreName: selectedGenre)
                } else if showGenres && bookService.selectedGenre == nil {
                    genreContentView
                } else if bookService.books.isEmpty {
                    emptySearchView
                } else {
                    searchResultsView
                }
            }
            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 500, trailing: 0))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background {
            ZStack {
                themeManager.colors.background
                
                // Bottom edge fade - sits behind content and tab bar
                VStack {
                    Spacer()
                    
                    LinearGradient(
                        stops: [
                            .init(color: Color.clear, location: 0.0),
                            .init(color: Color.black.opacity(0.05), location: 0.15),
                            .init(color: Color.black.opacity(0.15), location: 0.35),
                            .init(color: Color.black.opacity(0.30), location: 0.55),
                            .init(color: Color.black.opacity(0.50), location: 0.75),
                            .init(color: Color.black.opacity(0.65), location: 0.88),
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
        .coordinateSpace(name: "searchScroll")
        .onPreferenceChange(ScrollOffsetPreferenceKey.self) { offset in
            scrollOffset = offset
        }
        .onChange(of: searchQuery) { oldValue, newValue in
            if !newValue.trimmingCharacters(in: .whitespaces).isEmpty {
                showGenres = false
                bookService.clearGenreFilter()
                // Perform search
            } else {
                showGenres = true
            }
        }
        // Books are already loaded in RootView, no need to fetch here
        // Only fetch on explicit search or pull-to-refresh
    }
    
    private var booksSliderView: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Featured Books")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(themeManager.colors.text)
                .padding(.horizontal, 16)
            
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 16) {
                    ForEach(bookService.books) { book in
                        FeaturedBookCard2(book: book)
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
            
            
            // Genre Cards with book covers - 2 column grid
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12)
            ], spacing: 12) {
                ForEach(genreCategories, id: \.name) { category in
                    GenreCategoryCard(
                        bookService: bookService,
                        category: category,
                        onTap: {
                            showGenres = false
                            searchQuery = ""
                        }
                    )
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
    
    private func genreFilteredView(genreName: String) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header with genre name and clear button
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Showing results for")
                        .font(.system(size: 14))
                        .foregroundColor(themeManager.colors.textSecondary)
                    
                    Text(genreName)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(themeManager.colors.text)
                }
                
                Spacer()
                
                Button(action: {
                    bookService.clearGenreFilter()
                    showGenres = true
                    searchQuery = ""
                }) {
                    Text("Clear")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(themeManager.colors.text)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(themeManager.colors.card)
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(themeManager.colors.cardBorder, lineWidth: 1)
                        )
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 20)
            
            // Filtered books grid
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 16) {
                    ForEach(bookService.filteredBooks) { book in
                        SearchBookCard(book: book)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }
}

// MARK: - Genre Filtered View (for navigation)
struct GenreFilteredView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @EnvironmentObject var router: AppRouter
    @StateObject private var bookService = BookService.shared
    let genreName: String
    
    // Find matching genre category
    private var genreCategory: GenreCategory? {
        let categories = [
            GenreCategory(name: "Fiction & Story Telling", colors: ["#FF6B6B", "#FF8E8E"], searchTerms: ["fiction", "novel", "story", "storytelling"]),
            GenreCategory(name: "Self-Improvement\n& Growth", colors: ["#00B894", "#00CEC9"], searchTerms: ["self-help", "personal development", "psychology", "self-improvement", "growth"]),
            GenreCategory(name: "Romance & Love", colors: ["#FFD93D", "#FFCC02"], searchTerms: ["romance", "love", "relationship"]),
            GenreCategory(name: "Business & Money", colors: ["#A29BFE", "#6C5CE7"], searchTerms: ["business", "entrepreneurship", "leadership", "management", "money", "finance"]),
            GenreCategory(name: "Philosophy", colors: ["#FDCB6E", "#E17055"], searchTerms: ["meditations", "thus spoke", "philosophy", "wisdom", "ethics", "existential"]),
            GenreCategory(name: "Health & Wellness", colors: ["#55A3FF", "#74B9FF"], searchTerms: ["101", "new earth", "health", "wellness", "fitness", "meditation"]),
            GenreCategory(name: "Biography", colors: ["#FD79A8", "#E84393"], searchTerms: ["biography", "memoir", "autobiography"]),
            GenreCategory(name: "History", colors: ["#74B9FF", "#0984E3"], searchTerms: ["plato", "meditations", "history", "historical", "past", "civilization"]),
            GenreCategory(name: "Sci-Fi & Fantasy", colors: ["#6C5CE7", "#A29BFE"], searchTerms: ["science fiction", "fantasy", "sci-fi", "magic"]),
            GenreCategory(name: "True Crime & Mystery", colors: ["#4ECDC4", "#45B7A8"], searchTerms: ["mystery", "thriller", "crime", "detective", "true crime"])
        ]
        return categories.first { $0.name == genreName || $0.name.replacingOccurrences(of: "\n", with: " ") == genreName }
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header
                HStack {
                    Button(action: {
                        router.navigateBack()
                    }) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(themeManager.colors.text)
                    }
                    
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                
                // Genre name
                Text(genreName)
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(themeManager.colors.text)
                    .padding(.horizontal, 16)
                
                // Filtered books
                if !bookService.filteredBooks.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(alignment: .top, spacing: 16) {
                            ForEach(bookService.filteredBooks) { book in
                                SearchBookCard(book: book)
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                } else {
                    VStack(spacing: 16) {
                        Image(systemName: "book.closed")
                            .font(.system(size: 64))
                            .foregroundColor(themeManager.colors.textSecondary)
                        
                        Text("No books found in this genre")
                            .font(.system(size: 16))
                            .foregroundColor(themeManager.colors.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                }
            }
            .padding(.bottom, 120)
        }
        .background(themeManager.colors.background)
        .onAppear {
            if let category = genreCategory {
                bookService.selectedGenre = genreName
                bookService.filterBooksByGenre(category.searchTerms)
            }
        }
        .onDisappear {
            bookService.clearGenreFilter()
        }
    }
}

// MARK: - FlowLayout for flexible wrapping
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 0
        guard width > 0 else {
            return .zero
        }
        let result = FlowResult(
            in: width,
            subviews: subviews,
            spacing: spacing
        )
        return result.size
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard bounds.width > 0 else { return }
        let result = FlowResult(
            in: bounds.width,
            subviews: subviews,
            spacing: spacing
        )
        for (index, subview) in subviews.enumerated() {
            guard index < result.frames.count else { continue }
            subview.place(at: CGPoint(x: bounds.minX + result.frames[index].minX, y: bounds.minY + result.frames[index].minY), proposal: .unspecified)
        }
    }
    
    struct FlowResult {
        var size: CGSize = .zero
        var frames: [CGRect] = []
        
        init(in maxWidth: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var currentX: CGFloat = 0
            var currentY: CGFloat = 0
            var lineHeight: CGFloat = 0
            
            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)
                
                if currentX + size.width > maxWidth && currentX > 0 {
                    // Wrap to new line
                    currentX = 0
                    currentY += lineHeight + spacing
                    lineHeight = size.height // Start new line with current item height
                } else {
                    // Continue on current line
                    lineHeight = max(lineHeight, size.height)
                }
                
                frames.append(CGRect(x: currentX, y: currentY, width: size.width, height: size.height))
                currentX += size.width + spacing
            }
            
            self.size = CGSize(
                width: maxWidth,
                height: currentY + lineHeight
            )
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
    @EnvironmentObject var router: AppRouter
    @ObservedObject var bookService: BookService
    let category: GenreCategory
    var onTap: () -> Void
    
    // Get books matching this genre
    private var genreBooks: [Book] {
        let lowercasedTerms = category.searchTerms.map { $0.lowercased() }
        return bookService.books.filter { book in
            let titleMatch = lowercasedTerms.contains { term in
                book.title.lowercased().contains(term)
            }
            let authorMatch = lowercasedTerms.contains { term in
                book.author.lowercased().contains(term)
            }
            let descriptionMatch: Bool
            if let description = book.description?.lowercased() {
                descriptionMatch = lowercasedTerms.contains { term in
                    description.contains(term)
                }
            } else {
                descriptionMatch = false
            }
            let genreMatch: Bool
            if let genres = book.enrichedData?.genres {
                let lowercasedGenres = genres.map { $0.lowercased() }
                genreMatch = lowercasedTerms.contains { term in
                    lowercasedGenres.contains { genre in
                        genre.contains(term) || term.contains(genre)
                    }
                }
            } else {
                genreMatch = false
            }
            return titleMatch || authorMatch || descriptionMatch || genreMatch
        }.prefix(3).map { $0 }
    }
    
    var body: some View {
        Button(action: {
            // Filter books by genre
            bookService.selectedGenre = category.name
            bookService.filterBooksByGenre(category.searchTerms)
            onTap()
        }) {
            VStack(alignment: .leading, spacing: 12) {
                // Genre name
                Text(category.name.replacingOccurrences(of: "\n", with: " "))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(themeManager.colors.text)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                // Stacked book covers
                if !genreBooks.isEmpty {
                    ZStack(alignment: .leading) {
                        ForEach(Array(genreBooks.enumerated()), id: \.element.id) { index, book in
                            BookCoverStack(book: book, index: index)
                        }
                    }
                    .frame(height: 100)
                } else {
                    // Placeholder if no books found
                    HStack(spacing: 8) {
                        ForEach(0..<3) { _ in
                            RoundedRectangle(cornerRadius: 6)
                                .fill(themeManager.colors.card.opacity(0.3))
                                .frame(width: 60, height: 90)
                        }
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity)
            .background(themeManager.colors.card)
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(themeManager.colors.cardBorder, lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Book Cover Stack Component
struct BookCoverStack: View {
    @EnvironmentObject var themeManager: ThemeManager
    let book: Book
    let index: Int
    
    private let coverWidth: CGFloat = 65
    private let coverHeight: CGFloat = 95
    private let stackOffset: CGFloat = 20
    
    var body: some View {
        ZStack {
            if let coverUrl = book.coverUrl, let url = URL(string: coverUrl) {
                CachedBookImage(
                    url: url,
                    placeholder: AnyView(
                        RoundedRectangle(cornerRadius: 0)
                            .fill(themeManager.colors.card)
                            .overlay {
                                Image(systemName: "book.fill")
                                    .font(.system(size: 20))
                                    .foregroundColor(themeManager.colors.textSecondary.opacity(0.3))
                            }
                    ),
                    targetSize: CGSize(width: coverWidth, height: coverHeight)
                )
                .aspectRatio(contentMode: .fill)
                .frame(width: coverWidth, height: coverHeight)
                .clipped()
            } else {
                RoundedRectangle(cornerRadius: 0)
                    .fill(themeManager.colors.card)
                    .overlay {
                        Image(systemName: "book.fill")
                            .font(.system(size: 20))
                            .foregroundColor(themeManager.colors.textSecondary)
                    }
                    .frame(width: coverWidth, height: coverHeight)
            }
        }
        .frame(width: coverWidth, height: coverHeight)
        .clipShape(RoundedRectangle(cornerRadius: 0))
        .shadow(color: .black.opacity(0.3), radius: 8, x: 4, y: 6)
        .overlay(alignment: .leading) {
            // Spine effect
            LinearGradient(
                colors: [
                    Color.white.opacity(0.4),
                    Color.white.opacity(0.1),
                    Color.black.opacity(0.05)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: 5)
        }
        .offset(x: CGFloat(index) * stackOffset)
    }
}

struct FeaturedBookCard2: View {
    @EnvironmentObject var themeManager: ThemeManager
    @EnvironmentObject var router: AppRouter
    let book: Book
    
    private let cardWidth: CGFloat = 221.76 // 201.6 * 1.1 = 221.76
    private let cardHeight: CGFloat = 316.8 // 288 * 1.1 = 316.8
    private let coverWidth: CGFloat = 140.8 // 128 * 1.1 = 140.8
    private let coverHeight: CGFloat = 211.2 // 192 * 1.1 = 211.2
    
    // Format published date - extract year only
    private var formattedDate: String? {
        guard let publishedDate = book.publishedDate else { return nil }
        
        // Extract just the year from various formats
        if publishedDate.count == 4, let _ = Int(publishedDate) {
            // Already just a year (e.g., "2020")
            return publishedDate
        } else if publishedDate.count >= 4 {
            // Extract first 4 characters as year (e.g., "2020-01-15" -> "2020")
            let year = String(publishedDate.prefix(4))
            if let _ = Int(year) {
                return year
            }
        }
        
        return nil
    }
    
    // Calculate total book length from chapter durations
    private var totalLength: String? {
        guard !book.chapters.isEmpty else { return nil }
        
        // Sum up all chapter durations if available
        let totalSeconds = book.chapters.compactMap { $0.duration }.reduce(0, +)
        
        guard totalSeconds > 0 else { return nil }
        
        let totalMinutes = Int(totalSeconds / 60)
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }
    
    // Metadata line (date and length)
    private var metadataText: String? {
        var parts: [String] = []
        
        if let date = formattedDate {
            parts.append(date)
        }
        
        if let length = totalLength {
            parts.append(length)
        }
        
        return parts.isEmpty ? nil : parts.joined(separator: " • ")
    }
    
    var body: some View {
        Button(action: {
            router.navigate(to: .bookDetails(bookId: book.id))
        }) {
            ZStack {
                // Blurred background
                if let coverUrl = book.coverUrl, let url = URL(string: coverUrl) {
                    CachedBookImage(
                        url: url,
                        placeholder: AnyView(
                            RoundedRectangle(cornerRadius: 20)
                                .fill(themeManager.colors.card)
                        ),
                        targetSize: CGSize(width: cardWidth, height: cardHeight)
                    )
                    .aspectRatio(contentMode: .fill)
                    .frame(width: cardWidth, height: cardHeight)
                    .clipped()
                    .blur(radius: 40)
                    .opacity(0.3)
                } else {
                    RoundedRectangle(cornerRadius: 20)
                        .fill(themeManager.colors.card)
                }
                
                // Content
                VStack(spacing: 16) {
                    Spacer()
                        .frame(height: 20)
                    
                    // Centered book cover - 3D style with spine
                    ZStack {
                        if let coverUrl = book.coverUrl, let url = URL(string: coverUrl) {
                            CachedBookImage(
                                url: url,
                                placeholder: AnyView(
                                    RoundedRectangle(cornerRadius: 0)
                                        .fill(themeManager.colors.card)
                                        .overlay {
                                            Image(systemName: "book.fill")
                                                .font(.system(size: 40))
                                                .foregroundColor(themeManager.colors.textSecondary.opacity(0.3))
                                        }
                                ),
                                targetSize: CGSize(width: coverWidth, height: coverHeight)
                            )
                            .aspectRatio(contentMode: .fill)
                            .frame(width: coverWidth, height: coverHeight)
                            .clipped()
                        } else {
                            RoundedRectangle(cornerRadius: 0)
                                .fill(themeManager.colors.card)
                                .overlay {
                                    Image(systemName: "book.fill")
                                        .font(.system(size: 40))
                                        .foregroundColor(themeManager.colors.textSecondary)
                                }
                                .frame(width: coverWidth, height: coverHeight)
                        }
                    }
                    .frame(width: coverWidth, height: coverHeight)
                    .clipShape(RoundedRectangle(cornerRadius: 0))
                    .shadow(color: .black.opacity(0.3), radius: 8, x: 4, y: 6)
                    .overlay(alignment: .leading) {
                        // Spine effect
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.4),
                                Color.white.opacity(0.1),
                                Color.black.opacity(0.05)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(width: 8)
                    }
                    
                    // Book details
                    VStack(spacing: 6) {
                        Text(book.title)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(themeManager.colors.text)
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                        
                        Text(book.author)
                            .font(.system(size: 14))
                            .foregroundColor(themeManager.colors.textSecondary)
                            .lineLimit(1)
                        
                        // Date and length metadata
                        if let metadata = metadataText {
                            Text(metadata)
                                .font(.system(size: 14))
                                .foregroundColor(themeManager.colors.textSecondary)
                                .lineLimit(1)
                        }
                    }
                    .padding(.horizontal, 16)
                    
                    Spacer()
                        .frame(height: 20)
                }
            }
            .frame(width: cardWidth, height: cardHeight)
            .background(themeManager.colors.card.opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .strokeBorder(themeManager.colors.cardBorder.opacity(0.5), lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
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
                // Cover - 3D style with spine
                ZStack {
                    if let coverUrl = book.coverUrl, let url = URL(string: coverUrl) {
                        CachedBookImage(
                            url: url,
                            placeholder: AnyView(
                                RoundedRectangle(cornerRadius: 0)
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
                        RoundedRectangle(cornerRadius: 0)
                            .fill(themeManager.colors.card)
                            .overlay {
                                Image(systemName: "book.fill")
                                    .font(.system(size: 30))
                                    .foregroundColor(themeManager.colors.textSecondary)
                            }
                            .frame(width: cardWidth, height: coverHeight)
                    }
                }
                .frame(width: cardWidth, height: coverHeight)
                .clipShape(RoundedRectangle(cornerRadius: 0))
                .shadow(color: .black.opacity(0.3), radius: 8, x: 4, y: 6)
                .overlay(alignment: .leading) {
                    // Spine effect
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.4),
                            Color.white.opacity(0.1),
                            Color.black.opacity(0.05)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: 6)
                }
                
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

