//
//  OnboardingWelcomeView.swift
//  ReadBetterApp3.0
//
//  Screen 1: Welcome introduction to Learning Path.
//

import SwiftUI

struct OnboardingWelcomeView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @ObservedObject var viewModel: OnboardingViewModel
    
    @State private var isAnimating = false
    @State private var booksAppeared = false
    
    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            
            // Hero illustration - animated books forming a path
            bookPathIllustration
                .frame(height: 280)
                .padding(.bottom, 40)
            
            // Main headline
            Text("Your Reading Journey\nStarts Here")
                .font(.system(size: 32, weight: .bold))
                .foregroundColor(themeManager.colors.text)
                .multilineTextAlignment(.center)
                .opacity(isAnimating ? 1 : 0)
                .offset(y: isAnimating ? 0 : 20)
            
            // Subheadline
            Text("Create a personalized reading path\ntailored to your interests and goals")
                .font(.system(size: 17))
                .foregroundColor(themeManager.colors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.top, 16)
                .opacity(isAnimating ? 1 : 0)
                .offset(y: isAnimating ? 0 : 20)
            
            Spacer()
            
            // Get Started button
            Button(action: {
                viewModel.nextStep()
            }) {
                HStack(spacing: 8) {
                    Text("Get Started")
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
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
            .opacity(isAnimating ? 1 : 0)
            .offset(y: isAnimating ? 0 : 30)
            
            // Tap hint
            Text("or tap anywhere to continue")
                .font(.system(size: 14))
                .foregroundColor(themeManager.colors.textSecondary.opacity(0.6))
                .padding(.bottom, 40)
                .opacity(isAnimating ? 1 : 0)
        }
        .padding(.horizontal, 24)
        .onAppear {
            startAnimations()
        }
    }
    
    // MARK: - Book Path Illustration
    
    private var bookPathIllustration: some View {
        ZStack {
            // Curved path line
            PathLine()
                .stroke(
                    LinearGradient(
                        colors: [
                            themeManager.colors.primary.opacity(0.3),
                            themeManager.colors.primary.opacity(0.6),
                            themeManager.colors.primary
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [8, 8])
                )
                .frame(width: 300, height: 150)
                .opacity(booksAppeared ? 1 : 0)
            
            // Animated books along the path
            ForEach(0..<5) { index in
                BookIcon(index: index, themeColor: themeManager.colors.primary)
                    .offset(bookOffset(for: index))
                    .scaleEffect(booksAppeared ? 1 : 0.5)
                    .opacity(booksAppeared ? 1 : 0)
                    .animation(
                        .spring(response: 0.6, dampingFraction: 0.7)
                        .delay(Double(index) * 0.15),
                        value: booksAppeared
                    )
            }
            
            // Glowing destination circle
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            themeManager.colors.primary,
                            themeManager.colors.primary.opacity(0.3),
                            Color.clear
                        ],
                        center: .center,
                        startRadius: 5,
                        endRadius: 40
                    )
                )
                .frame(width: 80, height: 80)
                .offset(x: 120, y: 20)
                .opacity(booksAppeared ? 0.8 : 0)
                .scaleEffect(isAnimating ? 1.1 : 0.9)
                .animation(.easeInOut(duration: 2).repeatForever(autoreverses: true), value: isAnimating)
        }
    }
    
    private func bookOffset(for index: Int) -> CGSize {
        let positions: [CGSize] = [
            CGSize(width: -120, height: 40),
            CGSize(width: -60, height: -20),
            CGSize(width: 0, height: 30),
            CGSize(width: 60, height: -10),
            CGSize(width: 100, height: 20)
        ]
        return positions[index]
    }
    
    // MARK: - Animations
    
    private func startAnimations() {
        withAnimation(.easeOut(duration: 0.6)) {
            booksAppeared = true
        }
        
        withAnimation(.easeOut(duration: 0.8).delay(0.3)) {
            isAnimating = true
        }
    }
}

// MARK: - Path Line Shape

private struct PathLine: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        
        path.move(to: CGPoint(x: rect.minX, y: rect.midY + 20))
        path.addCurve(
            to: CGPoint(x: rect.maxX, y: rect.midY),
            control1: CGPoint(x: rect.width * 0.3, y: rect.minY),
            control2: CGPoint(x: rect.width * 0.7, y: rect.maxY)
        )
        
        return path
    }
}

// MARK: - Book Icon

private struct BookIcon: View {
    let index: Int
    let themeColor: Color
    
    private let colors: [Color] = [
        .blue,
        .purple,
        .orange,
        .green,
        .pink
    ]
    
    var body: some View {
        ZStack {
            // Book shadow
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.black.opacity(0.2))
                .frame(width: 32, height: 44)
                .offset(x: 2, y: 2)
            
            // Book cover
            RoundedRectangle(cornerRadius: 4)
                .fill(
                    LinearGradient(
                        colors: [colors[index], colors[index].opacity(0.7)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 32, height: 44)
            
            // Book spine
            Rectangle()
                .fill(colors[index].opacity(0.5))
                .frame(width: 3, height: 44)
                .offset(x: -14)
            
            // Book number
            Text("\(index + 1)")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.white)
        }
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        OnboardingWelcomeView(viewModel: OnboardingViewModel())
    }
    .environmentObject(ThemeManager())
}


