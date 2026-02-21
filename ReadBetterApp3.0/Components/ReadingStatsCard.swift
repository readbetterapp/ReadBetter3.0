//
//  ReadingStatsCard.swift
//  ReadBetterApp3.0
//
//  Created for performance optimization - isolated @EnvironmentObject
//

import SwiftUI

struct ReadingStatsCard: View {
    @EnvironmentObject var themeManager: ThemeManager
    @EnvironmentObject var readingStatsService: ReadingStatsService
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Reading Statistics")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(themeManager.colors.text)
            
            // Three metrics in a row
            HStack(spacing: 0) {
                // Streak
                statMetric(
                    icon: "flame.fill",
                    value: "\(readingStatsService.currentStreak)",
                    label: "day streak",
                    iconColor: readingStatsService.isStreakActive ? Color.orange : themeManager.colors.textSecondary.opacity(0.5)
                )
                
                Spacer()
                
                // Divider
                Rectangle()
                    .fill(themeManager.colors.cardBorder)
                    .frame(width: 1, height: 40)
                
                Spacer()
                
                // Weekly Time
                statMetric(
                    icon: "clock.fill",
                    value: readingStatsService.weeklyTimeFormatted,
                    label: "this week",
                    iconColor: themeManager.colors.primary
                )
                
                Spacer()
                
                // Divider
                Rectangle()
                    .fill(themeManager.colors.cardBorder)
                    .frame(width: 1, height: 40)
                
                Spacer()
                
                // Chapters
                statMetric(
                    icon: "book.fill",
                    value: "\(readingStatsService.weeklyChaptersCompleted)",
                    label: "chapters",
                    iconColor: themeManager.colors.primary
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
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
    }
    
    // Helper for stat metrics
    private func statMetric(icon: String, value: String, label: String, iconColor: Color) -> some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundColor(iconColor)
                Text(value)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(themeManager.colors.text)
            }
            Text(label)
                .font(.system(size: 12))
                .foregroundColor(themeManager.colors.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }
}
