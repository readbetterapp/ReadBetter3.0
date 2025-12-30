//
//  PlaybackTimeFormatter.swift
//  ReadBetterApp3.0
//
//  Consistent time formatting across the app:
//  - < 1 hour: M:SS
//  - >= 1 hour: H:MM:SS
//

import Foundation

enum PlaybackTimeFormatter {
    static func string(from seconds: Double) -> String {
        guard seconds.isFinite && seconds >= 0 else { return "0:00" }
        
        let totalSeconds = Int(seconds.rounded(.down))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let secs = totalSeconds % 60
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        } else {
            return String(format: "%d:%02d", minutes, secs)
        }
    }
}


