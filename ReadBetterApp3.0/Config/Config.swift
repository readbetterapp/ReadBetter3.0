//
//  Config.swift
//  ReadBetterApp3.0
//
//  Configuration values for the app
//

import Foundation

struct Config {
    /// OpenAI API key for daily inspiration quotes
    /// Reads from Info.plist which gets value from Secrets.xcconfig
    static var openAIAPIKey: String {
        #if DEBUG
        // For local development, try environment variable first (Xcode scheme)
        if let envKey = ProcessInfo.processInfo.environment["OPENAI_API_KEY"], !envKey.isEmpty {
            print("📝 Config: Using OpenAI API key from environment variable")
            return envKey
        }
        #endif
        
        // For TestFlight/Release, read from Info.plist (set via xcconfig)
        if let plistKey = Bundle.main.object(forInfoDictionaryKey: "OPENAI_API_KEY") as? String, !plistKey.isEmpty {
            print("📝 Config: Using OpenAI API key from Info.plist")
            return plistKey
        }
        
        print("⚠️ Config: No OpenAI API key found")
        return ""
    }
}


