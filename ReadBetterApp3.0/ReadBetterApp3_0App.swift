//
//  ReadBetterApp3_0App.swift
//  ReadBetterApp3.0
//
//  Created by Ermin on 30/11/2025.
//

import SwiftUI
import FirebaseCore
import FirebaseFirestore
import AVFoundation
import GoogleSignIn
import Kingfisher

class AppDelegate: NSObject, UIApplicationDelegate {
    /// Stored completion handler for background URLSession downloads
    var backgroundSessionCompletionHandler: (() -> Void)?

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {

        // CRITICAL: Configure audio session for background playback FIRST, before anything else.
        // This must happen early, before any AVPlayer is created.
        configureAudioSessionForBackgroundPlayback()

        // Configure Firebase with the correct plist based on bundle ID
        configureFirebase()

        // Configure Kingfisher image cache for optimal performance
        configureKingfisher()

        // Initialize DownloadManager early to reconnect background URLSession
        // This ensures downloads that completed while the app was killed are properly handled
        Task { @MainActor in
            _ = DownloadManager.shared
        }

        return true
    }

    func application(_ application: UIApplication,
                     handleEventsForBackgroundURLSession identifier: String,
                     completionHandler: @escaping () -> Void) {
        if identifier == "com.readbetter.downloads" {
            backgroundSessionCompletionHandler = completionHandler
        }
    }
    
    private func configureFirebase() {
        let bundleID = Bundle.main.bundleIdentifier ?? ""
        var plistName = "GoogleService-Info"
        
        // Select the correct plist based on bundle identifier
        if bundleID.hasSuffix("-dev") {
            plistName = "GoogleService-Info-Dev"
        } else if bundleID.hasSuffix("-beta") {
            plistName = "GoogleService-Info-Beta"
        }
        
        // Check if the plist exists
        guard let filePath = Bundle.main.path(forResource: plistName, ofType: "plist"),
              let options = FirebaseOptions(contentsOfFile: filePath) else {
            print("⚠️ \(plistName).plist not found. Firebase features will be unavailable.")
            print("📥 Download it from: https://console.firebase.google.com/")
            return
        }
        
        FirebaseApp.configure(options: options)
        print("✅ Firebase configured with \(plistName).plist for bundle: \(bundleID)")

        // Enable Firestore offline persistence globally — covers bookmarks, reading progress,
        // and all user data (not just books). Must be set immediately after FirebaseApp.configure,
        // before any Firestore operations, so it applies to the shared singleton.
        let firestoreSettings = FirestoreSettings()
        firestoreSettings.isPersistenceEnabled = true
        firestoreSettings.cacheSizeBytes = FirestoreCacheSizeUnlimited
        Firestore.firestore().settings = firestoreSettings
        print("✅ Firestore offline persistence enabled (unlimited cache)")
    }

    // Google Sign-In callback URL handler
    func application(_ app: UIApplication,
                     open url: URL,
                     options: [UIApplication.OpenURLOptionsKey : Any] = [:]) -> Bool {
        return GIDSignIn.sharedInstance.handle(url)
    }
    
    private func configureKingfisher() {
        // Configure memory cache - 150MB for smooth scrolling with many images
        ImageCache.default.memoryStorage.config.totalCostLimit = 150 * 1024 * 1024 // 150 MB
        
        // Configure disk cache - 500MB for persistent storage
        ImageCache.default.diskStorage.config.sizeLimit = 500 * 1024 * 1024 // 500 MB
        
        // Memory cache expiration - keep images in memory for 10 minutes
        ImageCache.default.memoryStorage.config.expiration = .seconds(600)
        
        // Disk cache expiration - keep images on disk for 7 days
        ImageCache.default.diskStorage.config.expiration = .days(7)
        
        // Enable automatic memory cleanup on memory warning
        ImageCache.default.memoryStorage.config.cleanInterval = 120 // Clean every 2 minutes
        
        print("✅ Kingfisher configured: Memory=150MB, Disk=500MB, Expiration=7days")
    }
    
    private func configureAudioSessionForBackgroundPlayback() {
        do {
            let session = AVAudioSession.sharedInstance()
            // Configure audio session for background playback.
            // This MUST be set before any AVPlayer is created.
            //
            // NOTE: Some option combinations can throw -50 (invalid parameter) depending on device/OS.
            // We prefer A2DP for Bluetooth headphones; `.allowBluetooth` can be rejected for `.playback`
            // on some configurations because it targets HFP (two-way) routing.
            do {
                if #available(iOS 10.0, *) {
                    try session.setCategory(
                        .playback,
                        mode: .spokenAudio,
                        options: [.allowAirPlay, .allowBluetoothA2DP]
                    )
                } else {
                    try session.setCategory(
                        .playback,
                        mode: .spokenAudio,
                        options: [.allowAirPlay]
                    )
                }
            } catch {
                // Fallbacks to keep background playback working even if a mode/options combo is rejected.
                print("⚠️ AVAudioSession launch config failed (will fallback): \(error)")
                do {
                    try session.setCategory(.playback)
                } catch {
                    // Last resort: plain playback, no options
                    try session.setCategory(.playback, options: [])
                }
            }

            try session.setActive(true)
            print("✅ AVAudioSession configured for background playback at app launch. category=\(session.category.rawValue) mode=\(session.mode.rawValue)")
        } catch {
            print("❌ Failed to configure AVAudioSession at app launch: \(error)")
        }
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
