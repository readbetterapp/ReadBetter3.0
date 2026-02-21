//
//  GoalOptionCard.swift
//  ReadBetterApp3.0
//
//  Reading goal selection card for onboarding.
//

import SwiftUI

struct GoalOptionCard: View {
    @EnvironmentObject var themeManager: ThemeManager
    
    let booksPerMonth: Int
    let title: String
    let subtitle: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void
    
    @State private var isPressed = false
    
    var body: some View {
        HStack(spacing: 16) {
            // Icon circle
            ZStack {
                Circle()
                    .fill(
                        isSelected
                            ? themeManager.colors.primary
                            : themeManager.colors.card
                    )
                    .frame(width: 64, height: 64)
                    .overlay(
                        Circle()
                            .stroke(
                                isSelected
                                    ? Color.clear
                                    : themeManager.colors.cardBorder,
                                lineWidth: 1
                            )
                    )
                
                Image(systemName: icon)
                    .font(.system(size: 28))
                    .foregroundColor(
                        isSelected
                            ? themeManager.colors.primaryText
                            : themeManager.colors.textSecondary
                    )
            }
            
            // Text content
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(themeManager.colors.text)
                
                Text(subtitle)
                    .font(.system(size: 15))
                    .foregroundColor(themeManager.colors.textSecondary)
            }
            
            Spacer()
            
            // Selection indicator
            ZStack {
                Circle()
                    .stroke(
                        isSelected
                            ? themeManager.colors.primary
                            : themeManager.colors.cardBorder,
                        lineWidth: 2
                    )
                    .frame(width: 28, height: 28)
                
                if isSelected {
                    Circle()
                        .fill(themeManager.colors.primary)
                        .frame(width: 18, height: 18)
                        .transition(.scale)
                }
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(themeManager.colors.card)
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(
                            isSelected
                                ? themeManager.colors.primary
                                : themeManager.colors.cardBorder,
                            lineWidth: isSelected ? 2 : 1
                        )
                )
        )
        .scaleEffect(isPressed ? 0.98 : 1.0)
        .animation(.easeInOut(duration: 0.1), value: isPressed)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
        .contentShape(Rectangle())
        .onTapGesture {
            action()
        }
        .onLongPressGesture(minimumDuration: 0.5, pressing: { pressing in
            withAnimation(.easeInOut(duration: 0.1)) {
                isPressed = pressing
            }
        }, perform: {
            action()
        })
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        
        VStack(spacing: 16) {
            GoalOptionCard(
                booksPerMonth: 1,
                title: "1 book/month",
                subtitle: "Casual Reader",
                icon: "book",
                isSelected: false,
                action: {}
            )
            
            GoalOptionCard(
                booksPerMonth: 2,
                title: "2-3 books/month",
                subtitle: "Avid Reader",
                icon: "books.vertical",
                isSelected: true,
                action: {}
            )
            
            GoalOptionCard(
                booksPerMonth: 4,
                title: "4+ books/month",
                subtitle: "Book Worm",
                icon: "books.vertical.fill",
                isSelected: false,
                action: {}
            )
        }
        .padding()
    }
    .environmentObject(ThemeManager())
}


