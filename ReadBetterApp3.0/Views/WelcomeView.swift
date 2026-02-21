//
//  WelcomeView.swift
//  ReadBetterApp3.0
//
//  Created by Ermin on 30/11/2025.
//

import SwiftUI

struct WelcomeView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @EnvironmentObject var router: AppRouter
    @State private var currentWordIndex = 0
    @State private var containerWidth: CGFloat = 80
    @State private var containerPadding: CGFloat = 12
    @State private var fadeOpacity: Double = 1.0
    
    // Callback when user skips welcome (handled by RootView)
    var onSkip: (() -> Void)? = nil
    
    private let words = ["book", "idea", "quote", "message", "story"]
    private let wordMetrics: [(width: CGFloat, padding: CGFloat)] = [
        (80, 10),   // book - use message padding (10) for consistent height
        (68, 10),   // idea - use message padding (10) for consistent height
        (88, 10),   // quote - use message padding (10) for consistent height
        (130, 10),  // message - reference height
        (78, 10)    // story - use message padding (10) for consistent height
    ]
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background
                themeManager.colors.background
                    .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Skip Button
                    HStack {
                        Spacer()
                        Button("Skip") {
                            // Use callback if provided, otherwise fallback to navigation
                            if let onSkip = onSkip {
                                onSkip()
                            } else {
                                router.navigate(to: .tabs)
                            }
                        }
                        .foregroundColor(themeManager.colors.textSecondary)
                        .font(.system(size: 16))
                        .padding(.trailing, 24)
                        .padding(.top, geometry.safeAreaInsets.top + 20)
                    }
                    
                    // Spacer for logo area (logo is rendered by RootView persistent layer)
                    Spacer()
                        .frame(height: max(0, geometry.size.height * 0.12 - 150))
                    
                    // Logo placeholder - actual logo rendered by RootView
                    // This spacer reserves the same height as the logo
                    Spacer()
                        .frame(height: 52) // Approximate logo height (36pt font + padding)
                    
                    Spacer()
                    
                    // Tagline with animated word - centered in middle of page
                    VStack(spacing: 0) {
                        HStack(spacing: 4) {
                            Text("the")
                                .font(.system(size: 28, weight: .semibold))
                                .foregroundColor(.black)
                            
                            // Animated word container - fixed height to match "message" size
                            ZStack {
                                ForEach(Array(words.enumerated()), id: \.offset) { index, word in
                                    Text(word)
                                        .font(.system(size: 28, weight: .semibold))
                                        .foregroundColor(.black)
                                        .opacity(index == currentWordIndex ? 1 : 0)
                                        .offset(y: index == currentWordIndex ? 0 : 40)
                                        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: currentWordIndex)
                                }
                            }
                            .frame(width: containerWidth, height: 34)
                            .clipped()
                            
                            Text("you miss,")
                                .font(.system(size: 28, weight: .semibold))
                                .foregroundColor(.black)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(ThemeColors.brand)
                        .padding(.bottom, 4)
                        
                        Text("won't help.")
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundColor(themeManager.colors.text)
                    }
                    .padding(.horizontal, 40)
                    
                    Spacer()
                    
                    // Bottom Section
                    VStack(spacing: 0) {
                        // Get Started Button with iOS 26+ Liquid Glass effect
                        if #available(iOS 26.0, *) {
                            let glassTintColor = themeManager.isDarkMode 
                                ? Color(white: 0.3).opacity(0.4) // Uniform mid-grey for dark mode
                                : Color(white: 0.5).opacity(0.3) // Subtle grey for light mode
                            
                            Button(action: {
                                router.navigate(to: .login)
                            }) {
                                Text("Get Started")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundColor(themeManager.isDarkMode ? .white : .black)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 20)
                            }
                            .glassEffect(.regular.tint(glassTintColor), in: RoundedRectangle(cornerRadius: 50))
                            .padding(.horizontal, 40)
                            .padding(.bottom, 32)
                        } else {
                            // Fallback for iOS 25 and earlier
                            Button(action: {
                                router.navigate(to: .login)
                            }) {
                                Text("Get Started")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundColor(.black)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 20)
                                    .background(ThemeColors.brand)
                                    .cornerRadius(50)
                                    .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)
                            }
                            .padding(.horizontal, 40)
                            .padding(.bottom, 32)
                        }
                        
                        // Theme Toggle Button
                        ThemeToggleButton()
                            .padding(.bottom, max(geometry.safeAreaInsets.bottom, 40))
                    }
                }
            }
        }
        .opacity(fadeOpacity)
        .onAppear {
            startWordAnimation()
        }
    }
    
    private func startWordAnimation() {
        Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { _ in
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                // Update container size first
                let nextIndex = (currentWordIndex + 1) % words.count
                containerWidth = wordMetrics[nextIndex].width
                containerPadding = wordMetrics[nextIndex].padding
                
                // Then update word after a small delay
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    currentWordIndex = nextIndex
                }
            }
        }
    }
}

struct ThemeToggleButton: View {
    @EnvironmentObject var themeManager: ThemeManager
    @State private var fadeOpacity: Double = 1.0
    
    var body: some View {
        Button(action: {
            withAnimation(.easeInOut(duration: 0.2)) {
                fadeOpacity = 0
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                themeManager.toggleDarkMode()
                
                withAnimation(.easeInOut(duration: 0.2)) {
                    fadeOpacity = 1
                }
            }
        }) {
            GlassMorphicView {
                Image(systemName: themeManager.isDarkMode ? "sun.max.fill" : "moon.fill")
                    .font(.system(size: 24))
                    .foregroundColor(themeManager.isDarkMode ? .white : Color(hex: "#1a1a1a"))
            }
            .frame(width: 76, height: 76)
        }
        .opacity(fadeOpacity)
    }
}

