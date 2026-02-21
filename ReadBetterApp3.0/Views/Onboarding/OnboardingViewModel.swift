//
//  OnboardingViewModel.swift
//  ReadBetterApp3.0
//
//  ViewModel for managing onboarding state and flow.
//

import Foundation
import SwiftUI
import Combine

@MainActor
class OnboardingViewModel: ObservableObject {
    // MARK: - Navigation State
    
    @Published var currentStep: Int = 0
    @Published var isCompleted: Bool = false
    
    /// Total number of onboarding steps
    let totalSteps = 5
    
    // MARK: - User Selections
    
    /// Selected genres (Screen 2)
    @Published var selectedGenres: Set<String> = []
    
    /// Books per month goal (Screen 3)
    @Published var booksPerMonth: Int = 2
    
    /// Selected starting book (Screen 4)
    @Published var selectedBook: Book?
    
    // MARK: - Generated Path
    
    @Published var generatedPath: LearningPath?
    @Published var isGeneratingPath: Bool = false
    @Published var generationError: String?
    
    // MARK: - Services
    
    private let learningPathService = LearningPathService.shared
    private let bookService = BookService.shared
    
    // MARK: - Computed Properties
    
    /// Can proceed to next step
    var canProceed: Bool {
        switch currentStep {
        case 0: // Welcome
            return true
        case 1: // Genres
            return selectedGenres.count >= 1 && selectedGenres.count <= 3
        case 2: // Goal
            return booksPerMonth > 0
        case 3: // Book picker
            return selectedBook != nil
        case 4: // Path reveal
            return generatedPath != nil
        default:
            return false
        }
    }
    
    /// Available books for selection
    var availableBooks: [Book] {
        return bookService.books
    }
    
    /// Progress percentage (0.0 to 1.0)
    var progress: Double {
        return Double(currentStep) / Double(totalSteps - 1)
    }
    
    // MARK: - Navigation
    
    func nextStep() {
        guard currentStep < totalSteps - 1 else {
            completeOnboarding()
            return
        }
        
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            currentStep += 1
        }
        
        // If moving to path reveal screen, generate the path
        if currentStep == 4 {
            Task {
                await generateLearningPath()
            }
        }
    }
    
    func previousStep() {
        guard currentStep > 0 else { return }
        
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            currentStep -= 1
        }
    }
    
    func goToStep(_ step: Int) {
        guard step >= 0 && step < totalSteps else { return }
        
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            currentStep = step
        }
    }
    
    // MARK: - Genre Selection
    
    func toggleGenre(_ genreId: String) {
        if selectedGenres.contains(genreId) {
            selectedGenres.remove(genreId)
        } else if selectedGenres.count < 3 {
            selectedGenres.insert(genreId)
            // Haptic feedback
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.impactOccurred()
        }
    }
    
    func isGenreSelected(_ genreId: String) -> Bool {
        return selectedGenres.contains(genreId)
    }
    
    // MARK: - Goal Selection
    
    func selectGoal(_ books: Int) {
        booksPerMonth = books
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
    }
    
    // MARK: - Book Selection
    
    func selectBook(_ book: Book) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            selectedBook = book
        }
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
    }
    
    // MARK: - Path Generation
    
    func generateLearningPath() async {
        guard let book = selectedBook else {
            generationError = "No book selected"
            return
        }
        
        isGeneratingPath = true
        generationError = nil
        
        do {
            try await learningPathService.generateLearningPath(
                startingBookIsbn: book.id,
                genres: Array(selectedGenres),
                booksPerMonth: booksPerMonth
            )
            
            // Wait a moment for Firestore listener to update
            try await Task.sleep(nanoseconds: 1_500_000_000) // 1.5 seconds
            
            // Get the path from the service
            generatedPath = learningPathService.currentPath
            
            if generatedPath == nil {
                generationError = "Failed to generate path. Please try again."
            }
        } catch {
            generationError = error.localizedDescription
        }
        
        isGeneratingPath = false
    }
    
    // MARK: - Completion
    
    func completeOnboarding() {
        // Save preferences and mark onboarding as complete
        Task {
            do {
                try await learningPathService.completeOnboarding(
                    genres: Array(selectedGenres),
                    booksPerMonth: booksPerMonth
                )
            } catch {
                print("⚠️ Failed to save onboarding preferences: \(error.localizedDescription)")
            }
        }
        
        withAnimation {
            isCompleted = true
        }
    }
    
    // MARK: - Reset
    
    func reset() {
        currentStep = 0
        selectedGenres = []
        booksPerMonth = 2
        selectedBook = nil
        generatedPath = nil
        isGeneratingPath = false
        generationError = nil
        isCompleted = false
    }
}

