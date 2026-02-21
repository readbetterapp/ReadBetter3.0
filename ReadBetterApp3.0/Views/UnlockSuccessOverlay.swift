//
//  UnlockSuccessOverlay.swift
//  ReadBetterApp3.0
//
//  Created by Ermin on 30/11/2025.
//

import SwiftUI
import Kingfisher

struct UnlockSuccessOverlay: View {
    @EnvironmentObject var themeManager: ThemeManager
    
    let book: Book
    let onComplete: () -> Void
    
    @State private var scale: CGFloat = 0.5
    @State private var opacity: Double = 0
    @State private var bookScale: CGFloat = 0.8
    @State private var checkScale: CGFloat = 0
    @State private var glowOpacity: Double = 0
    
    var body: some View {
        ZStack {
            // Background
            Color.black.opacity(0.9)
                .ignoresSafeArea()
            
            // Content - Centered with slight upward bias
            VStack(spacing: 0) {
                Spacer()
                    .frame(maxHeight: 60) // Small top spacer
                
                VStack(spacing: 24) {
                    // Book Cover with glow effect behind it
                    ZStack {
                        // Glow effect BEHIND book (same position)
                        Circle()
                            .fill(Color(red: 0.96, green: 0.82, blue: 0.25))
                            .frame(width: 220, height: 220)
                            .opacity(glowOpacity * 0.4)
                            .blur(radius: 50)
                        
                        // Book Cover
                        if let coverUrl = book.coverUrl, let url = URL(string: coverUrl) {
                            KFImage(url)
                                .placeholder {
                                    RoundedRectangle(cornerRadius: 4)
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
                                .frame(width: 140, height: 200)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                                .shadow(color: Color(red: 0.96, green: 0.82, blue: 0.25).opacity(0.5), radius: 20, x: 0, y: 0)
                                .overlay(alignment: .bottomTrailing) {
                                    // Check badge
                                    ZStack {
                                        Circle()
                                            .fill(Color.green)
                                            .frame(width: 48, height: 48)
                                        
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.system(size: 28))
                                            .foregroundColor(.white)
                                    }
                                    .offset(x: -12, y: -12)
                                    .scaleEffect(checkScale)
                                }
                                .scaleEffect(bookScale)
                        }
                    }
                    
                    // Sparkles and Title
                    HStack(spacing: 12) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 20))
                            .foregroundColor(Color(red: 0.96, green: 0.82, blue: 0.25))
                        
                        Text("CONGRATULATIONS")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(Color(red: 0.96, green: 0.82, blue: 0.25))
                            .tracking(2)
                        
                        Image(systemName: "sparkles")
                            .font(.system(size: 20))
                            .foregroundColor(Color(red: 0.96, green: 0.82, blue: 0.25))
                    }
                    
                    // Title
                    Text("Book Unlocked!")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundColor(.white)
                    
                    // Book title
                    Text(book.title)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .padding(.horizontal, 40)
                    
                    // Subtitle
                    Text("Added to your library")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white.opacity(0.5))
                        .padding(.top, 16)
                }
                .scaleEffect(scale)
                .opacity(opacity)
                
                Spacer()
                    .frame(maxHeight: 200) // Larger bottom spacer pushes content up
            }
        }
        .onAppear {
            // Entrance animation
            withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                scale = 1.0
                opacity = 1.0
            }
            
            // Book pop animation
            withAnimation(.spring(response: 0.4, dampingFraction: 0.5).delay(0.1)) {
                bookScale = 1.0
            }
            
            // Check mark animation
            withAnimation(.spring(response: 0.4, dampingFraction: 0.5).delay(0.2)) {
                checkScale = 1.0
            }
            
            // Glow animation
            withAnimation(.easeInOut(duration: 0.5).delay(0.3)) {
                glowOpacity = 1.0
            }
            
            // Auto dismiss after 2.5 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                withAnimation(.easeOut(duration: 0.3)) {
                    opacity = 0
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    onComplete()
                }
            }
        }
    }
}



