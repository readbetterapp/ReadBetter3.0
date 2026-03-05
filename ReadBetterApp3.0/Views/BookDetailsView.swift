//
//  BookDetailsView.swift
//  ReadBetterApp3.0
//
//  Created by Ermin on 30/11/2025.
//

import SwiftUI
import Kingfisher

struct BookDetailsView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @EnvironmentObject var router: AppRouter
    @EnvironmentObject var readingProgressService: ReadingProgressService
    @EnvironmentObject var authManager: AuthManager
    @StateObject private var bookService = BookService.shared
    @StateObject private var ownershipService = BookOwnershipService.shared
    @ObservedObject private var downloadManager = DownloadManager.shared

    let bookId: String
    @State private var book: Book?
    @State private var isDescriptionExpanded = false
    @State private var isLoading = true
    @State private var showUnlockModal = false
    @State private var showLoginPrompt = false
    
    var body: some View {
        ZStack {
            themeManager.colors.background
                .ignoresSafeArea()
            
            if isLoading {
                ProgressView()
                    .tint(themeManager.colors.primary)
            } else if let book = book {
                // Blurred background image - fixed behind
                backgroundImageView(book: book)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                
                // Scrollable content
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 24) {
                            // Invisible anchor for scroll position
                            Color.clear
                                .frame(height: 1)
                                .id("top")
                            
                            // Top spacing to position content below back button
                            Spacer().frame(height: 175)
                            
                            // Book Cover and Info
                            bookCoverSection(book: book)
                            
                            // Reading progress (above Description, same width as cards below)
                            if ownershipService.isBookOwned(bookId: book.id),
                               let progress = readingProgressService.getProgress(for: book.id) {
                                readingProgressSection(progress: progress)
                            }
                            
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
                        .padding(.bottom, 200)
                    }
                    .scrollIndicators(.hidden)
                    .contentMargins(.bottom, 0, for: .scrollContent)
                    .onAppear {
                        proxy.scrollTo("top", anchor: .top)
                    }
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
                    // Navigate back to tabs to ensure we don't end up at onboarding
                    router.navigateBackToTabs()
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
        .overlay {
            if showUnlockModal, let book = book {
                UnlockBookModal(book: book, isPresented: $showUnlockModal)
                    .environmentObject(themeManager)
                    .environmentObject(ownershipService)
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
                    .animation(.spring(response: 0.3, dampingFraction: 0.8), value: showUnlockModal)
            }
        }
        .overlay {
            if showLoginPrompt {
                LoginPromptOverlay(isPresented: $showLoginPrompt)
                    .environmentObject(themeManager)
                    .environmentObject(router)
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
                    .animation(.spring(response: 0.3, dampingFraction: 0.8), value: showLoginPrompt)
            }
        }
    }
    
    // MARK: - Background Image
    private func backgroundImageView(book: Book) -> some View {
        ZStack(alignment: .bottom) {
            if let coverUrl = book.coverUrl, let url = URL(string: coverUrl) {
                KFImage(url)
                    .placeholder { Color.clear }
                    .fade(duration: 0.2)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: UIScreen.main.bounds.width, height: 1200)
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
            .frame(height: 400)
        }
        .frame(height: 1200)
        .allowsHitTesting(false)
    }
    
    // MARK: - Book Cover Section
    private func bookCoverSection(book: Book) -> some View {
        let hasChapters = !book.chapters.isEmpty
        let hasDescriptionContent = book.hasDescription == true &&
                                    book.descriptionAudioUrl != nil &&
                                    book.descriptionJsonUrl != nil
        let hasPlayableContent = hasChapters || hasDescriptionContent
        let isOwned = ownershipService.isBookOwned(bookId: book.id)
        let savedProgress = readingProgressService.getProgress(for: book.id)
        let hasProgress = savedProgress != nil
        
        // Determine button state based on ownership and progress
        let buttonLabel: String
        let buttonIcon: String
        let buttonBackground: Color
        let buttonTextColor: Color
        
        if isOwned {
            if hasProgress {
                buttonLabel = "Continue Reading"
                buttonIcon = "play.fill"
            } else {
                buttonLabel = hasChapters ? "Start Reading" : "Coming Soon"
                buttonIcon = hasChapters ? "play.fill" : "clock"
            }
            buttonBackground = hasChapters ? themeManager.colors.primary : themeManager.colors.cardBorder
            buttonTextColor = hasChapters ? themeManager.colors.primaryText : themeManager.colors.textSecondary
        } else {
            buttonLabel = "Unlock Book"
            buttonIcon = "lock.fill"
            buttonBackground = themeManager.colors.primary
            buttonTextColor = themeManager.colors.primaryText
        }
        
        return VStack(spacing: 24) {
            // Book Cover (no progress overlay)
            if let coverUrl = book.coverUrl, let url = URL(string: coverUrl) {
                KFImage(url)
                    .placeholder {
                        RoundedRectangle(cornerRadius: 0)
                            .fill(themeManager.colors.card)
                            .overlay {
                                Image(systemName: "book.fill")
                                    .font(.system(size: 40))
                                    .foregroundColor(themeManager.colors.textSecondary)
                            }
                    }
                    .fade(duration: 0.2)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
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
                    if isOwned {
                        guard hasChapters else { return }
                        // Navigate to reader - use saved progress if available
                        if let progress = savedProgress {
                            router.navigate(to: .readerAt(
                                bookId: book.id,
                                chapterNumber: progress.currentChapterNumber,
                                startTime: progress.currentTime
                            ))
                        } else {
                            router.navigate(to: .reader(bookId: book.id, chapterNumber: nil))
                        }
                    } else {
                        // Check if user is signed in (not guest)
                        if authManager.isSignedIn {
                            // Show unlock modal
                            showUnlockModal = true
                        } else {
                            // Show login prompt for guests
                            showLoginPrompt = true
                        }
                    }
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: buttonIcon)
                            .font(.system(size: 16, weight: .semibold))
                        Text(buttonLabel)
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .foregroundColor(buttonTextColor)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(buttonBackground)
                    .clipShape(Capsule())
                    .opacity(hasChapters ? 1.0 : 0.4)
                }
                .disabled(!isOwned && !hasChapters)
                
                // Sample button for non-owned books
                if !isOwned && hasDescriptionContent {
                    Button(action: {
                        router.navigate(to: .descriptionReader(bookId: book.id))
                    }) {
                        HStack(spacing: 8) {
                            Image(systemName: "eye.fill")
                                .font(.system(size: 16, weight: .semibold))
                            Text("Read Sample")
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
                
                // Read Summary button (only show if book has description)
                // Check both the flag and that URLs exist (more robust)
                if hasDescriptionContent {
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

                // Download for Offline button
                if isOwned && hasChapters {
                    downloadButton(for: book)
                }
            }
            .padding(.horizontal, 32)
        }
    }

    // MARK: - Download Button
    @ViewBuilder
    private func downloadButton(for book: Book) -> some View {
        let status = downloadManager.downloadStatus(for: book.id)
        let isDownloading = downloadManager.activeDownloads[book.id] != nil

        if isDownloading, let progress = downloadManager.activeDownloads[book.id] {
            // Downloading state — show progress
            VStack(spacing: 8) {
                ProgressView(value: progress.fractionComplete)
                    .tint(themeManager.colors.primary)
                HStack {
                    Text("Downloading... \(Int(progress.fractionComplete * 100))%")
                        .font(.system(size: 13))
                        .foregroundColor(themeManager.colors.textSecondary)
                    Spacer()
                    Button("Cancel") {
                        downloadManager.cancelDownload(bookId: book.id)
                    }
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.red)
                }
            }
            .padding(.top, 4)
        } else if status == .completed && downloadManager.isBookDownloaded(book.id) {
            // Downloaded state
            Button(action: {
                downloadManager.deleteDownload(bookId: book.id)
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16, weight: .semibold))
                    Text("Downloaded")
                        .font(.system(size: 16, weight: .semibold))
                    Spacer()
                    Image(systemName: "trash")
                        .font(.system(size: 14))
                        .foregroundColor(.red)
                }
                .foregroundColor(themeManager.colors.primary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(themeManager.colors.card)
                .overlay(
                    Capsule()
                        .strokeBorder(themeManager.colors.primary.opacity(0.3), lineWidth: 1)
                )
                .clipShape(Capsule())
            }
        } else if status == .failed {
            // Failed state — retry
            Button(action: {
                downloadManager.downloadBook(book)
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.clockwise.circle.fill")
                        .font(.system(size: 16, weight: .semibold))
                    Text("Retry Download")
                        .font(.system(size: 16, weight: .semibold))
                }
                .foregroundColor(.orange)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(themeManager.colors.card)
                .overlay(
                    Capsule()
                        .strokeBorder(Color.orange.opacity(0.3), lineWidth: 1)
                )
                .clipShape(Capsule())
            }
        } else {
            // Not downloaded
            Button(action: {
                downloadManager.downloadBook(book)
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.down.circle")
                        .font(.system(size: 16, weight: .semibold))
                    Text("Download for Offline")
                        .font(.system(size: 16, weight: .semibold))
                }
                .foregroundColor(themeManager.colors.text)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(themeManager.colors.card)
                .overlay(
                    Capsule()
                        .strokeBorder(themeManager.colors.cardBorder, lineWidth: 1)
                )
                .clipShape(Capsule())
            }
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
    
    // MARK: - Reading Progress Section
    private func readingProgressSection(progress: ReadingProgress) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Your Progress")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(themeManager.colors.text)
                
                Spacer()
                
                Text("\(Int(progress.percentComplete))%")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(themeManager.colors.primary)
            }
            
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(themeManager.colors.cardBorder)
                        .frame(height: 8)
                    
                    RoundedRectangle(cornerRadius: 4)
                        .fill(themeManager.colors.primary)
                        .frame(width: geometry.size.width * CGFloat(progress.percentComplete / 100), height: 8)
                }
            }
            .frame(height: 8)
            
            HStack {
                Text("Chapter \(progress.currentChapterNumber): \(progress.currentChapterTitle)")
                    .font(.system(size: 12))
                    .foregroundColor(themeManager.colors.textSecondary)
                    .lineLimit(1)
                
                Spacer()
                
                Text(progress.timeRemainingFormatted)
                    .font(.system(size: 12))
                    .foregroundColor(themeManager.colors.textSecondary)
            }
        }
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
        .shadow(color: Color.black.opacity(0.18), radius: 18, x: 0, y: 8)
    }
    
    // MARK: - Chapters Section
    private func chaptersSection(book: Book) -> some View {
        let progress = readingProgressService.getProgress(for: book.id)
        let isOwned = ownershipService.isBookOwned(bookId: book.id)
        let completed = Set(progress?.completedChapterIds ?? [])
        
        return VStack(alignment: .leading, spacing: 16) {
            Text("Chapters")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(themeManager.colors.text)
            
            ForEach(book.chapters.sorted(by: { $0.order < $1.order })) { chapter in
                let cp = progress?.chapterProgressById[chapter.id]
                let fraction: Double = {
                    if completed.contains(chapter.id) { return 1.0 }
                    guard let cp, cp.durationSeconds > 0 else { return 0 }
                    return cp.fractionComplete
                }()
                
                Button(action: {
                    let isOwned = ownershipService.isBookOwned(bookId: book.id)
                    if isOwned {
                        // Navigate to reader with specific chapter
                        router.navigate(to: .reader(bookId: book.id, chapterNumber: chapter.order + 1))
                    } else {
                        // Check if user is signed in (not guest)
                        if authManager.isSignedIn {
                            // Show unlock modal
                            showUnlockModal = true
                        } else {
                            // Show login prompt for guests
                            showLoginPrompt = true
                        }
                    }
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
                            
                            if isOwned, progress != nil {
                                VStack(alignment: .leading, spacing: 6) {
                                    GeometryReader { geometry in
                                        ZStack(alignment: .leading) {
                                            RoundedRectangle(cornerRadius: 3)
                                                .fill(themeManager.colors.cardBorder)
                                                .frame(height: 6)
                                            
                                            RoundedRectangle(cornerRadius: 3)
                                                .fill(themeManager.colors.primary)
                                                .frame(width: geometry.size.width * CGFloat(fraction), height: 6)
                                        }
                                    }
                                    .frame(height: 6)
                                    
                                    Text("\(Int(fraction * 100))%")
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundColor(themeManager.colors.textSecondary)
                                }
                                .padding(.top, 2)
                            } else {
                                Text("Available")
                                    .font(.system(size: 12))
                                    .foregroundColor(themeManager.colors.textSecondary)
                            }
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

