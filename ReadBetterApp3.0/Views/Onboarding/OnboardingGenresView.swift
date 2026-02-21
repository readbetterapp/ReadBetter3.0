//
//  OnboardingGenresView.swift
//  ReadBetterApp3.0
//
//  Screen 2: Genre selection for Learning Path.
//

import SwiftUI

struct OnboardingGenresView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @ObservedObject var viewModel: OnboardingViewModel
    
    @State private var isAnimating = false
    
    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 8) {
                Text("What do you love to read?")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(themeManager.colors.text)
                    .multilineTextAlignment(.center)
                
                Text("Select 1-3 genres that interest you")
                    .font(.system(size: 16))
                    .foregroundColor(themeManager.colors.textSecondary)
            }
            .padding(.top, 32)
            .padding(.bottom, 24)
            .opacity(isAnimating ? 1 : 0)
            .offset(y: isAnimating ? 0 : 20)
            
            // Selection counter
            selectionCounter
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
                .opacity(isAnimating ? 1 : 0)
            
            // Genre grid - ScrollView with fixed frame
            ScrollView(showsIndicators: false) {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(Array(UserPreferences.availableGenres.enumerated()), id: \.element.id) { index, genre in
                        GenreCard(
                            genre: genre,
                            isSelected: viewModel.isGenreSelected(genre.id),
                            action: {
                                viewModel.toggleGenre(genre.id)
                            }
                        )
                        .opacity(isAnimating ? 1 : 0)
                        .offset(y: isAnimating ? 0 : 20)
                        .animation(
                            .spring(response: 0.5, dampingFraction: 0.8)
                            .delay(Double(index) * 0.05),
                            value: isAnimating
                        )
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 100) // Space for button
            }
            .frame(maxHeight: .infinity) // Allow ScrollView to take available space
            
            // Continue button - fixed at bottom
            continueButton
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
                .opacity(isAnimating ? 1 : 0)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.5)) {
                isAnimating = true
            }
        }
    }
    
    // MARK: - Selection Counter
    
    private var selectionCounter: some View {
        HStack(spacing: 8) {
            ForEach(0..<3) { index in
                Circle()
                    .fill(
                        index < viewModel.selectedGenres.count
                            ? themeManager.colors.primary
                            : themeManager.colors.cardBorder
                    )
                    .frame(width: 10, height: 10)
                    .animation(.spring(response: 0.3), value: viewModel.selectedGenres.count)
            }
            
            Text("\(viewModel.selectedGenres.count)/3 selected")
                .font(.system(size: 14))
                .foregroundColor(themeManager.colors.textSecondary)
                .padding(.leading, 8)
        }
    }
    
    // MARK: - Continue Button
    
    private var continueButton: some View {
        Button(action: {
            viewModel.nextStep()
        }) {
            HStack(spacing: 8) {
                Text("Continue")
                    .font(.system(size: 18, weight: .semibold))
                
                Image(systemName: "arrow.right")
                    .font(.system(size: 16, weight: .semibold))
            }
            .foregroundColor(
                viewModel.canProceed
                    ? themeManager.colors.primaryText
                    : themeManager.colors.textSecondary
            )
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(
                viewModel.canProceed
                    ? themeManager.colors.primary
                    : themeManager.colors.card
            )
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(
                        viewModel.canProceed
                            ? Color.clear
                            : themeManager.colors.cardBorder,
                        lineWidth: 1
                    )
            )
        }
        .disabled(!viewModel.canProceed)
        .animation(.easeInOut(duration: 0.2), value: viewModel.canProceed)
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        OnboardingGenresView(viewModel: OnboardingViewModel())
    }
    .environmentObject(ThemeManager())
}


