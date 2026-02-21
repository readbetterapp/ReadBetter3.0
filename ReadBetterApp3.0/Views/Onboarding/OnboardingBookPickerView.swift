//
//  OnboardingBookPickerView.swift
//  ReadBetterApp3.0
//
//  Screen 4: Starting book selection for Learning Path.
//

import SwiftUI

struct OnboardingBookPickerView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @ObservedObject var viewModel: OnboardingViewModel
    
    @State private var isAnimating = false
    @State private var searchText = ""
    
    private var filteredBooks: [Book] {
        if searchText.isEmpty {
            return viewModel.availableBooks
        }
        return viewModel.availableBooks.filter { book in
            book.title.localizedCaseInsensitiveContains(searchText) ||
            book.author.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 8) {
                Text("Pick your first book")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(themeManager.colors.text)
                    .multilineTextAlignment(.center)
                
                Text("This will be the start of your journey")
                    .font(.system(size: 16))
                    .foregroundColor(themeManager.colors.textSecondary)
            }
            .padding(.top, 32)
            .padding(.bottom, 24)
            .opacity(isAnimating ? 1 : 0)
            .offset(y: isAnimating ? 0 : 20)
            
            // Search bar
            searchBar
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
                .opacity(isAnimating ? 1 : 0)
            
            // Selected book preview (if any)
            if let selectedBook = viewModel.selectedBook {
                selectedBookPreview(selectedBook)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 20)
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
            
            // Books scroll - horizontal
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 16) {
                    ForEach(Array(filteredBooks.enumerated()), id: \.element.id) { index, book in
                        BookPickerCard(
                            book: book,
                            isSelected: viewModel.selectedBook?.id == book.id,
                            action: {
                                viewModel.selectBook(book)
                            }
                        )
                        .opacity(isAnimating ? 1 : 0)
                        .offset(y: isAnimating ? 0 : 30)
                        .animation(
                            .spring(response: 0.5, dampingFraction: 0.8)
                            .delay(Double(index) * 0.05),
                            value: isAnimating
                        )
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 20)
            }
            .frame(height: 260)
            
            Spacer(minLength: 0) // Flexible spacer
            
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
    
    // MARK: - Search Bar
    
    private var searchBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 18))
                .foregroundColor(themeManager.colors.textSecondary)
            
            TextField("Search books...", text: $searchText)
                .font(.system(size: 16))
                .foregroundColor(themeManager.colors.text)
            
            if !searchText.isEmpty {
                Button(action: { searchText = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(themeManager.colors.textSecondary)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(themeManager.colors.card)
        .cornerRadius(14)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(themeManager.colors.cardBorder, lineWidth: 1)
        )
    }
    
    // MARK: - Selected Book Preview
    
    private func selectedBookPreview(_ book: Book) -> some View {
        HStack(spacing: 16) {
            // Checkmark
            ZStack {
                Circle()
                    .fill(themeManager.colors.primary)
                    .frame(width: 32, height: 32)
                
                Image(systemName: "checkmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(themeManager.colors.primaryText)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Starting with")
                    .font(.system(size: 13))
                    .foregroundColor(themeManager.colors.textSecondary)
                
                Text(book.title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(themeManager.colors.text)
                    .lineLimit(1)
            }
            
            Spacer()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(themeManager.colors.card)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(themeManager.colors.primary.opacity(0.5), lineWidth: 1)
                )
        )
    }
    
    // MARK: - Continue Button
    
    private var continueButton: some View {
        Button(action: {
            viewModel.nextStep()
        }) {
            HStack(spacing: 8) {
                Text("Create My Path")
                    .font(.system(size: 18, weight: .semibold))
                
                Image(systemName: "sparkles")
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

// MARK: - Book Picker Card

struct BookPickerCard: View {
    @EnvironmentObject var themeManager: ThemeManager
    
    let book: Book
    let isSelected: Bool
    let action: () -> Void
    
    @State private var isPressed = false
    
    private let cardWidth: CGFloat = 140
    private let coverHeight: CGFloat = 190
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Book cover
            ZStack(alignment: .topTrailing) {
                if let coverUrl = book.coverUrl, let url = URL(string: coverUrl) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        case .failure(_), .empty:
                            coverPlaceholder
                        @unknown default:
                            coverPlaceholder
                        }
                    }
                    .frame(width: cardWidth, height: coverHeight)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                } else {
                    coverPlaceholder
                }
                
                // Selection indicator
                if isSelected {
                    ZStack {
                        Circle()
                            .fill(themeManager.colors.primary)
                            .frame(width: 28, height: 28)
                        
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(themeManager.colors.primaryText)
                    }
                    .offset(x: -8, y: 8)
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .shadow(color: .black.opacity(0.3), radius: isSelected ? 12 : 6, x: 0, y: 4)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(
                        isSelected ? themeManager.colors.primary : Color.clear,
                        lineWidth: 3
                    )
            )
            
            // Title
            Text(book.title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(themeManager.colors.text)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            
            // Author
            Text(book.author)
                .font(.system(size: 12))
                .foregroundColor(themeManager.colors.textSecondary)
                .lineLimit(1)
        }
        .frame(width: cardWidth)
        .scaleEffect(isPressed ? 0.95 : (isSelected ? 1.03 : 1.0))
        .animation(.easeInOut(duration: 0.1), value: isPressed)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
        .contentShape(Rectangle()) // Make entire area tappable
        .onTapGesture {
            action()
        }
        .onLongPressGesture(minimumDuration: 0.5, pressing: { pressing in
            // This gives us press feedback without blocking scroll
            withAnimation(.easeInOut(duration: 0.1)) {
                isPressed = pressing
            }
        }, perform: {
            // Long press action - just call action
            action()
        })
    }
    
    private var coverPlaceholder: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(themeManager.colors.card)
            .frame(width: cardWidth, height: coverHeight)
            .overlay(
                Image(systemName: "book.fill")
                    .font(.system(size: 40))
                    .foregroundColor(themeManager.colors.textSecondary.opacity(0.3))
            )
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        OnboardingBookPickerView(viewModel: OnboardingViewModel())
    }
    .environmentObject(ThemeManager())
}


