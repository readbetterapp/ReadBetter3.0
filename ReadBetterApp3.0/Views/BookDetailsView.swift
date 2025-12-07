//
//  BookDetailsView.swift
//  ReadBetterApp3.0
//
//  Created by Ermin on 30/11/2025.
//

import SwiftUI

struct BookDetailsView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @EnvironmentObject var router: AppRouter
    @StateObject private var bookService = BookService.shared
    
    let bookId: String
    @State private var book: Book?
    @State private var isDescriptionExpanded = false
    @State private var isLoading = true
    
    var body: some View {
        ZStack {
            themeManager.colors.background
                .ignoresSafeArea()
            
            if isLoading {
                ProgressView()
                    .tint(themeManager.colors.primary)
            } else if let book = book {
                ZStack(alignment: .top) {
                    // Blurred background image - fixed behind
                    backgroundImageView(book: book)
                        .ignoresSafeArea()
                        .allowsHitTesting(false)
                    
                    // Scrollable content
                    ScrollView {
                        VStack(spacing: 24) {
                            // Book Cover and Info
                            bookCoverSection(book: book)
                            
                            // Description
                            if let description = book.description, !description.isEmpty {
                                descriptionSection(description: description)
                            }
                            
                            // Chapters
                            if !book.chapters.isEmpty {
                                chaptersSection(book: book)
                            }
                            
                            // Book Information
                            bookInfoSection(book: book)
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 80) // Space for header
                        .padding(.bottom, 100)
                    }
                    .scrollIndicators(.hidden)
                }
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "book.closed")
                        .font(.system(size: 64))
                        .foregroundColor(themeManager.colors.textSecondary)
                    Text("Book not found")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(themeManager.colors.text)
                }
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button(action: {
                    router.navigateBack()
                }) {
                    Image(systemName: "arrow.left")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(themeManager.colors.text)
                        .frame(width: 40, height: 40)
                        .background(themeManager.colors.card)
                        .clipShape(Circle())
                }
            }
        }
        .task {
            await loadBook()
        }
    }
    
    // MARK: - Background Image
    private func backgroundImageView(book: Book) -> some View {
        ZStack(alignment: .bottom) {
            if let coverUrl = book.coverUrl, let url = URL(string: coverUrl) {
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Color.clear
                }
                .frame(height: 600)
                .clipped()
                .blur(radius: 40)
                .opacity(0.2)
            }
            
            // Gradient fade
            LinearGradient(
                colors: [.clear, themeManager.colors.background],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 250)
        }
        .frame(height: 600)
        .allowsHitTesting(false)
    }
    
    // MARK: - Book Cover Section
    private func bookCoverSection(book: Book) -> some View {
        VStack(spacing: 24) {
            // Book Cover
            if let coverUrl = book.coverUrl, let url = URL(string: coverUrl) {
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    RoundedRectangle(cornerRadius: 0)
                        .fill(themeManager.colors.card)
                        .overlay {
                            Image(systemName: "book.fill")
                                .font(.system(size: 40))
                                .foregroundColor(themeManager.colors.textSecondary)
                        }
                }
                .frame(width: 200, height: 280)
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
            }
            
            // Title and Author
            VStack(spacing: 8) {
                Text(book.title)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundColor(themeManager.colors.text)
                    .multilineTextAlignment(.center)
                
                Text("by \(book.author)")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(themeManager.colors.textSecondary)
            }
            
            // Action Buttons
            VStack(spacing: 12) {
                Button(action: {
                    // Navigate to reader (start from first chapter)
                    router.navigate(to: .reader(bookId: book.id, chapterNumber: nil))
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 16, weight: .semibold))
                        Text("Start Reading")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .foregroundColor(themeManager.colors.primaryText)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(themeManager.colors.primary)
                    .clipShape(Capsule())
                }
                
                // Read Summary button (only show if book has description)
                // Check both the flag and that URLs exist (more robust)
                if book.hasDescription == true && 
                   book.descriptionAudioUrl != nil && 
                   book.descriptionJsonUrl != nil {
                    Button(action: {
                        // Navigate to description reader
                        router.navigate(to: .descriptionReader(bookId: book.id))
                    }) {
                        HStack(spacing: 8) {
                            Image(systemName: "doc.text.fill")
                                .font(.system(size: 16, weight: .semibold))
                            Text("Read Summary")
                                .font(.system(size: 16, weight: .semibold))
                        }
                        .foregroundColor(themeManager.colors.text)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(themeManager.colors.card)
                        .overlay(
                            Capsule()
                                .strokeBorder(themeManager.colors.cardBorder, lineWidth: 1)
                        )
                        .clipShape(Capsule())
                    }
                }
            }
            .padding(.horizontal, 32)
        }
    }
    
    // MARK: - Description Section
    private func descriptionSection(description: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Description")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(themeManager.colors.text)
            
            Text(description)
                .font(.system(size: 14))
                .foregroundColor(themeManager.colors.textSecondary)
                .lineSpacing(4)
                .lineLimit(isDescriptionExpanded ? nil : 3)
            
            if description.count > 150 {
                Button(action: {
                    withAnimation {
                        isDescriptionExpanded.toggle()
                    }
                }) {
                    Text(isDescriptionExpanded ? "See less" : "See more")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(themeManager.colors.primary)
                }
            }
        }
        .padding(16)
        .background(themeManager.colors.card)
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(themeManager.colors.cardBorder, lineWidth: 1)
        )
    }
    
    // MARK: - Chapters Section
    private func chaptersSection(book: Book) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Chapters")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(themeManager.colors.text)
            
            ForEach(book.chapters.sorted(by: { $0.order < $1.order })) { chapter in
                Button(action: {
                    // Navigate to reader with specific chapter
                    router.navigate(to: .reader(bookId: book.id, chapterNumber: chapter.order + 1))
                }) {
                    HStack(spacing: 12) {
                        // Chapter number circle
                        ZStack {
                            Circle()
                                .fill(themeManager.colors.cardBorder)
                                .frame(width: 32, height: 32)
                            
                            Text("\(chapter.order + 1)")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(themeManager.colors.textSecondary)
                        }
                        
                        // Chapter info
                        VStack(alignment: .leading, spacing: 2) {
                            Text(chapter.title)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(themeManager.colors.text)
                            
                            Text("Available")
                                .font(.system(size: 12))
                                .foregroundColor(themeManager.colors.textSecondary)
                        }
                        
                        Spacer()
                        
                        Image(systemName: "play.fill")
                            .font(.system(size: 14))
                            .foregroundColor(themeManager.colors.textSecondary)
                    }
                    .padding(.vertical, 12)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(16)
        .background(themeManager.colors.card)
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(themeManager.colors.cardBorder, lineWidth: 1)
        )
    }
    
    // MARK: - Book Info Section
    private func bookInfoSection(book: Book) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Book Information")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(themeManager.colors.text)
            
            if let publisher = book.publisher {
                infoRow(label: "Publisher", value: publisher)
            }
            
            if let publishedDate = book.publishedDate {
                infoRow(label: "Published", value: publishedDate)
            }
            
            infoRow(label: "ISBN-10", value: book.isbn10)
            
            if let isbn13 = book.isbn13 {
                infoRow(label: "ISBN-13", value: isbn13)
            }
        }
        .padding(16)
        .background(themeManager.colors.card)
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(themeManager.colors.cardBorder, lineWidth: 1)
        )
    }
    
    private func infoRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 14))
                .foregroundColor(themeManager.colors.textSecondary)
            
            Spacer()
            
            Text(value)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(themeManager.colors.text)
        }
    }
    
    // MARK: - Load Book
    private func loadBook() async {
        isLoading = true
        do {
            book = try await bookService.getBook(isbn: bookId)
        } catch {
            print("❌ Error loading book: \(error)")
        }
        isLoading = false
    }
}

