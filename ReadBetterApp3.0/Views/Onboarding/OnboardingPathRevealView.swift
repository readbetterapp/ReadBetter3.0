//
//  OnboardingPathRevealView.swift
//  ReadBetterApp3.0
//
//  Screen 5: Animated reveal of the generated Learning Path.
//

import SwiftUI

struct OnboardingPathRevealView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @ObservedObject var viewModel: OnboardingViewModel
    
    @State private var revealedBookCount = 0
    @State private var showConfetti = false
    @State private var headerAnimated = false
    
    var body: some View {
        ZStack {
            // Main content
            VStack(spacing: 0) {
                if viewModel.isGeneratingPath {
                    loadingState
                } else if let error = viewModel.generationError {
                    errorState(error)
                } else if let path = viewModel.generatedPath {
                    pathRevealContent(path)
                } else {
                    loadingState
                }
            }
            
            // Confetti overlay
            if showConfetti {
                ConfettiView()
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }
        }
    }
    
    // MARK: - Loading State
    
    private var loadingState: some View {
        VStack(spacing: 24) {
            Spacer()
            
            // Animated loading indicator
            ZStack {
                Circle()
                    .stroke(themeManager.colors.cardBorder, lineWidth: 4)
                    .frame(width: 80, height: 80)
                
                Circle()
                    .trim(from: 0, to: 0.3)
                    .stroke(themeManager.colors.primary, lineWidth: 4)
                    .frame(width: 80, height: 80)
                    .rotationEffect(.degrees(viewModel.isGeneratingPath ? 360 : 0))
                    .animation(.linear(duration: 1).repeatForever(autoreverses: false), value: viewModel.isGeneratingPath)
                
                Image(systemName: "sparkles")
                    .font(.system(size: 28))
                    .foregroundColor(themeManager.colors.primary)
            }
            
            Text("Creating your path...")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(themeManager.colors.text)
            
            Text("Our AI is finding the perfect books for you")
                .font(.system(size: 15))
                .foregroundColor(themeManager.colors.textSecondary)
            
            Spacer()
        }
    }
    
    // MARK: - Error State
    
    private func errorState(_ error: String) -> some View {
        VStack(spacing: 24) {
            Spacer()
            
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 60))
                .foregroundColor(.orange)
            
            Text("Something went wrong")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(themeManager.colors.text)
            
            Text(error)
                .font(.system(size: 15))
                .foregroundColor(themeManager.colors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            
            Button(action: {
                Task {
                    await viewModel.generateLearningPath()
                }
            }) {
                Text("Try Again")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(themeManager.colors.primaryText)
                    .padding(.horizontal, 32)
                    .padding(.vertical, 14)
                    .background(themeManager.colors.primary)
                    .cornerRadius(12)
            }
            
            Spacer()
        }
    }
    
    // MARK: - Path Reveal Content
    
    private func pathRevealContent(_ path: LearningPath) -> some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                // Header
                VStack(spacing: 8) {
                    Text("Your Learning Path")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(themeManager.colors.text)
                    
                    Text("\(path.books.count) books • \(path.availableCount) available now")
                        .font(.system(size: 15))
                        .foregroundColor(themeManager.colors.textSecondary)
                }
                .padding(.top, 24)
                .padding(.bottom, 20)
                .opacity(headerAnimated ? 1 : 0)
                .offset(y: headerAnimated ? 0 : 20)
                
                // Books timeline - ScrollView with proper frame
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        ForEach(Array(path.books.enumerated()), id: \.element.isbn) { index, book in
                            PathBookRow(
                                book: book,
                                index: index,
                                isRevealed: index < revealedBookCount
                            )
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 120) // Space for button
                }
                .frame(maxHeight: .infinity) // Allow ScrollView to take available space
                
                // Start Reading button - fixed at bottom
                startButton
                    .padding(.horizontal, 24)
                    .padding(.bottom, 40)
                    .opacity(revealedBookCount >= path.books.count ? 1 : 0)
                    .offset(y: revealedBookCount >= path.books.count ? 0 : 30)
                    .animation(.spring(response: 0.5, dampingFraction: 0.8), value: revealedBookCount)
            }
            .onAppear {
                startRevealAnimation(bookCount: path.books.count)
            }
        }
    }
    
    // MARK: - Start Button
    
    private var startButton: some View {
        Button(action: {
            viewModel.completeOnboarding()
        }) {
            HStack(spacing: 8) {
                Text("Start Reading")
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
    
    // MARK: - Reveal Animation
    
    private func startRevealAnimation(bookCount: Int) {
        // Animate header first
        withAnimation(.easeOut(duration: 0.5)) {
            headerAnimated = true
        }
        
        // Then reveal books one by one
        for i in 0..<bookCount {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5 + Double(i) * 0.3) {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                    revealedBookCount = i + 1
                }
                
                // Haptic feedback for each book
                let generator = UIImpactFeedbackGenerator(style: .light)
                generator.impactOccurred()
            }
        }
        
        // Show confetti when all books revealed
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5 + Double(bookCount) * 0.3 + 0.3) {
            withAnimation {
                showConfetti = true
            }
            
            // Success haptic
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)
            
            // Hide confetti after a few seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                withAnimation {
                    showConfetti = false
                }
            }
        }
    }
}

// MARK: - Path Book Row

private struct PathBookRow: View {
    @EnvironmentObject var themeManager: ThemeManager
    
    let book: LearningPathBook
    let index: Int
    let isRevealed: Bool
    
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            // Timeline indicator
            VStack(spacing: 0) {
                // Number circle
                ZStack {
                    Circle()
                        .fill(book.available ? themeManager.colors.primary : themeManager.colors.card)
                        .frame(width: 36, height: 36)
                        .overlay(
                            Circle()
                                .stroke(
                                    book.available ? Color.clear : themeManager.colors.cardBorder,
                                    lineWidth: 1
                                )
                        )
                    
                    Text("\(index + 1)")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(
                            book.available
                                ? themeManager.colors.primaryText
                                : themeManager.colors.textSecondary
                        )
                }
                
                // Connecting line
                if index < 4 {
                    Rectangle()
                        .fill(themeManager.colors.cardBorder)
                        .frame(width: 2, height: 80)
                }
            }
            
            // Book card
            HStack(spacing: 14) {
                // Cover
                if let coverUrl = book.coverUrl, let url = URL(string: coverUrl) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        default:
                            coverPlaceholder
                        }
                    }
                    .frame(width: 60, height: 85)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
                } else {
                    coverPlaceholder
                }
                
                // Info
                VStack(alignment: .leading, spacing: 6) {
                    // Availability badge
                    if !book.available {
                        Text("Coming Soon")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.orange)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.orange.opacity(0.15))
                            .cornerRadius(4)
                    }
                    
                    Text(book.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(themeManager.colors.text)
                        .lineLimit(2)
                    
                    Text(book.author)
                        .font(.system(size: 13))
                        .foregroundColor(themeManager.colors.textSecondary)
                        .lineLimit(1)
                    
                    // Reason
                    Text(book.reason)
                        .font(.system(size: 12))
                        .foregroundColor(themeManager.colors.primary)
                        .lineLimit(2)
                        .padding(.top, 2)
                }
                
                Spacer()
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(themeManager.colors.card)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(themeManager.colors.cardBorder, lineWidth: 1)
                    )
            )
        }
        .opacity(isRevealed ? 1 : 0)
        .offset(x: isRevealed ? 0 : 50)
        .scaleEffect(isRevealed ? 1 : 0.9)
    }
    
    private var coverPlaceholder: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(themeManager.colors.cardBorder)
            .frame(width: 60, height: 85)
            .overlay(
                Image(systemName: "book.fill")
                    .font(.system(size: 20))
                    .foregroundColor(themeManager.colors.textSecondary.opacity(0.5))
            )
    }
}

// MARK: - Confetti View

private struct ConfettiView: View {
    @State private var particles: [ConfettiParticle] = []
    
    private let colors: [Color] = [.red, .orange, .yellow, .green, .blue, .purple, .pink]
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                ForEach(particles) { particle in
                    Circle()
                        .fill(particle.color)
                        .frame(width: particle.size, height: particle.size)
                        .position(particle.position)
                        .opacity(particle.opacity)
                }
            }
            .onAppear {
                createParticles(in: geometry.size)
            }
        }
    }
    
    private func createParticles(in size: CGSize) {
        for _ in 0..<50 {
            let particle = ConfettiParticle(
                color: colors.randomElement() ?? .yellow,
                size: CGFloat.random(in: 6...12),
                position: CGPoint(
                    x: CGFloat.random(in: 0...size.width),
                    y: -20
                ),
                opacity: 1.0
            )
            particles.append(particle)
        }
        
        // Animate particles falling
        for i in particles.indices {
            let delay = Double.random(in: 0...0.5)
            let duration = Double.random(in: 2...3)
            
            withAnimation(.easeIn(duration: duration).delay(delay)) {
                particles[i].position.y = size.height + 50
                particles[i].position.x += CGFloat.random(in: -100...100)
            }
            
            withAnimation(.easeIn(duration: duration * 0.8).delay(delay + duration * 0.5)) {
                particles[i].opacity = 0
            }
        }
    }
}

private struct ConfettiParticle: Identifiable {
    let id = UUID()
    let color: Color
    let size: CGFloat
    var position: CGPoint
    var opacity: Double
}

// MARK: - Preview

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        
        let vm = OnboardingViewModel()
        OnboardingPathRevealView(viewModel: vm)
            .onAppear {
                // Simulate generated path
                vm.generatedPath = LearningPath(
                    books: [
                        LearningPathBook(isbn: "1", title: "Atomic Habits", author: "James Clear", coverUrl: nil, position: 1, status: .reading, available: true, reason: "Your starting book"),
                        LearningPathBook(isbn: "2", title: "The 4-Hour Workweek", author: "Tim Ferriss", coverUrl: nil, position: 2, status: .upcoming, available: true, reason: "Similar productivity themes"),
                        LearningPathBook(isbn: "3", title: "Deep Work", author: "Cal Newport", coverUrl: nil, position: 3, status: .upcoming, available: false, reason: "Complements focus strategies"),
                        LearningPathBook(isbn: "4", title: "The Lean Startup", author: "Eric Ries", coverUrl: nil, position: 4, status: .upcoming, available: true, reason: "Build on entrepreneurship"),
                        LearningPathBook(isbn: "5", title: "Zero to One", author: "Peter Thiel", coverUrl: nil, position: 5, status: .upcoming, available: false, reason: "Advanced business thinking"),
                    ],
                    startingBookIsbn: "1"
                )
            }
    }
    .environmentObject(ThemeManager())
}


