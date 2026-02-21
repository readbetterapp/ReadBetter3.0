//
//  LoginPromptOverlay.swift
//  ReadBetterApp3.0
//
//  Prompts guests to sign in before purchasing books
//

import SwiftUI

struct LoginPromptOverlay: View {
    @EnvironmentObject var themeManager: ThemeManager
    @EnvironmentObject var router: AppRouter
    @Binding var isPresented: Bool
    
    var body: some View {
        ZStack {
            // Backdrop
            Color.black.opacity(0.6)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        isPresented = false
                    }
                }
            
            // Content Card
            VStack(spacing: 24) {
                // Close Button
                HStack {
                    Spacer()
                    Button(action: {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            isPresented = false
                        }
                    }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(themeManager.colors.textSecondary)
                            .frame(width: 32, height: 32)
                            .background(themeManager.colors.cardBorder)
                            .clipShape(Circle())
                    }
                }
                
                // Icon
                ZStack {
                    Circle()
                        .fill(themeManager.colors.primary.opacity(0.15))
                        .frame(width: 80, height: 80)
                    
                    Image(systemName: "person.badge.key.fill")
                        .font(.system(size: 36))
                        .foregroundColor(themeManager.colors.primary)
                }
                
                // Title & Message
                VStack(spacing: 8) {
                    Text("Sign In Required")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(themeManager.colors.text)
                    
                    Text("Create an account or sign in to unlock books and start your reading journey.")
                        .font(.system(size: 15))
                        .foregroundColor(themeManager.colors.textSecondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                }
                .padding(.horizontal, 8)
                
                // Buttons
                VStack(spacing: 12) {
                    // Sign In Button
                    Button(action: {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            isPresented = false
                        }
                        // Navigate to login
                        router.navigate(to: .login)
                    }) {
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.right.circle.fill")
                                .font(.system(size: 18, weight: .semibold))
                            Text("Sign In / Create Account")
                                .font(.system(size: 16, weight: .semibold))
                        }
                        .foregroundColor(themeManager.colors.primaryText)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(themeManager.colors.primary)
                        .clipShape(Capsule())
                    }
                    
                    // Continue Browsing Button
                    Button(action: {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            isPresented = false
                        }
                    }) {
                        Text("Continue Browsing")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(themeManager.colors.textSecondary)
                    }
                }
            }
            .padding(24)
            .background(themeManager.colors.card)
            .cornerRadius(24)
            .overlay(
                RoundedRectangle(cornerRadius: 24)
                    .strokeBorder(themeManager.colors.cardBorder, lineWidth: 1)
            )
            .padding(.horizontal, 32)
            .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 10)
        }
    }
}
