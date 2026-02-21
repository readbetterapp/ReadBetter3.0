//
//  ProfileView.swift
//  ReadBetterApp3.0
//
//  Created by Ermin on 30/11/2025.
//

import SwiftUI

struct ProfileView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @EnvironmentObject var router: AppRouter
    @EnvironmentObject var authManager: AuthManager
    @State private var booksRead: Int = 0
    @State private var currentlyReading: Int = 0
    @State private var readingTime: String = "0h"
    @State private var isLoadingStats = false
    @State private var isEditingName = false
    @State private var editedName: String = ""
    
    var body: some View {
        ZStack {
            themeManager.colors.background
                .ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: 0) {
                    if let error = authManager.lastErrorMessage {
                        Text(error)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(Color.red)
                            .padding(.horizontal, 16)
                            .padding(.top, 8)
                    }
                    
                    // Header
                    HStack(spacing: 12) {
                        Button(action: {
                            router.navigateBack()
                        }) {
                            Circle()
                                .fill(themeManager.colors.card)
                                .frame(width: 40, height: 40)
                                .overlay {
                                    Image(systemName: "arrow.left")
                                        .font(.system(size: 18, weight: .medium))
                                        .foregroundColor(themeManager.colors.text)
                                }
                                .overlay {
                                    Circle()
                                        .strokeBorder(themeManager.colors.cardBorder, lineWidth: 1)
                                }
                        }
                        
                        Text("Profile")
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundColor(themeManager.colors.text)
                        
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 20)
                    
                    VStack(spacing: 24) {
                        // Profile Card
                        profileCard
                        
                        // Settings Section
                        settingsSection
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 100)
                }
            }
            .scrollIndicators(.hidden)
        }
        .navigationBarBackButtonHidden(true)
        .task {
            await loadUserStats()
        }
        .alert("Edit Name", isPresented: $isEditingName) {
            TextField("Your name", text: $editedName)
            Button("Save") {
                Task {
                    do {
                        try await authManager.updateDisplayName(editedName)
                    } catch {
                        authManager.lastErrorMessage = "Failed to update name: \(error.localizedDescription)"
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This name will appear on your profile and across the app.")
        }
    }
    
    // MARK: - Profile Card
    private var profileCard: some View {
        VStack(spacing: 16) {
            // User Info
            HStack(spacing: 16) {
                // Avatar
                Circle()
                    .fill(themeManager.colors.primary)
                    .frame(width: 60, height: 60)
                    .overlay {
                        Image(systemName: "person.fill")
                            .font(.system(size: 28))
                            .foregroundColor(themeManager.colors.primaryText)
                    }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(authManager.displayName)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(themeManager.colors.text)
                    
                    Text(authSubtitle)
                        .font(.system(size: 14))
                        .foregroundColor(themeManager.colors.textSecondary)
                }
                
                Spacer()
            }
            
            // Divider
            Divider()
                .background(themeManager.colors.divider)
            
            // Stats
            HStack(spacing: 0) {
                // Books Read
                VStack(spacing: 2) {
                    if isLoadingStats {
                        ProgressView()
                            .tint(themeManager.colors.primary)
                    } else {
                        Text("\(booksRead)")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(themeManager.colors.text)
                    }
                    Text("Books Read")
                        .font(.system(size: 12))
                        .foregroundColor(themeManager.colors.textSecondary)
                }
                .frame(maxWidth: .infinity)
                
                // Currently Reading
                VStack(spacing: 2) {
                    if isLoadingStats {
                        ProgressView()
                            .tint(themeManager.colors.primary)
                    } else {
                        Text("\(currentlyReading)")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(themeManager.colors.text)
                    }
                    Text("Currently Reading")
                        .font(.system(size: 12))
                        .foregroundColor(themeManager.colors.textSecondary)
                }
                .frame(maxWidth: .infinity)
                
                // Reading Time
                VStack(spacing: 2) {
                    if isLoadingStats {
                        ProgressView()
                            .tint(themeManager.colors.primary)
                    } else {
                        Text(readingTime)
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(themeManager.colors.text)
                    }
                    Text("Reading Time")
                        .font(.system(size: 12))
                        .foregroundColor(themeManager.colors.textSecondary)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(20)
        .background(themeManager.colors.card)
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(themeManager.colors.cardBorder, lineWidth: 1)
        )
    }
    
    // MARK: - Settings Section
    private var settingsSection: some View {
        VStack(spacing: 0) {
            // Dark Mode Toggle
            Button(action: {
                themeManager.toggleDarkMode()
            }) {
                settingsRow(
                    icon: themeManager.isDarkMode ? "sun.max.fill" : "moon.fill",
                    title: themeManager.isDarkMode ? "Light Mode" : "Dark Mode",
                    color: themeManager.colors.text
                )
            }
            
            Divider()
                .background(themeManager.colors.divider)
            
            // Reading Goals
            Button(action: {
                // Navigate to reading goals
            }) {
                settingsRow(
                    icon: "target",
                    title: "Reading Goals",
                    color: themeManager.colors.text
                )
            }
            
            Divider()
                .background(themeManager.colors.divider)
            
            // Achievements
            Button(action: {
                // Navigate to achievements
            }) {
                settingsRow(
                    icon: "trophy.fill",
                    title: "Achievements",
                    color: themeManager.colors.text
                )
            }
            
            Divider()
                .background(themeManager.colors.divider)
            
            // Settings
            Button(action: {
                // Navigate to settings
            }) {
                settingsRow(
                    icon: "gearshape.fill",
                    title: "Settings",
                    color: themeManager.colors.text
                )
            }
            
            Divider()
                .background(themeManager.colors.divider)
            
            // Edit Name
            Button(action: {
                editedName = authManager.displayName
                isEditingName = true
            }) {
                settingsRow(
                    icon: "person.crop.circle.badge.pencil",
                    title: "Edit Name",
                    color: themeManager.colors.text
                )
            }
            
            Divider()
                .background(themeManager.colors.divider)
            
            if authManager.isAnonymous {
                // Upgrade guest -> account
                Button(action: {
                    router.navigate(to: .login)
                }) {
                    settingsRow(
                        icon: "person.badge.plus",
                        title: "Sign In / Create Account",
                        color: themeManager.colors.text
                    )
                }
            } else {
                // Logout (return to guest)
                Button(action: {
                    Task { await handleLogout() }
                }) {
                    settingsRow(
                        icon: "arrow.right.square.fill",
                        title: "Logout",
                        color: Color.red
                    )
                }
            }
        }
        .background(themeManager.colors.card)
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(themeManager.colors.cardBorder, lineWidth: 1)
        )
    }
    
    private func settingsRow(icon: String, title: String, color: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundColor(color)
                .frame(width: 24)
            
            Text(title)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(color)
            
            Spacer()
        }
        .padding(16)
    }
    
    // MARK: - Actions
    private var authSubtitle: String {
        if authManager.isAnonymous {
            return "Guest • not synced"
        }
        if let email = authManager.email, !email.isEmpty {
            return email
        }
        return "Signed in"
    }
    
    private func handleLogout() async {
        await authManager.signOut()
        router.navigateToRoot()
    }
    
    private func loadUserStats() async {
        isLoadingStats = true
        // TODO: Load actual user stats from API/Firestore
        // For now, using placeholder values
        try? await Task.sleep(nanoseconds: 500_000_000) // Simulate loading
        booksRead = 0
        currentlyReading = 0
        readingTime = "0h"
        isLoadingStats = false
    }
}

