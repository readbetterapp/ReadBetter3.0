//
//  LibraryView.swift
//  ReadBetterApp3.0
//
//  Created by Ermin on 30/11/2025.
//

import SwiftUI

struct LibraryView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @EnvironmentObject var ownershipService: BookOwnershipService
    @StateObject private var bookService = BookService.shared
    @State private var activeFilter: FilterType = .all
    
    enum FilterType: String, CaseIterable {
        case all = "All Books"
        case reading = "Currently Reading"
        case finished = "Finished"
    }
    
    var filteredBooks: [Book] {
        // Only show owned books
        let ownedBooks = bookService.books.filter { ownershipService.isBookOwned(bookId: $0.id) }
        return ownedBooks
    }
    
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0, pinnedViews: []) {
                // Header
                HStack {
                    Text("My Library")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundColor(themeManager.colors.text)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 20)
                
                // Filter buttons
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(FilterType.allCases, id: \.self) { filter in
                            FilterButton(
                                title: filter.rawValue,
                                isActive: activeFilter == filter,
                                action: { activeFilter = filter }
                            )
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .padding(.bottom, 24)
                
                // Books Grid
                if filteredBooks.isEmpty {
                    EmptyLibraryView()
                        .padding(.top, 60)
                } else {
                    LazyVGrid(columns: [
                        GridItem(.flexible(), spacing: 16),
                        GridItem(.flexible(), spacing: 16)
                    ], spacing: 20) {
                        ForEach(filteredBooks) { book in
                            BookCard(book: book)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 100)
                }
                
                // Extra space for tab bar collapse
                Spacer()
                    .frame(height: 1000)
            }
        }
        .scrollIndicators(.hidden)
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
    }
}

// MARK: - Filter Button
struct FilterButton: View {
    @EnvironmentObject var themeManager: ThemeManager
    let title: String
    let isActive: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(isActive ? themeManager.colors.primaryText : themeManager.colors.textSecondary)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background {
                    if isActive {
                        Capsule()
                            .fill(themeManager.colors.primary)
                    } else {
                        if #available(iOS 26.0, *) {
                            Capsule()
                                .fill(Color.clear)
                                .glassEffect(in: Capsule())
                        } else {
                            Capsule()
                                .fill(themeManager.colors.card)
                                .overlay(
                                    Capsule()
                                        .strokeBorder(themeManager.colors.cardBorder, lineWidth: 1)
                                )
                        }
                    }
                }
                .shadow(color: Color.black.opacity(isActive ? 0 : 0.12), radius: 8, x: 0, y: 4)
        }
    }
}

// MARK: - Empty Library View
struct EmptyLibraryView: View {
    @EnvironmentObject var themeManager: ThemeManager
    
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "books.vertical")
                .font(.system(size: 60))
                .foregroundColor(themeManager.colors.textSecondary)
            
            Text("No Books in Your Library")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(themeManager.colors.text)
            
            Text("Start exploring and add books to your collection")
                .font(.system(size: 14))
                .foregroundColor(themeManager.colors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 40)
        .padding(.horizontal, 40)
        .frame(maxWidth: .infinity)
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
        .shadow(color: Color.black.opacity(0.18), radius: 18, x: 0, y: 8)
        .padding(.horizontal, 16)
    }
}

// MARK: - Book Card Component
struct BookCard: View {
    @EnvironmentObject var themeManager: ThemeManager
    @EnvironmentObject var router: AppRouter
    let book: Book
    
    var body: some View {
        Button(action: {
            router.navigate(to: .bookDetails(bookId: book.id))
        }) {
            VStack(alignment: .leading, spacing: 12) {
                // Cover - Use cached image loader (preloaded in background)
                RoundedRectangle(cornerRadius: 0)
                    .fill(themeManager.colors.card)
                    .frame(height: 180)
                    .overlay {
                        if let coverUrl = book.coverUrl, let url = URL(string: coverUrl) {
                            // Calculate approximate display size for LibraryView grid (2 columns)
                            // Width: approximately (screen width - padding - spacing) / 2, use 200 as safe estimate
                            // Height: 180 as defined in the card
                            let displaySize = CGSize(width: 200, height: 180)
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
                                targetSize: displaySize
                            )
                            .aspectRatio(contentMode: .fill)
                        } else {
                            Image(systemName: "book.fill")
                                .font(.system(size: 40))
                                .foregroundColor(themeManager.colors.textSecondary)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .shadow(color: .black.opacity(0.3), radius: 4, x: 2, y: 3)
                
                // Title
                Text(book.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(themeManager.colors.text)
                    .lineLimit(2)
                
                // Author
                Text("by \(book.author)")
                    .font(.system(size: 12))
                    .foregroundColor(themeManager.colors.textSecondary)
                    .lineLimit(1)
                
                // Publisher/Date info
                if let publisher = book.publisher {
                    Text(publisher)
                        .font(.system(size: 11))
                        .foregroundColor(themeManager.colors.textSecondary)
                        .lineLimit(1)
                }
            }
            .padding(12)
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
            .shadow(color: Color.black.opacity(0.18), radius: 18, x: 0, y: 8)
        }
        .buttonStyle(PlainButtonStyle())
    }
}
