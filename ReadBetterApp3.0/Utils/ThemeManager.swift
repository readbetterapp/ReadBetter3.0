//
//  ThemeManager.swift
//  ReadBetterApp3.0
//
//  Created by Ermin on 30/11/2025.
//

import SwiftUI
import Combine

class ThemeManager: ObservableObject {
    @AppStorage("darkMode") private var isDarkModeStorage: Bool = false
    
    @Published var isDarkMode: Bool {
        didSet {
            isDarkModeStorage = isDarkMode
            colors = ThemeColors(isDarkMode: isDarkMode)
        }
    }
    
    @Published var colors: ThemeColors
    
    init() {
        // Initialize with system color scheme if no saved preference
        let systemIsDark = UITraitCollection.current.userInterfaceStyle == .dark
        // Initialize with default value first
        self.isDarkMode = systemIsDark
        self.colors = ThemeColors(isDarkMode: systemIsDark)
        
        // Then check for saved preference and update if needed
        if UserDefaults.standard.object(forKey: "darkMode") != nil {
            // User has a saved preference
            self.isDarkMode = isDarkModeStorage
            self.colors = ThemeColors(isDarkMode: isDarkModeStorage)
        }
    }
    
    func toggleDarkMode() {
        withAnimation {
            isDarkMode.toggle()
        }
    }
    
    func setDarkMode(_ value: Bool) {
        withAnimation {
            isDarkMode = value
        }
    }
}

