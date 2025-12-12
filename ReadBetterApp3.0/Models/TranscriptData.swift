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
        
        // Custom Codable implementation to handle auto-generated id
        enum CodingKeys: String, CodingKey {
            case id, text, wordIndices, startTime, endTime
        }
        
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            // Generate new id if not present in decoded data
            id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
            text = try container.decode(String.self, forKey: .text)
            wordIndices = try container.decode([Int].self, forKey: .wordIndices)
            startTime = try container.decode(Double.self, forKey: .startTime)
            endTime = try container.decode(Double.self, forKey: .endTime)
        }
        
        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(id, forKey: .id)
            try container.encode(text, forKey: .text)
            try container.encode(wordIndices, forKey: .wordIndices)
            try container.encode(startTime, forKey: .startTime)
            try container.encode(endTime, forKey: .endTime)
        }
    }
}







