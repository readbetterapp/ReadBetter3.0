//
//  BookmarksView.swift
//  ReadBetterApp3.0
//
//  Created by Ermin on 30/11/2025.
//

import SwiftUI

struct BookmarksView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @State private var scrollOffset: CGFloat = 0
    
    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
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
                            
                            Button(action: {}) {
                                Image(systemName: "plus")
                                    .font(.system(size: 20))
                                    .foregroundColor(themeManager.colors.primaryText)
                                    .frame(width: 40, height: 40)
                                    .background(themeManager.colors.primary)
                                    .cornerRadius(20)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 12)
                    
                    // Quick Stats
                    HStack(spacing: 12) {
                        StatCard(
                            icon: "bookmark.fill",
                            value: "0",
                            label: "Total Bookmarks"
                        )
                        
                        StatCard(
                            icon: "folder.fill",
                            value: "0",
                            label: "Collections"
                        )
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 28)
                    
                    // Collections Section
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Text("Collections")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundColor(themeManager.colors.text)
                            
                            Spacer()
                            
                            Button("Create New") {
                                // Create collection action
                            }
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(themeManager.colors.primary)
                        }
                        .padding(.horizontal, 16)
                        
                        // Empty Collections State
                        EmptyStateCard(
                            icon: "folder.fill",
                            title: "No Collections Yet",
                            message: "Create collections to organize your bookmarks by topic, series, or any way you like.",
                            actionTitle: "Create First Collection"
                        )
                        .padding(.horizontal, 16)
                    }
                    .padding(.bottom, 32)
                    
                    // Recent Bookmarks Section
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Text("Recent Bookmarks")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundColor(themeManager.colors.text)
                            
                            Spacer()
                            
                            Button("View All") {
                                // View all action
                            }
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(themeManager.colors.primary)
                        }
                        .padding(.horizontal, 16)
                        
                        // Empty Recent Bookmarks State
                        EmptyStateCard(
                            icon: "bookmark.fill",
                            title: "No Bookmarks Yet",
                            message: "Start reading and bookmark your favorite passages to see them here.",
                            actionTitle: "Start Reading"
                        )
                        .padding(.horizontal, 16)
                    }
                    .padding(.bottom, 32)
                    
                // Quick Actions
                QuickActionsCard()
                    .padding(.horizontal, 16)
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
        .background(themeManager.colors.card)
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(themeManager.colors.cardBorder, lineWidth: 1)
        )
    }
}

struct EmptyStateCard: View {
    @EnvironmentObject var themeManager: ThemeManager
    let icon: String
    let title: String
    let message: String
    let actionTitle: String
    
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
            
            Button(action: {}) {
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
        .background(themeManager.colors.card)
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(themeManager.colors.cardBorder, lineWidth: 1)
        )
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
        .background(themeManager.colors.card)
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(themeManager.colors.cardBorder, lineWidth: 1)
        )
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

