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
    case descriptionReader(bookId: String)
    case sampleReader(bookId: String)
    case profile
}

class AppRouter: ObservableObject {
    @Published var path: NavigationPath = NavigationPath()
    
    func navigate(to route: AppRoute) {
        path.append(route)
    }
    
    func navigateBack() {
        if !path.isEmpty {
            path.removeLast()
        }
    }
    
    func navigateToRoot() {
        path.removeLast(path.count)
    }
    
    func replace(with route: AppRoute) {
        path.removeLast(path.count)
        path.append(route)
    }
}

