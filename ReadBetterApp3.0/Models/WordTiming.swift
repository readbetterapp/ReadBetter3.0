//
//  WordTiming.swift
//  ReadBetterApp3.0
//
//  Created by Ermin on 30/11/2025.
//

import Foundation

struct WordTiming: Identifiable, Codable {
    let id: UUID
    let text: String
    let start: Double
    let end: Double
    let index: Int
    let hasLineBreak: Bool // Track if this word should end a sentence/line
    
    init(text: String, start: Double, end: Double, index: Int, hasLineBreak: Bool = false) {
        self.id = UUID()
        self.text = text
        self.start = start
        self.end = end
        self.index = index
        self.hasLineBreak = hasLineBreak
    }
    
    // Support multiple JSON formats
    init?(from json: [String: Any], index: Int) {
        // FILTER 1: Skip words not found in transcript (filler words like "uh", "um")
        if let caseValue = json["case"] as? String, caseValue == "not-found-in-transcript" {
            return nil
        }
        
        // Extract text from various possible fields
        let rawText = json["word"] as? String ??
                     json["text"] as? String ??
                     json["alignedWord"] as? String ??
                     json["value"] as? String ??
                     json["token"] as? String ?? ""
        
        guard !rawText.isEmpty, rawText != "<unk>" else { return nil }
        
        // Check for line breaks (\r\n, \n, \r, etc.)
        // Also check if the word itself is a line break marker
        let hasLineBreak = rawText.contains("\r\n") || 
                          rawText.contains("\n\n") || 
                          rawText.contains("\r") ||
                          rawText.contains("\n") ||
                          rawText == "\\r\\n" ||
                          rawText == "\\n\\n" ||
                          rawText == "\\r" ||
                          rawText == "\\n"
        
        // Clean text but preserve punctuation and spaces
        // Only remove leading/trailing whitespace, keep internal spaces and all punctuation
        var cleanedText = rawText
        // Remove line break characters but mark that we had them
        cleanedText = cleanedText.replacingOccurrences(of: "\r\n", with: " ")
        cleanedText = cleanedText.replacingOccurrences(of: "\n\n", with: " ")
        cleanedText = cleanedText.replacingOccurrences(of: "\r", with: " ")
        cleanedText = cleanedText.replacingOccurrences(of: "\n", with: " ")
        cleanedText = cleanedText.replacingOccurrences(of: "\\r\\n", with: " ")
        cleanedText = cleanedText.replacingOccurrences(of: "\\n\\n", with: " ")
        cleanedText = cleanedText.replacingOccurrences(of: "\\r", with: " ")
        cleanedText = cleanedText.replacingOccurrences(of: "\\n", with: " ")
        cleanedText = cleanedText.trimmingCharacters(in: .whitespaces)
        
        // FILTER 2: Skip punctuation-only tokens (no alphanumeric characters)
        guard !cleanedText.isEmpty else { return nil }
        
        // Check if text contains at least one alphanumeric character
        let alphanumeric = CharacterSet.alphanumerics
        let hasAlphanumeric = cleanedText.unicodeScalars.contains { alphanumeric.contains($0) }
        guard hasAlphanumeric else {
            // This is punctuation-only (like ",", ".", "!", "?", etc.)
            return nil
        }
        
        // Extract start time
        let start: Double
        if let startValue = json["start"] as? Double {
            start = startValue
        } else if let startValue = json["startTime"] as? Double {
            start = startValue
        } else if let startValue = json["begin"] as? Double {
            start = startValue
        } else if let startValue = json["start"] as? String, let parsed = Double(startValue) {
            start = parsed
        } else {
            // No timing - will be estimated later (use -1 as marker)
            start = -1.0
        }
        
        // Extract end time
        let end: Double
        if let endValue = json["end"] as? Double {
            end = endValue
        } else if let endValue = json["endTime"] as? Double {
            end = endValue
        } else if let endValue = json["finish"] as? Double {
            end = endValue
        } else if let endValue = json["end"] as? String, let parsed = Double(endValue) {
            end = parsed
        } else {
            // No timing - will be estimated later (use -1 as marker)
            end = -1.0
        }
        
        self.id = UUID()
        self.text = cleanedText
        self.start = start
        self.end = end
        self.index = index
        self.hasLineBreak = hasLineBreak
    }
}

struct Transcript: Codable {
    let words: [WordTiming]
    let sentences: [Sentence]?
    
    struct Sentence: Codable {
        let text: String
        let words: [WordTiming]?
    }
}

