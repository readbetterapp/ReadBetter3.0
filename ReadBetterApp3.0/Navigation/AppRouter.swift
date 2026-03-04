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
    
    // MARK: - Back Navigation Signal (TabContainerView observes this)
    /// Used when TabView manages per-tab NavigationStacks (router.path is empty).
    /// Values:
    /// - >0: pop 1 level
    /// - -1: pop to root of current tab
    @Published var backNavigationSignal: Int = 0
    
    // MARK: - Mini Player Expand/Collapse State
    /// Controls whether the reader is expanded from mini player (Spotify-style animation)
    @Published var isReaderExpandedFromMiniPlayer: Bool = false
    
    /// Optional initial seek time for reader overlay (used when opening from ReaderLoadingView)
    var readerOverlayInitialSeekTime: Double? = nil
    var shouldAutoPlayOnLoad: Bool = false
    
    func navigate(to route: AppRoute) {
        path.append(route)
    }
    
    func navigateBack() {
        // If we are inside a real NavigationStack bound to router.path (Welcome/Onboarding),
        // pop there. Otherwise, signal TabContainerView to pop from the current tab stack.
        if !path.isEmpty {
            path.removeLast()
        } else {
            backNavigationSignal += 1
        }
    }
    
    func navigateBackToTabs() {
        // If we're in root navigation context, go to tabs route.
        // If we're in tab navigation context, pop to root of current tab.
        if !path.isEmpty {
            path.removeLast(path.count)
            path.append(AppRoute.tabs)
        } else {
            backNavigationSignal = -1
        }
    }
    
    func navigateToRoot() {
        if !path.isEmpty {
            path.removeLast(path.count)
        } else {
            backNavigationSignal = -1
        }
    }
    
    func replace(with route: AppRoute) {
        if !path.isEmpty {
            path.removeLast(path.count)
            path.append(route)
        } else {
            // Clear current tab stack, then push
            backNavigationSignal = -1
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                self.path.append(route)
            }
        }
    }

    func replaceTop(with route: AppRoute) {
        backNavigationSignal += 1  // pop current reader
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            self.path.append(route)  // push new reader
        }
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

