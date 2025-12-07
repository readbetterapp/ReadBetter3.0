//
//  LibraryView.swift
//  ReadBetterApp3.0
//
//  Created by Ermin on 30/11/2025.
//

import SwiftUI

struct LibraryView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @StateObject private var bookService = BookService.shared
    @State private var activeFilter: FilterType = .all
    @State private var scrollOffset: CGFloat = 0
    
    enum FilterType: String, CaseIterable {
        case all = "All Books"
        case reading = "Currently Reading"
        case finished = "Finished"
    }
    
    var filteredBooks: [Book] {
        return bookService.books
    }
    
    var body: some View {
        VStack(spacing: 0) {
                // Header
                HStack {
                    Text("My Library")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundColor(themeManager.colors.text)
                    
                    Spacer()
                    
                    // View toggle buttons
                    HStack(spacing: 0) {
                        Button(action: {}) {
                            Image(systemName: "square.grid.3x3.fill")
                                .font(.system(size: 16))
                                .foregroundColor(themeManager.colors.primaryText)
                                .frame(width: 32, height: 32)
                                .background(themeManager.colors.primary)
                                .cornerRadius(4)
                        }
                        
                        Button(action: {}) {
                            Image(systemName: "list.bullet")
                                .font(.system(size: 16))
                                .foregroundColor(themeManager.colors.textSecondary)
                                .frame(width: 32, height: 32)
                        }
                    }
                    .padding(4)
                    .background(themeManager.colors.card)
                    .cornerRadius(8)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 20)
            
                // Filter Buttons
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(FilterType.allCases, id: \.self) { filter in
                            Button(action: {
                                activeFilter = filter
                            }) {
                                Text("\(filter.rawValue) (0)")
                                    .font(.system(size: 14, weight: activeFilter == filter ? .semibold : .regular))
                                    .foregroundColor(
                                        activeFilter == filter 
                                            ? themeManager.colors.primaryText 
                                            : themeManager.colors.textSecondary
                                    )
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 8)
                                    .background(
                                        activeFilter == filter 
                                            ? themeManager.colors.primary 
                                            : themeManager.colors.card
                                    )
                                    .cornerRadius(20)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 20)
                                            .strokeBorder(
                                                activeFilter == filter 
                                                    ? Color.clear 
                                                    : themeManager.colors.cardBorder,
                                                lineWidth: 1
                                            )
                                    )
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .padding(.bottom, 20)
                
                // Books Grid - ScrollView fills remaining space
                ScrollView {
                    VStack {
                        if filteredBooks.isEmpty {
                            VStack(spacing: 16) {
                                Image(systemName: "books.vertical.fill")
                                    .font(.system(size: 64))
                                    .foregroundColor(themeManager.colors.textSecondary)
                                
                                Text("Your library is empty")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundColor(themeManager.colors.text)
                                
                                Text("Start adding books to build your personal library")
                                    .font(.system(size: 16))
                                    .foregroundColor(themeManager.colors.textSecondary)
                                    .multilineTextAlignment(.center)
                            }
                            .padding(.horizontal, 32)
                            .padding(.vertical, 60)
                            .frame(maxWidth: .infinity)
                            .padding(.bottom, 120)
                        } else {
                            LazyVGrid(columns: [
                                GridItem(.flexible(), spacing: 16),
                                GridItem(.flexible(), spacing: 16)
                            ], spacing: 16) {
                                ForEach(filteredBooks) { book in
                                    BookCard(book: book)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.bottom, 120)
                        }
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
        }
        .background(themeManager.colors.background)
        .refreshable {
            // Pull to refresh - force refresh to get latest data
            print("📚 LibraryView: Refreshing books...")
            do {
                try await bookService.fetchBooks(forceRefresh: true)
            } catch {
                print("❌ LibraryView: Error refreshing books: \(error)")
            }
        }
    }
}

// Book model moved to Models/Book.swift

// Book Card Component
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
                    .clipShape(RoundedRectangle(cornerRadius: 0))
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

