//
//  OnboardingContainerView.swift
//  ReadBetterApp3.0
//
//  Main container for the Instagram Stories-style onboarding flow.
//

import SwiftUI

struct OnboardingContainerView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @StateObject private var viewModel = OnboardingViewModel()
    
    /// Callback when onboarding is completed
    var onComplete: () -> Void
    
    var body: some View {
        ZStack {
            // Background gradient
            backgroundGradient
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Progress bar at top
                progressBar
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                
                // Content area - each view handles its own scrolling
                Group {
                    switch viewModel.currentStep {
                    case 0:
                        OnboardingWelcomeView(viewModel: viewModel)
                    case 1:
                        OnboardingGenresView(viewModel: viewModel)
                    case 2:
                        OnboardingGoalView(viewModel: viewModel)
                    case 3:
                        OnboardingBookPickerView(viewModel: viewModel)
                    case 4:
                        OnboardingPathRevealView(viewModel: viewModel)
                    default:
                        OnboardingWelcomeView(viewModel: viewModel)
                    }
                }
                .id(viewModel.currentStep)
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)
                ))
                .animation(.spring(response: 0.4, dampingFraction: 0.8), value: viewModel.currentStep)
            }
        }
        .onChange(of: viewModel.isCompleted) { _, isCompleted in
            if isCompleted {
                onComplete()
            }
        }
        .environmentObject(viewModel)
    }
    
    // MARK: - Background
    
    private var backgroundGradient: some View {
        LinearGradient(
            colors: [
                themeManager.colors.background,
                themeManager.colors.background.opacity(0.95),
                Color.black.opacity(0.3)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
    
    // MARK: - Progress Bar
    
    private var progressBar: some View {
        StoryProgressBar(
            totalSteps: viewModel.totalSteps,
            currentStep: viewModel.currentStep
        )
    }
}

// MARK: - Preview

#Preview {
    OnboardingContainerView(onComplete: {})
        .environmentObject(ThemeManager())
}


