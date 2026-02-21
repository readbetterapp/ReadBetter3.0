//
//  BookmarkEditSheet.swift
//  ReadBetterApp3.0
//
//  Long-press editor for assigning bookmarks to multiple folders/tags + starring.
//

import SwiftUI

struct BookmarkEditSheet: View {
    @EnvironmentObject var themeManager: ThemeManager
    @EnvironmentObject var bookmarkService: BookmarkService
    @Environment(\.dismiss) private var dismiss
    
    let bookmarkId: String
    
    @State private var selectedFolderIds: Set<String> = []
    @State private var starred: Bool = false
    @State private var newFolderName: String = ""
    @State private var isSaving: Bool = false
    
    private var bookmark: Bookmark? {
        bookmarkService.bookmarkForId(bookmarkId)
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                themeManager.colors.background.ignoresSafeArea()
                
                VStack(spacing: 16) {
                    if let bookmark {
                        // Preview
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Bookmark")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(themeManager.colors.textSecondary)
                            
                            Text(bookmark.text)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(themeManager.colors.text)
                                .lineSpacing(16 * 0.4)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                        .background(themeManager.colors.card)
                        .cornerRadius(16)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .strokeBorder(themeManager.colors.cardBorder, lineWidth: 1)
                        )
                        
                        Toggle(isOn: $starred) {
                            Text("Starred")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(themeManager.colors.text)
                        }
                        .tint(themeManager.colors.primary)
                        .padding(.horizontal, 4)
                        
                        // Create folder
                        HStack(spacing: 10) {
                            TextField("New folder", text: $newFolderName)
                                .textInputAutocapitalization(.words)
                                .padding(12)
                                .background(themeManager.colors.card)
                                .cornerRadius(12)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .strokeBorder(themeManager.colors.cardBorder, lineWidth: 1)
                                )
                                .foregroundColor(themeManager.colors.text)
                            
                            Button("Add") {
                                Task { await createFolderAndSelect() }
                            }
                            .disabled(newFolderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(themeManager.colors.primaryText)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(themeManager.colors.primary)
                            .cornerRadius(12)
                        }
                        
                        // Folder list (multi-select)
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Folders")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(themeManager.colors.textSecondary)
                            
                            ScrollView {
                                VStack(spacing: 10) {
                                    ForEach(bookmarkService.folders) { folder in
                                        folderRow(folder)
                                    }
                                    
                                    if bookmarkService.folders.isEmpty {
                                        Text("No folders yet. Create one above.")
                                            .font(.system(size: 14))
                                            .foregroundColor(themeManager.colors.textSecondary)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .padding(.vertical, 8)
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                            .frame(maxHeight: 260)
                        }
                        
                        Button(action: { Task { await saveAndDismiss() } }) {
                            HStack(spacing: 10) {
                                if isSaving {
                                    ProgressView()
                                        .tint(themeManager.colors.primaryText)
                                }
                                Text("Save")
                                    .font(.system(size: 16, weight: .semibold))
                            }
                            .foregroundColor(themeManager.colors.primaryText)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(themeManager.colors.primary)
                            .cornerRadius(16)
                        }
                        .disabled(isSaving)
                        
                        Spacer()
                    } else {
                        ProgressView()
                            .tint(themeManager.colors.primary)
                        Text("Loading...")
                            .font(.system(size: 14))
                            .foregroundColor(themeManager.colors.textSecondary)
                        Spacer()
                    }
                }
                .padding(16)
            }
            .navigationTitle("Bookmark")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") { dismiss() }
                        .foregroundColor(themeManager.colors.primary)
                }
            }
            .onAppear {
                if let b = bookmark {
                    selectedFolderIds = Set(b.folderIds)
                    starred = b.starred
                }
            }
            .onChange(of: bookmarkService.bookmarksById[bookmarkId]) { _, newValue in
                // Keep editor in sync if the bookmark updates elsewhere.
                if let b = newValue {
                    selectedFolderIds = Set(b.folderIds)
                    starred = b.starred
                }
            }
        }
    }
    
    private func folderRow(_ folder: BookmarkFolder) -> some View {
        Button(action: {
            toggleFolder(folder.id)
        }) {
            HStack(spacing: 12) {
                Text(folder.name)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(themeManager.colors.text)
                
                Spacer()
                
                if selectedFolderIds.contains(folder.id) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(themeManager.colors.primary)
                } else {
                    Image(systemName: "circle")
                        .font(.system(size: 18, weight: .regular))
                        .foregroundColor(themeManager.colors.textSecondary)
                }
            }
            .padding(14)
            .background(themeManager.colors.card)
            .cornerRadius(14)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(themeManager.colors.cardBorder, lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private func toggleFolder(_ folderId: String) {
        if selectedFolderIds.contains(folderId) {
            selectedFolderIds.remove(folderId)
        } else {
            selectedFolderIds.insert(folderId)
        }
    }
    
    @MainActor
    private func createFolderAndSelect() async {
        let name = newFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        do {
            let folder = try await bookmarkService.createFolder(name: name)
            selectedFolderIds.insert(folder.id)
            newFolderName = ""
        } catch {
            bookmarkService.lastErrorMessage = "Create folder failed: \(error.localizedDescription)"
        }
    }
    
    @MainActor
    private func saveAndDismiss() async {
        guard !bookmarkId.isEmpty else { return }
        isSaving = true
        defer { isSaving = false }
        
        do {
            try await bookmarkService.setFolders(bookmarkId: bookmarkId, folderIds: Array(selectedFolderIds))
            try await bookmarkService.setStarred(bookmarkId: bookmarkId, starred: starred)
            dismiss()
        } catch {
            bookmarkService.lastErrorMessage = "Save failed: \(error.localizedDescription)"
        }
    }
}





