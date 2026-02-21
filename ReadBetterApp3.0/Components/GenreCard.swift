//
//  GenreCard.swift
//  ReadBetterApp3.0
//
//  Selectable genre card for onboarding.
//

import SwiftUI

struct GenreCard: View {
    @EnvironmentObject var themeManager: ThemeManager
    
    let genre: GenreOption
    let isSelected: Bool
    let action: () -> Void
    
    @State private var isPressed = false
    
    // Genre-specific gradient colors
    private var gradientColors: [Color] {
        switch genre.id {
        case "fiction":
            return [Color(hex: "#FF6B6B"), Color(hex: "#EE5A5A")]
        case "self-help":
            return [Color(hex: "#4ECDC4"), Color(hex: "#44A08D")]
        case "business":
            return [Color(hex: "#667EEA"), Color(hex: "#764BA2")]
        case "biography":
            return [Color(hex: "#F093FB"), Color(hex: "#F5576C")]
        case "history":
            return [Color(hex: "#4FACFE"), Color(hex: "#00F2FE")]
        case "philosophy":
            return [Color(hex: "#FA709A"), Color(hex: "#FEE140")]
        case "science":
            return [Color(hex: "#30CFD0"), Color(hex: "#330867")]
        case "health":
            return [Color(hex: "#11998E"), Color(hex: "#38EF7D")]
        case "romance":
            return [Color(hex: "#FF0844"), Color(hex: "#FFB199")]
        case "mystery":
            return [Color(hex: "#3D4E81"), Color(hex: "#5753C9")]
        case "fantasy":
            return [Color(hex: "#7F00FF"), Color(hex: "#E100FF")]
        case "psychology":
            return [Color(hex: "#FC6767"), Color(hex: "#FC8181")]
        default:
            return [themeManager.colors.primary, themeManager.colors.primary.opacity(0.7)]
        }
    }
    
    var body: some View {
        VStack(spacing: 12) {
            // Icon
            ZStack {
                Circle()
                    .fill(
                        isSelected 
                            ? LinearGradient(colors: gradientColors, startPoint: .topLeading, endPoint: .bottomTrailing)
                            : LinearGradient(colors: [Color.white.opacity(0.15), Color.white.opacity(0.1)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                    .frame(width: 56, height: 56)
                
                Image(systemName: genre.icon)
                    .font(.system(size: 24))
                    .foregroundColor(isSelected ? .white : themeManager.colors.textSecondary)
            }
            
            // Genre name
            Text(genre.name)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(isSelected ? themeManager.colors.text : themeManager.colors.textSecondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 130)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(themeManager.colors.card)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(
                            isSelected
                                ? LinearGradient(colors: gradientColors, startPoint: .topLeading, endPoint: .bottomTrailing)
                                : LinearGradient(colors: [themeManager.colors.cardBorder], startPoint: .topLeading, endPoint: .bottomTrailing),
                            lineWidth: isSelected ? 2 : 1
                        )
                )
        )
        .scaleEffect(isPressed ? 0.96 : 1.0)
        .scaleEffect(isSelected ? 1.02 : 1.0)
        .animation(.easeInOut(duration: 0.1), value: isPressed)
        .contentShape(Rectangle()) // Make entire area tappable
        .onTapGesture {
            action()
        }
        .onLongPressGesture(minimumDuration: 0.5, pressing: { pressing in
            // This gives us press feedback without blocking scroll
            withAnimation(.easeInOut(duration: 0.1)) {
                isPressed = pressing
            }
        }, perform: {
            // Long press action (optional) - just call action
            action()
        })
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        
        VStack(spacing: 16) {
            HStack(spacing: 16) {
                GenreCard(
                    genre: GenreOption(id: "fiction", name: "Fiction", icon: "book.fill"),
                    isSelected: false,
                    action: {}
                )
                
                GenreCard(
                    genre: GenreOption(id: "self-help", name: "Self-Help", icon: "person.fill.checkmark"),
                    isSelected: true,
                    action: {}
                )
            }
            
            HStack(spacing: 16) {
                GenreCard(
                    genre: GenreOption(id: "business", name: "Business", icon: "chart.line.uptrend.xyaxis"),
                    isSelected: true,
                    action: {}
                )
                
                GenreCard(
                    genre: GenreOption(id: "fantasy", name: "Fantasy", icon: "sparkles"),
                    isSelected: false,
                    action: {}
                )
            }
        }
        .padding()
    }
    .environmentObject(ThemeManager())
}


