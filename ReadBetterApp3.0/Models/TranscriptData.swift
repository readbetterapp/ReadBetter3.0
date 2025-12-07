//
//  TranscriptData.swift
//  ReadBetterApp3.0
//
//  Created by Ermin on 30/11/2025.
//

import Foundation

struct TranscriptData: Codable {
    let fullText: String
    let sentences: [Sentence]
    let words: [WordTiming]
    
    struct Sentence: Identifiable, Codable {
        let id: UUID
        let text: String
        let wordIndices: [Int] // Indices into words array
        let startTime: Double
        let endTime: Double
        
        init(text: String, wordIndices: [Int], startTime: Double, endTime: Double) {
            self.id = UUID()
            self.text = text
            self.wordIndices = wordIndices
            self.startTime = startTime
            self.endTime = endTime
        }
    }
}







