//
//  OnboardingGoalView.swift
//  ReadBetterApp3.0
//
//  Screen 3: Reading goal selection for Learning Path.
//

import SwiftUI

struct OnboardingGoalView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @ObservedObject var viewModel: OnboardingViewModel
    
    @State private var isAnimating = false
    
    private let goalOptions: [(books: Int, title: String, subtitle: String, icon: String)] = [
        (1, "1 book/month", "Casual Reader", "book"),
        (2, "2-3 books/month", "Avid Reader", "books.vertical"),
        (4, "4+ books/month", "Book Worm", "books.vertical.fill")
    ]
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 8) {
                Text("How much do you\nwant to read?")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(themeManager.colors.text)
                    .multilineTextAlignment(.center)
                
                Text("We'll create a path that fits your pace")
                    .font(.system(size: 16))
                    .foregroundColor(themeManager.colors.textSecondary)
            }
            .padding(.top, 32)
            .padding(.bottom, 40)
            .opacity(isAnimating ? 1 : 0)
            .offset(y: isAnimating ? 0 : 20)
            
            // Goal options
            VStack(spacing: 16) {
                ForEach(Array(goalOptions.enumerated()), id: \.offset) { index, option in
                    GoalOptionCard(
                        booksPerMonth: option.books,
                        title: option.title,
                        subtitle: option.subtitle,
                        icon: option.icon,
                        isSelected: viewModel.booksPerMonth == option.books,
                        action: {
                            viewModel.selectGoal(option.books)
                        }
                    )
                    .opacity(isAnimating ? 1 : 0)
                    .offset(y: isAnimating ? 0 : 30)
                    .animation(
                        .spring(response: 0.5, dampingFraction: 0.8)
                        .delay(Double(index) * 0.1),
                        value: isAnimating
                    )
                }
            }
            .padding(.horizontal, 24)
            
            Spacer()
            
            // Motivational text
            motivationalText
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
                .opacity(isAnimating ? 1 : 0)
            
            // Continue button
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
    
    // MARK: - Motivational Text
    
    private var motivationalText: some View {
        HStack(spacing: 12) {
            Image(systemName: "lightbulb.fill")
                .font(.system(size: 18))
                .foregroundColor(themeManager.colors.primary)
            
            Text(motivationalMessage)
                .font(.system(size: 14))
                .foregroundColor(themeManager.colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(themeManager.colors.card.opacity(0.5))
        )
        .animation(.easeInOut(duration: 0.3), value: viewModel.booksPerMonth)
    }
    
    private var motivationalMessage: String {
        switch viewModel.booksPerMonth {
        case 1:
            return "Perfect for busy schedules. One great book a month can change your life."
        case 2:
            return "A great balance! You'll explore new ideas while having time to reflect."
        case 4:
            return "You're committed! Get ready for an incredible reading journey."
        default:
            return "Every book is a new adventure waiting to begin."
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
            .foregroundColor(themeManager.colors.primaryText)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(themeManager.colors.primary)
            .cornerRadius(16)
        }
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        OnboardingGoalView(viewModel: OnboardingViewModel())
    }
    .environmentObject(ThemeManager())
}


