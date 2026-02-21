//
//  BookmarksView.swift
//  ReadBetterApp3.0
//
//  Created by Ermin on 30/11/2025.
//

import SwiftUI

struct BookmarksView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @EnvironmentObject var router: AppRouter
    @EnvironmentObject var authManager: AuthManager
    @EnvironmentObject var bookmarkService: BookmarkService
    
    @State private var isCreateFolderPresented: Bool = false
    @State private var newFolderName: String = ""
    @State private var selectedFolder: BookmarkFolder? = nil
    @State private var scrollOffset: CGFloat = 0
    
    var body: some View {
        // Using List as scroll container (like Apple Music) for tab bar collapse
        List {
            ScrollOffsetReader(coordinateSpace: "bookmarksScroll")
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            // Error message if any
            if let error = bookmarkService.lastErrorMessage {
                Text(error)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.red)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 0, trailing: 16))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
            
            // Header
            HStack {
                Text("Bookmarks")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundColor(themeManager.colors.text)
                
                Spacer()
                
                HStack(spacing: 12) {
                    Button(action: {}) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 20))
                            .foregroundColor(themeManager.colors.text)
                            .frame(width: 40, height: 40)
                            .background(themeManager.colors.card)
                            .cornerRadius(20)
                            .overlay(
                                Circle()
                                    .strokeBorder(themeManager.colors.cardBorder, lineWidth: 1)
                            )
                    }
                    
                    Button(action: {
                        newFolderName = ""
                        isCreateFolderPresented = true
                    }) {
                        Image(systemName: "plus")
                            .font(.system(size: 20))
                            .foregroundColor(themeManager.colors.primaryText)
                            .frame(width: 40, height: 40)
                            .background(themeManager.colors.primary)
                            .cornerRadius(20)
                    }
                }
            }
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 12, trailing: 16))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            
            // Quick Stats
            HStack(spacing: 12) {
                StatCard(
                    icon: "bookmark.fill",
                    value: "\(bookmarkService.bookmarks.count)",
                    label: "Total Bookmarks"
                )
                
                StatCard(
                    icon: "folder.fill",
                    value: "\(bookmarkService.folders.count)",
                    label: "Collections"
                )
            }
            .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 28, trailing: 16))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            
            // Collections Section
            collectionsSection
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 32, trailing: 0))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            
            // Recent Bookmarks Section
            recentBookmarksSection
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 32, trailing: 0))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            
            // Quick Actions
            QuickActionsCard()
                .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            
            // Extra space for tab bar collapse
            Color.clear
                .frame(height: 500)
                .listRowInsets(EdgeInsets())
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
        .overlay(alignment: .top) {
            // Top edge fade - sits on top of content, behind status bar
            LinearGradient(
                stops: [
                    .init(color: Color.black.opacity(0.80), location: 0.0),
                    .init(color: Color.black.opacity(0.65), location: 0.12),
                    .init(color: Color.black.opacity(0.50), location: 0.25),
                    .init(color: Color.black.opacity(0.30), location: 0.45),
                    .init(color: Color.black.opacity(0.15), location: 0.65),
                    .init(color: Color.black.opacity(0.05), location: 0.85),
                    .init(color: Color.clear, location: 1.0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 120)
            .ignoresSafeArea(edges: .top)
            .allowsHitTesting(false)
        }
        .coordinateSpace(name: "bookmarksScroll")
        .onPreferenceChange(ScrollOffsetPreferenceKey.self) { offset in
            scrollOffset = offset
        }
        .alert("Create Folder", isPresented: $isCreateFolderPresented) {
            TextField("Folder name", text: $newFolderName)
            Button("Create") {
                Task {
                    do {
                        _ = try await bookmarkService.createFolder(name: newFolderName)
                    } catch {
                        bookmarkService.lastErrorMessage = "Create folder failed: \(error.localizedDescription)"
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Folders help organize bookmarks. You can add bookmarks to multiple folders.")
        }
        .sheet(item: $selectedFolder) { folder in
            FolderBookmarksSheet(folder: folder, onOpenBookmark: { open($0) })
                .environmentObject(themeManager)
                .environmentObject(bookmarkService)
        }
    }
    
    private var folderNameById: [String: String] {
        Dictionary(uniqueKeysWithValues: bookmarkService.folders.map { ($0.id, $0.name) })
    }
    
    private var collectionsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Collections")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(themeManager.colors.text)
                
                Spacer()
                
                Button("Create New") {
                    newFolderName = ""
                    isCreateFolderPresented = true
                }
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(themeManager.colors.primary)
            }
            .padding(.horizontal, 16)
            
            if bookmarkService.folders.isEmpty {
                EmptyStateCard(
                    icon: "folder.fill",
                    title: "No Collections Yet",
                    message: "Create collections to organize your bookmarks by topic, series, or any way you like.",
                    actionTitle: "Create First Collection",
                    action: {
                        newFolderName = ""
                        isCreateFolderPresented = true
                    }
                )
                .padding(.horizontal, 16)
            } else {
                VStack(spacing: 12) {
                    ForEach(bookmarkService.folders) { folder in
                        BookmarkFolderRow(
                            folder: folder,
                            bookmarkCount: bookmarkService.bookmarks(inFolder: folder.id).count,
                            onTap: { selectedFolder = folder }
                        )
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }
    
    private var recentBookmarksSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Recent Bookmarks")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(themeManager.colors.text)
                
                Spacer()
                
                Button("View All") {
                    // For now, show the Bookmarks tab top section (no separate view yet)
                }
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(themeManager.colors.primary)
            }
            .padding(.horizontal, 16)
            
            let recent = bookmarkService.recentBookmarks(limit: 10)
            if recent.isEmpty {
                EmptyStateCard(
                    icon: "bookmark.fill",
                    title: "No Bookmarks Yet",
                    message: "Start reading and bookmark your favorite passages to see them here.",
                    actionTitle: "Start Reading",
                    action: { }
                )
                .padding(.horizontal, 16)
            } else {
                VStack(spacing: 12) {
                    ForEach(recent) { bookmark in
                        BookmarkRowCard(
                            bookmark: bookmark,
                            folderNameById: folderNameById,
                            onTap: { open(bookmark) }
                        )
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }
    
    private func open(_ bookmark: Bookmark) {
        if bookmark.isDescription {
            router.navigate(to: .descriptionReaderAt(bookId: bookmark.bookId, startTime: bookmark.startTime))
        } else {
            router.navigate(to: .readerAt(bookId: bookmark.bookId, chapterNumber: bookmark.chapterNumber, startTime: bookmark.startTime))
        }
    }
}

struct StatCard: View {
    @EnvironmentObject var themeManager: ThemeManager
    let icon: String
    let value: String
    let label: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Circle()
                .fill(themeManager.colors.primary)
                .frame(width: 32, height: 32)
                .overlay {
                    Image(systemName: icon)
                        .font(.system(size: 16))
                        .foregroundColor(themeManager.colors.primaryText)
                }
            
            Text(value)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(themeManager.colors.text)
            
            Text(label)
                .font(.system(size: 12))
                .foregroundColor(themeManager.colors.textSecondary)
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
        .shadow(color: Color.black.opacity(0.18), radius: 18, x: 0, y: 8)
    }
}

struct EmptyStateCard: View {
    @EnvironmentObject var themeManager: ThemeManager
    let icon: String
    let title: String
    let message: String
    let actionTitle: String
    let action: () -> Void
    
    var body: some View {
        VStack(spacing: 16) {
            Circle()
                .fill(themeManager.isDarkMode 
                    ? Color.white.opacity(0.1) 
                    : Color.black.opacity(0.05))
                .frame(width: 60, height: 60)
                .overlay {
                    Image(systemName: icon)
                        .font(.system(size: 28))
                        .foregroundColor(themeManager.colors.textSecondary)
                }
            
            Text(title)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(themeManager.colors.text)
            
            Text(message)
                .font(.system(size: 14))
                .foregroundColor(themeManager.colors.textSecondary)
                .multilineTextAlignment(.center)
            
            Button(action: action) {
                Text(actionTitle)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(themeManager.colors.primaryText)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(themeManager.colors.primary)
                    .cornerRadius(12)
            }
            .padding(.top, 4)
        }
        .padding(.vertical, 40)
        .padding(.horizontal, 20)
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
    }
}

private struct BookmarkFolderRow: View {
    @EnvironmentObject var themeManager: ThemeManager
    let folder: BookmarkFolder
    let bookmarkCount: Int
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Circle()
                    .fill(themeManager.colors.primary)
                    .frame(width: 40, height: 40)
                    .overlay {
                        Image(systemName: "folder.fill")
                            .font(.system(size: 18))
                            .foregroundColor(themeManager.colors.primaryText)
                    }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(folder.name)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(themeManager.colors.text)
                    
                    Text("\(bookmarkCount) bookmarks")
                        .font(.system(size: 12))
                        .foregroundColor(themeManager.colors.textSecondary)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(themeManager.colors.textSecondary)
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
        .buttonStyle(PlainButtonStyle())
    }
}

private struct BookmarkRowCard: View {
    @EnvironmentObject var themeManager: ThemeManager
    let bookmark: Bookmark
    let folderNameById: [String: String]
    let onTap: () -> Void
    
    private var folderNames: [String] {
        bookmark.folderIds.compactMap { folderNameById[$0] }
    }
    
    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 10) {
                Text(bookmark.text)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(themeManager.colors.text)
                    .lineSpacing(16 * 0.35)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                HStack(spacing: 10) {
                    Text(bookmark.isDescription ? "Summary" : "Chapter \(bookmark.chapterNumber ?? 0)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(themeManager.colors.textSecondary)
                    
                    Text("at \(PlaybackTimeFormatter.string(from: bookmark.startTime))")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(themeManager.colors.textSecondary)
                    
                    Spacer()
                    
                    if bookmark.starred {
                        Image(systemName: "star.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(themeManager.colors.accent)
                    }
                }
                
                if !folderNames.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(folderNames, id: \.self) { name in
                                Text(name)
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(themeManager.colors.text)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(themeManager.colors.card)
                                    .cornerRadius(12)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .strokeBorder(themeManager.colors.cardBorder, lineWidth: 1)
                                    )
                            }
                        }
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
        .buttonStyle(PlainButtonStyle())
    }
}

private struct FolderBookmarksSheet: View {
    @EnvironmentObject var themeManager: ThemeManager
    @EnvironmentObject var bookmarkService: BookmarkService
    @Environment(\.dismiss) private var dismiss
    
    let folder: BookmarkFolder
    let onOpenBookmark: (Bookmark) -> Void
    
    private var bookmarks: [Bookmark] {
        bookmarkService.bookmarks(inFolder: folder.id)
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                themeManager.colors.background.ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 12) {
                        if bookmarks.isEmpty {
                            EmptyStateCard(
                                icon: "bookmark.fill",
                                title: "No Bookmarks in \(folder.name)",
                                message: "Long-press the bookmark icon in the reader to add bookmarks to this folder.",
                                actionTitle: "Close",
                                action: { dismiss() }
                            )
                        } else {
                            ForEach(bookmarks) { b in
                                BookmarkRowCard(
                                    bookmark: b,
                                    folderNameById: Dictionary(uniqueKeysWithValues: bookmarkService.folders.map { ($0.id, $0.name) }),
                                    onTap: {
                                        dismiss()
                                        onOpenBookmark(b)
                                    }
                                )
                            }
                        }
                    }
                    .padding(16)
                    .padding(.bottom, 32)
                }
            }
            .navigationTitle(folder.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") { dismiss() }
                        .foregroundColor(themeManager.colors.primary)
                }
            }
        }
    }
}

struct QuickActionsCard: View {
    @EnvironmentObject var themeManager: ThemeManager
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Quick Actions")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(themeManager.colors.text)
                .padding(.top, 20)
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
            
            QuickActionRow(
                icon: "star.fill",
                title: "Starred Bookmarks",
                subtitle: "View your most important bookmarks",
                iconColor: themeManager.colors.accent
            )
            
            Divider()
                .background(themeManager.colors.divider)
            
            QuickActionRow(
                icon: "clock.fill",
                title: "Reading History",
                subtitle: "See what you've been reading"
            )
            
            Divider()
                .background(themeManager.colors.divider)
            
            QuickActionRow(
                icon: "book.fill",
                title: "Export Bookmarks",
                subtitle: "Save your bookmarks to share or backup"
            )
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
        .shadow(color: Color.black.opacity(0.18), radius: 18, x: 0, y: 8)
    }
}

struct QuickActionRow: View {
    @EnvironmentObject var themeManager: ThemeManager
    let icon: String
    let title: String
    let subtitle: String
    var iconColor: Color?
    
    var body: some View {
        Button(action: {}) {
            HStack(spacing: 12) {
                Circle()
                    .fill(themeManager.isDarkMode 
                        ? Color.white.opacity(0.1) 
                        : Color.black.opacity(0.05))
                    .frame(width: 40, height: 40)
                    .overlay {
                        Image(systemName: icon)
                            .font(.system(size: 20))
                            .foregroundColor(iconColor ?? themeManager.colors.text)
                    }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(themeManager.colors.text)
                    
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundColor(themeManager.colors.textSecondary)
                }
                
                Spacer()
            }
            .padding(.vertical, 16)
            .padding(.horizontal, 20)
        }
    }
}

