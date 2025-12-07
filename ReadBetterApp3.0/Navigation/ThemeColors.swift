//
//  ThemeColors.swift
//  ReadBetterApp3.0
//
//  Created by Ermin on 30/11/2025.
//

import SwiftUI

struct ThemeColors {
    let background: Color
    let text: Color
    let textSecondary: Color
    let divider: Color
    let card: Color
    let cardBorder: Color
    let primary: Color
    let primaryText: Color
    let accent: Color
    
    // Brand color (always the same)
    static let brand = Color(hex: "#F4D03F")
    
    init(isDarkMode: Bool) {
        if isDarkMode {
            // Dark mode colors
            self.background = Color(hex: "#1c1c1e")
            self.text = Color(hex: "#FFFFFF")
            self.textSecondary = Color(hex: "#999999")
            self.divider = Color(hex: "#333333")
            self.card = Color(hex: "#1E1E1E")
            self.cardBorder = Color(hex: "#444444")
            self.primary = Color(hex: "#FFFFFF")
            self.primaryText = Color(hex: "#121212")
            self.accent = Color(hex: "#FFD700")
        } else {
            // Light mode colors
            self.background = Color(hex: "#F7FAFF")
            self.text = Color(hex: "#1E1F22")
            self.textSecondary = Color(hex: "#9EA2B0")
            self.divider = Color(hex: "#E5E7EB")
            self.card = Color(hex: "#FFFFFF")
            self.cardBorder = Color(hex: "#E6EAF3")
            self.primary = Color(hex: "#0E121B")
            self.primaryText = Color(hex: "#FFFFFF")
            self.accent = Color(hex: "#FFD700")
        }
    }
    
    // Custom initializer for reader-specific themes
    init(background: Color, text: Color, textSecondary: Color, divider: Color, card: Color, cardBorder: Color, primary: Color, primaryText: Color, accent: Color) {
        self.background = background
        self.text = text
        self.textSecondary = textSecondary
        self.divider = divider
        self.card = card
        self.cardBorder = cardBorder
        self.primary = primary
        self.primaryText = primaryText
        self.accent = accent
    }
}

// Extension to create Color from hex string
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

