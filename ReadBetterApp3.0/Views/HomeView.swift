//
//  HomeView.swift
//  ReadBetterApp3.0
//
//  Created by Ermin on 30/11/2025.
//

import SwiftUI

struct HomeView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @State private var scrollOffset: CGFloat = 0
    
    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Header
                HomeHeaderView()
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 12)
                
                // Divider
                Rectangle()
                    .fill(themeManager.colors.divider)
                    .frame(height: 1)
                    .padding(.horizontal, 16)
                
                // Continue Reading Section
                ContinueReadingSection()
                    .padding(.top, 20)
                
                // Inspiration Card
                InspirationCard()
                    .padding(.top, 20)
                
                // Reading Notes Card
                ReadingNotesCard()
                    .padding(.top, 20)
                
                // Learning Path Section
                LearningPathSection()
                    .padding(.top, 20)
                
                // Recently Added Section
                RecentlyAddedSection()
                    .padding(.top, 20)
                
                // Copyright Footer
                CopyrightFooter()
                    .padding(.top, 20)
                    .padding(.bottom, 120) // Extra padding for tab bar
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
        .background(themeManager.colors.background)
    }
}

struct HomeHeaderView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @EnvironmentObject var router: AppRouter
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Good Morning")
                    .font(.system(size: 16))
                    .foregroundColor(themeManager.colors.textSecondary)
                
                Text("Read Better")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(themeManager.colors.text)
            }
            
            Spacer()
            
            Button(action: {
                router.navigate(to: .profile)
            }) {
                Circle()
                    .fill(themeManager.colors.card)
                    .frame(width: 40, height: 40)
                    .overlay {
                        Image(systemName: "person.fill")
                            .foregroundColor(themeManager.colors.text)
                    }
            }
        }
    }
}

struct ContinueReadingSection: View {
    @EnvironmentObject var themeManager: ThemeManager
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Continue Reading")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(themeManager.colors.text)
                .padding(.horizontal, 16)
            
            // Placeholder card
            RoundedRectangle(cornerRadius: 16)
                .fill(
                    LinearGradient(
                        colors: [themeManager.colors.card, themeManager.colors.card.opacity(0.8)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(height: 200)
                .overlay {
                    Text("No book in progress")
                        .foregroundColor(themeManager.colors.textSecondary)
                }
                .padding(.horizontal, 16)
        }
    }
}

struct InspirationCard: View {
    @EnvironmentObject var themeManager: ThemeManager
    
    var body: some View {
        RoundedRectangle(cornerRadius: 16)
            .fill(themeManager.colors.card)
            .frame(height: 120)
            .overlay(alignment: .leading) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Daily Inspiration")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(themeManager.colors.text)
                    
                    Text("The more that you read, the more things you will know. The more that you learn, the more places you'll go.")
                        .font(.system(size: 14))
                        .foregroundColor(themeManager.colors.textSecondary)
                        .lineLimit(3)
                }
                .padding(20)
            }
            .padding(.horizontal, 16)
    }
}

struct ReadingNotesCard: View {
    @EnvironmentObject var themeManager: ThemeManager
    
    var body: some View {
        RoundedRectangle(cornerRadius: 16)
            .fill(themeManager.colors.card)
            .frame(height: 100)
            .overlay(alignment: .leading) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Reading Notes")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(themeManager.colors.text)
                    
                    Text("Your notes will appear here")
                        .font(.system(size: 14))
                        .foregroundColor(themeManager.colors.textSecondary)
                }
                .padding(20)
            }
            .padding(.horizontal, 16)
    }
}

struct LearningPathSection: View {
    @EnvironmentObject var themeManager: ThemeManager
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Learning Path")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(themeManager.colors.text)
                .padding(.horizontal, 16)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(0..<3) { _ in
                        RoundedRectangle(cornerRadius: 12)
                            .fill(themeManager.colors.card)
                            .frame(width: 120, height: 160)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }
}

struct RecentlyAddedSection: View {
    @EnvironmentObject var themeManager: ThemeManager
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Recently Added")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(themeManager.colors.text)
                .padding(.horizontal, 16)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(0..<5) { _ in
                        VStack(alignment: .leading, spacing: 8) {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(themeManager.colors.card)
                                .frame(width: 100, height: 150)
                            
                            Text("Book Title")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(themeManager.colors.text)
                                .lineLimit(2)
                        }
                        .frame(width: 100)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }
}

struct CopyrightFooter: View {
    @EnvironmentObject var themeManager: ThemeManager
    
    var body: some View {
        Text("© 2025 Read Better. All rights reserved.")
            .font(.system(size: 12))
            .foregroundColor(themeManager.colors.textSecondary)
            .padding(.horizontal, 16)
    }
}

