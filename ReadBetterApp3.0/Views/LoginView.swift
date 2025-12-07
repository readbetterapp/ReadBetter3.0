//
//  LoginView.swift
//  ReadBetterApp3.0
//
//  Created by Ermin on 30/11/2025.
//

import SwiftUI

struct LoginView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @EnvironmentObject var router: AppRouter
    @State private var fadeOpacity: Double = 1.0
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background
                themeManager.colors.background
                    .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Back Button
                    HStack {
                        Button(action: {
                            router.navigateBack()
                        }) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 24))
                                .foregroundColor(themeManager.colors.textSecondary)
                        }
                        .padding(.leading, 24)
                        .padding(.top, geometry.safeAreaInsets.top + 20)
                        
                        Spacer()
                    }
                    
                    Spacer()
                    
                    // Main Content
                    VStack(spacing: 0) {
                        // Tagline
                        VStack(spacing: 8) {
                            HStack(spacing: 8) {
                                Text("Intention")
                                    .font(.system(size: 28, weight: .semibold))
                                    .foregroundColor(.black)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 4)
                                    .background(ThemeColors.brand)
                                
                                Text("needs to be followed")
                                    .font(.system(size: 28, weight: .semibold))
                                    .foregroundColor(themeManager.colors.text)
                            }
                            
                            Text("with Attention")
                                .font(.system(size: 28, weight: .semibold))
                                .foregroundColor(themeManager.colors.text)
                        }
                        .padding(.bottom, 60)
                    }
                    .padding(.horizontal, 40)
                    
                    Spacer()
                    
                    // Bottom Section
                    VStack(spacing: 16) {
                        // Sign Up Button
                        Button(action: {
                            // Placeholder - would navigate to sign up
                            router.navigate(to: .tabs)
                        }) {
                            Text("Sign Up")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(.black)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 20)
                                .background(Color.white)
                                .cornerRadius(50)
                                .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)
                        }
                        .padding(.horizontal, 40)
                        
                        // Sign In Button
                        Button(action: {
                            // Placeholder - would navigate to sign in
                            router.navigate(to: .tabs)
                        }) {
                            Text("Sign In")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(.black)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 20)
                                .background(ThemeColors.brand)
                                .cornerRadius(50)
                                .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)
                        }
                        .padding(.horizontal, 40)
                        
                        // Social Login Icons
                        HStack(spacing: 32) {
                            // Google Icon
                            Circle()
                                .fill(ThemeColors.brand)
                                .frame(width: 80, height: 80)
                                .overlay {
                                    Image(systemName: "globe")
                                        .font(.system(size: 24))
                                        .foregroundColor(.black)
                                }
                                .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
                            
                            // Apple Icon
                            Circle()
                                .fill(ThemeColors.brand)
                                .frame(width: 80, height: 80)
                                .overlay {
                                    Image(systemName: "apple.logo")
                                        .font(.system(size: 24))
                                        .foregroundColor(.black)
                                }
                                .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
                        }
                        .padding(.top, 40)
                        .padding(.bottom, 32)
                        
                        // Theme Toggle Button
                        ThemeToggleButton()
                            .padding(.bottom, max(geometry.safeAreaInsets.bottom, 20))
                    }
                }
            }
        }
        .opacity(fadeOpacity)
        .preferredColorScheme(themeManager.isDarkMode ? .dark : .light)
    }
}

