//
//  StoryProgressBar.swift
//  ReadBetterApp3.0
//
//  Instagram Stories-style segmented progress bar for onboarding.
//

import SwiftUI

struct StoryProgressBar: View {
    @EnvironmentObject var themeManager: ThemeManager
    
    /// Total number of segments
    let totalSteps: Int
    
    /// Current step (0-indexed)
    let currentStep: Int
    
    /// Progress within current step (0.0 to 1.0), for auto-advancing segments
    var currentStepProgress: CGFloat = 1.0
    
    /// Spacing between segments
    private let spacing: CGFloat = 6
    
    /// Height of progress bar
    private let height: CGFloat = 4
    
    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: spacing) {
                ForEach(0..<totalSteps, id: \.self) { index in
                    SegmentView(
                        index: index,
                        currentStep: currentStep,
                        currentStepProgress: currentStepProgress,
                        height: height,
                        accentColor: themeManager.colors.primary,
                        backgroundColor: themeManager.colors.textSecondary.opacity(0.3)
                    )
                }
            }
        }
        .frame(height: height)
    }
}

// MARK: - Segment View

private struct SegmentView: View {
    let index: Int
    let currentStep: Int
    let currentStepProgress: CGFloat
    let height: CGFloat
    let accentColor: Color
    let backgroundColor: Color
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Background
                RoundedRectangle(cornerRadius: height / 2)
                    .fill(backgroundColor)
                
                // Progress fill
                RoundedRectangle(cornerRadius: height / 2)
                    .fill(accentColor)
                    .frame(width: progressWidth(for: geometry.size.width))
            }
        }
        .animation(.linear(duration: 0.1), value: currentStep)
        .animation(.linear(duration: 0.1), value: currentStepProgress)
    }
    
    private func progressWidth(for totalWidth: CGFloat) -> CGFloat {
        if index < currentStep {
            // Completed step - full width
            return totalWidth
        } else if index == currentStep {
            // Current step - partial width based on progress
            return totalWidth * currentStepProgress
        } else {
            // Future step - no fill
            return 0
        }
    }
}

// MARK: - Animated Story Progress Bar

/// A version that automatically animates through steps with timing
struct AnimatedStoryProgressBar: View {
    @EnvironmentObject var themeManager: ThemeManager
    
    let totalSteps: Int
    @Binding var currentStep: Int
    
    /// Duration for each step in seconds (for auto-advance)
    var stepDuration: TimeInterval = 5.0
    
    /// Whether to auto-advance
    var autoAdvance: Bool = false
    
    /// Callback when a step completes
    var onStepComplete: ((Int) -> Void)?
    
    @State private var progress: CGFloat = 0
    @State private var timer: Timer?
    
    var body: some View {
        StoryProgressBar(
            totalSteps: totalSteps,
            currentStep: currentStep,
            currentStepProgress: progress
        )
        .onAppear {
            if autoAdvance {
                startTimer()
            } else {
                progress = 1.0
            }
        }
        .onDisappear {
            timer?.invalidate()
        }
        .onChange(of: currentStep) { _, _ in
            progress = autoAdvance ? 0 : 1.0
            if autoAdvance {
                startTimer()
            }
        }
    }
    
    private func startTimer() {
        timer?.invalidate()
        progress = 0
        
        let interval: TimeInterval = 0.05
        let increment = CGFloat(interval / stepDuration)
        
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in
            withAnimation(.linear(duration: interval)) {
                progress += increment
            }
            
            if progress >= 1.0 {
                timer?.invalidate()
                onStepComplete?(currentStep)
            }
        }
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        
        VStack(spacing: 40) {
            // Static progress bar examples
            VStack(alignment: .leading, spacing: 8) {
                Text("Step 1 of 5")
                    .foregroundColor(.white)
                StoryProgressBar(totalSteps: 5, currentStep: 0)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Step 3 of 5")
                    .foregroundColor(.white)
                StoryProgressBar(totalSteps: 5, currentStep: 2)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Step 5 of 5 (complete)")
                    .foregroundColor(.white)
                StoryProgressBar(totalSteps: 5, currentStep: 4)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Partial progress")
                    .foregroundColor(.white)
                StoryProgressBar(totalSteps: 5, currentStep: 2, currentStepProgress: 0.6)
            }
        }
        .padding()
    }
    .environmentObject(ThemeManager())
}


