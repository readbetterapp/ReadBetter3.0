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
    
    private let words = ["book", "idea", "quote", "message", "story"]
    private let wordMetrics: [(width: CGFloat, padding: CGFloat)] = [
        (80, 12),   // book
        (68, 14),   // idea
        (88, 11),   // quote
        (130, 10),  // message
        (78, 13)    // story
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
                            router.navigate(to: .tabs)
                        }
                        .foregroundColor(themeManager.colors.textSecondary)
                        .font(.system(size: 16))
                        .padding(.trailing, 24)
                        .padding(.top, geometry.safeAreaInsets.top + 20)
                    }
                    
                    Spacer()
                        .frame(height: geometry.size.height * 0.12)
                    
                    // Main Content
                    VStack(spacing: 0) {
                        // Logo
                        HStack(spacing: 4) {
                            Text("Read")
                                .font(.system(size: 36, weight: .bold))
                                .foregroundColor(.black)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(ThemeColors.brand)
                            
                            Text("Better")
                                .font(.system(size: 36, weight: .bold))
                                .foregroundColor(themeManager.colors.text)
                                .padding(.leading, 8)
                        }
                        .padding(.bottom, 60)
                        
                        // Tagline with animated word
                        VStack(spacing: 0) {
                            HStack(spacing: 8) {
                                Text("the")
                                    .font(.system(size: 28, weight: .semibold))
                                    .foregroundColor(.black)
                                
                                // Animated word container
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
                                .frame(width: containerWidth)
                                .clipped()
                                
                                Text("you miss,")
                                    .font(.system(size: 28, weight: .semibold))
                                    .foregroundColor(.black)
                            }
                            .padding(.horizontal, containerPadding)
                            .padding(.vertical, 4)
                            .background(ThemeColors.brand)
                            .padding(.bottom, 4)
                            
                            Text("won't help.")
                                .font(.system(size: 28, weight: .semibold))
                                .foregroundColor(themeManager.colors.text)
                        }
                        .padding(.bottom, 40)
                    }
                    .padding(.horizontal, 40)
                    
                    Spacer()
                    
                    // Bottom Section
                    VStack(spacing: 0) {
                        // Get Started Button
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

