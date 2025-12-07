//
//  ReadBetterApp3_0App.swift
//  ReadBetterApp3.0
//
//  Created by Ermin on 30/11/2025.
//

import SwiftUI
import FirebaseCore

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        // Check if GoogleService-Info.plist exists before configuring Firebase
        if Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil {
            FirebaseApp.configure()
            // Note: Book loading is handled in RootView to avoid duplicate calls
        } else {
            print("⚠️ GoogleService-Info.plist not found. Firebase features will be unavailable.")
            print("📥 Download it from: https://console.firebase.google.com/")
        }
        return true
    }
}

@main
struct ReadBetterApp3_0App: App {
    // Register app delegate for Firebase setup
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    
    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}
