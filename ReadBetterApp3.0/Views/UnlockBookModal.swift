//
//  UnlockBookModal.swift
//  ReadBetterApp3.0
//
//  Created by Ermin on 30/11/2025.
//

import SwiftUI

struct UnlockBookModal: View {
    @EnvironmentObject var themeManager: ThemeManager
    @EnvironmentObject var ownershipService: BookOwnershipService
    
    let book: Book
    @Binding var isPresented: Bool
    @State private var isUnlocking: Bool = false
    @State private var showSuccess: Bool = false
    
    var body: some View {
        ZStack {
            // Backdrop
            Color.black.opacity(0.6)
                .ignoresSafeArea()
                .onTapGesture {
                    if !isUnlocking && !showSuccess {
                        isPresented = false
                    }
                }
            
            // Modal Content
            VStack(spacing: 24) {
                // Close Button
                HStack {
                    Spacer()
                    Button(action: {
                        isPresented = false
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 24))
                            .foregroundColor(themeManager.colors.textSecondary)
                    }
                    .disabled(isUnlocking || showSuccess)
                }
                
                // Book Cover Preview
                if let coverUrl = book.coverUrl, let url = URL(string: coverUrl) {
                    AsyncImage(url: url) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } placeholder: {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(themeManager.colors.card)
                            .overlay {
                                Image(systemName: "book.fill")
                                    .font(.system(size: 30))
                                    .foregroundColor(themeManager.colors.textSecondary)
                            }
                    }
                    .frame(width: 80, height: 110)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .shadow(color: .black.opacity(0.3), radius: 6, x: 2, y: 4)
                }
                
                // Lock Icon & Title
                VStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(themeManager.colors.primary)
                            .frame(width: 48, height: 48)
                        
                        Image(systemName: "lock.fill")
                            .font(.system(size: 20))
                            .foregroundColor(themeManager.colors.primaryText)
                    }
                    
                    Text("Unlock Book")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(themeManager.colors.text)
                    
                    Text(book.title)
                        .font(.system(size: 14))
                        .foregroundColor(themeManager.colors.textSecondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }
                
                // Info text
                Text("Tap below to unlock this book and add it to your library.")
                    .font(.system(size: 14))
                    .foregroundColor(themeManager.colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)
                
                // Unlock Button
                Button(action: {
                    handleUnlock()
                }) {
                    HStack(spacing: 8) {
                        if isUnlocking {
                            ProgressView()
                                .tint(themeManager.colors.primaryText)
                        } else {
                            Image(systemName: "lock.open.fill")
                                .font(.system(size: 16, weight: .semibold))
                        }
                        Text(isUnlocking ? "Unlocking..." : "Unlock Book")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .foregroundColor(themeManager.colors.primaryText)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(themeManager.colors.primary)
                    .cornerRadius(12)
                }
                .disabled(isUnlocking || showSuccess)
                .opacity(isUnlocking ? 0.7 : 1.0)
            }
            .padding(24)
            .background(themeManager.colors.card)
            .cornerRadius(24)
            .overlay(
                RoundedRectangle(cornerRadius: 24)
                    .strokeBorder(themeManager.colors.cardBorder, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 10)
            .padding(.horizontal, 32)
            .scaleEffect(showSuccess ? 0.95 : 1.0)
            .opacity(showSuccess ? 0 : 1.0)
        }
        .overlay {
            if showSuccess {
                UnlockSuccessOverlay(book: book, onComplete: {
                    showSuccess = false
                    isPresented = false
                })
            }
        }
    }
    
    private func handleUnlock() {
        isUnlocking = true
        
        // Small delay for better UX
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            // For testing, always unlock with hardcoded password
            let success = ownershipService.unlockBook(bookId: book.id, password: "unlock")
            
            if success {
                showSuccess = true
            }
            isUnlocking = false
        }
    }
}
