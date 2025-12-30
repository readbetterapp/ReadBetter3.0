//
//  LoginView.swift
//  ReadBetterApp3.0
//
//  Created by Ermin on 30/11/2025.
//

import SwiftUI
import AuthenticationServices

struct LoginView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @EnvironmentObject var router: AppRouter
    @EnvironmentObject var authManager: AuthManager
    @State private var fadeOpacity: Double = 1.0
    
    enum EmailAuthMode {
        case signIn
        case signUp
    }
    
    @State private var showEmailSheet: Bool = false
    @State private var emailMode: EmailAuthMode = .signIn
    @State private var awaitingAppleSignIn: Bool = false
    
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
                    
                    Spacer(minLength: 16)
                    
                    // Main Content
                    VStack(spacing: 0) {
                        // Tagline - reader-style text flow with "Intention" highlighted
                        Text("Intention needs to be followed with Attention")
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundColor(themeManager.colors.text)
                            .lineSpacing(24 * 0.4) // Reader-style proportional spacing (fontSize * 0.4)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .overlay(alignment: .leading) {
                                // Highlight "Intention" with yellow background
                                Text("Intention")
                                    .font(.system(size: 24, weight: .semibold))
                                    .foregroundColor(.black)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 3)
                                    .background(ThemeColors.brand)
                                    .cornerRadius(4)
                            }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.bottom, 40)
                    }
                    .padding(.horizontal, 40)
                    
                    Spacer()
                    
                    // Bottom Section
                    VStack(spacing: 16) {
                        // Sign Up Button
                        Button(action: {
                            emailMode = .signUp
                            showEmailSheet = true
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
                            emailMode = .signIn
                            showEmailSheet = true
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
                        
                        // Social login
                        HStack(spacing: 32) {
                            // Apple (left)
                            Button(action: {
                                awaitingAppleSignIn = true
                                authManager.startSignInWithApple()
                            }) {
                                GlassMorphicView {
                                    Image(systemName: "apple.logo")
                                        .font(.system(size: 28, weight: .semibold))
                                        .foregroundColor(themeManager.isDarkMode ? .white : Color(hex: "#1a1a1a"))
                                }
                                .frame(width: 76, height: 76)
                            }
                            
                            // Google (right)
                            Button(action: {
                                Task {
                                    do {
                                        try await authManager.signInWithGoogle()
                                        router.replace(with: .tabs)
                                    } catch {
                                        authManager.lastErrorMessage = error.localizedDescription
                                    }
                                }
                            }) {
                                GlassMorphicView {
                                    GoogleMark()
                                }
                                .frame(width: 76, height: 76)
                            }
                        }
                        .padding(.top, 24)
                        .padding(.bottom, 20)
                        .padding(.horizontal, 40)
                        
                        if let error = authManager.lastErrorMessage {
                            Text(error)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.red)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 40)
                        }
                        
                        // Theme Toggle Button
                        ThemeToggleButton()
                            .padding(.bottom, max(geometry.safeAreaInsets.bottom, 20))
                    }
                }
            }
        }
        .opacity(fadeOpacity)
        .preferredColorScheme(themeManager.isDarkMode ? .dark : .light)
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .onChange(of: authManager.isAnonymous) { oldValue, newValue in
            if awaitingAppleSignIn, oldValue == true, newValue == false {
                awaitingAppleSignIn = false
                router.replace(with: .tabs)
            }
        }
        .onChange(of: authManager.uid) { _, newValue in
            // If the user signed in (or switched accounts) via Apple while already non-anonymous,
            // still complete navigation.
            if awaitingAppleSignIn, newValue != nil, authManager.isAnonymous == false {
                awaitingAppleSignIn = false
                router.replace(with: .tabs)
            }
        }
        .sheet(isPresented: $showEmailSheet) {
            EmailAuthSheet(mode: emailMode) {
                showEmailSheet = false
                router.replace(with: .tabs)
            }
            .environmentObject(themeManager)
            .environmentObject(authManager)
        }
    }
}

private struct GoogleMark: View {
    var body: some View {
        // Approximate the multicolor Google "G" using an angular gradient.
        Text("G")
            .font(.system(size: 34, weight: .bold))
            .foregroundStyle(
                AngularGradient(
                    colors: [
                        Color(hex: "#4285F4"), // blue
                        Color(hex: "#EA4335"), // red
                        Color(hex: "#FBBC05"), // yellow
                        Color(hex: "#34A853"), // green
                        Color(hex: "#4285F4")  // blue
                    ],
                    center: .center
                )
            )
    }
}

private struct EmailAuthSheet: View {
    @EnvironmentObject var themeManager: ThemeManager
    @EnvironmentObject var authManager: AuthManager
    @Environment(\.dismiss) private var dismiss
    
    let mode: LoginView.EmailAuthMode
    let onSuccess: () -> Void
    
    @State private var name: String = ""
    @State private var email: String = ""
    @State private var password: String = ""
    @State private var isWorking: Bool = false
    
    var body: some View {
        NavigationStack {
            ZStack {
                themeManager.colors.background.ignoresSafeArea()
                
                VStack(spacing: 16) {
                    if mode == .signUp {
                        textField(title: "Name", text: $name)
                    }
                    
                    textField(title: "Email", text: $email)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                    
                    SecureField("Password", text: $password)
                        .textInputAutocapitalization(.never)
                        .padding(16)
                        .background(themeManager.colors.card)
                        .cornerRadius(14)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .strokeBorder(themeManager.colors.cardBorder, lineWidth: 1)
                        )
                        .foregroundColor(themeManager.colors.text)
                    
                    Button(action: submit) {
                        HStack(spacing: 10) {
                            if isWorking {
                                ProgressView()
                                    .tint(themeManager.colors.primaryText)
                            }
                            Text(mode == .signUp ? "Create Account" : "Sign In")
                                .font(.system(size: 16, weight: .semibold))
                        }
                        .foregroundColor(themeManager.colors.primaryText)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(themeManager.colors.primary)
                        .cornerRadius(16)
                    }
                    .disabled(isWorking)
                    
                    if let error = authManager.lastErrorMessage {
                        Text(error)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.red)
                            .multilineTextAlignment(.center)
                    }
                    
                    Spacer()
                }
                .padding(16)
            }
            .navigationTitle(mode == .signUp ? "Sign Up" : "Sign In")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
    
    private func textField(title: String, text: Binding<String>) -> some View {
        TextField(title, text: text)
            .padding(16)
            .background(themeManager.colors.card)
            .cornerRadius(14)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(themeManager.colors.cardBorder, lineWidth: 1)
            )
            .foregroundColor(themeManager.colors.text)
    }
    
    private func submit() {
        authManager.lastErrorMessage = nil
        isWorking = true
        
        Task {
            do {
                switch mode {
                case .signIn:
                    try await authManager.signInEmail(email: email, password: password)
                case .signUp:
                    try await authManager.signUpOrLinkAnonymous(email: email, password: password, displayName: name)
                }
                
                await MainActor.run {
                    isWorking = false
                    onSuccess()
                }
            } catch {
                await MainActor.run {
                    isWorking = false
                    authManager.lastErrorMessage = error.localizedDescription
                }
            }
        }
    }
}

