//
//  AppRouter.swift
//  ReadBetterApp3.0
//
//  Created by Ermin on 30/11/2025.
//

import SwiftUI
import Combine

enum AppRoute: Hashable {
    case welcome
    case login
    case tabs
    case bookDetails(bookId: String)
    case genre(category: String)
    case reader(bookId: String, chapterNumber: Int?)
    case readerAt(bookId: String, chapterNumber: Int?, startTime: Double?)
    case descriptionReader(bookId: String)
    case descriptionReaderAt(bookId: String, startTime: Double?)
    case sampleReader(bookId: String)
    case profile
}

class AppRouter: ObservableObject {
    @Published var path: NavigationPath = NavigationPath()
    
    // MARK: - Mini Player Expand/Collapse State
    /// Controls whether the reader is expanded from mini player (Spotify-style animation)
    @Published var isReaderExpandedFromMiniPlayer: Bool = false
    
    func navigate(to route: AppRoute) {
        path.append(route)
    }
    
    func navigateBack() {
        if !path.isEmpty {
            path.removeLast()
        }
    }
    
    func navigateBackToTabs() {
        // Clear the path and navigate to tabs to ensure we're at the tabs view
        path.removeLast(path.count)
        path.append(AppRoute.tabs)
    }
    
    func navigateToRoot() {
        path.removeLast(path.count)
    }
    
    func replace(with route: AppRoute) {
        path.removeLast(path.count)
        path.append(route)
    }
    
    // MARK: - Mini Player Reader Expansion
    
    /// Expand reader from mini player with Spotify-style animation
    func expandReaderFromMiniPlayer() {
        withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
            isReaderExpandedFromMiniPlayer = true
        }
    }
    
    /// Collapse reader back to mini player with Spotify-style animation
    func collapseReaderToMiniPlayer() {
        withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
            isReaderExpandedFromMiniPlayer = false
        }
    }
}

