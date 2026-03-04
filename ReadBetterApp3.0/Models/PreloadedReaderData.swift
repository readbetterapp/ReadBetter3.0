//
//  PreloadedReaderData.swift
//  ReadBetterApp3.0
//
//  Container for all preloaded reader data
//

import Foundation
import AVFoundation
import SwiftUI

struct PreloadedReaderData {
    let book: Book
    let chapter: Chapter
    let audioURL: URL
    
    // Precomputed for instant rendering - NO rebuilding needed in reader
    let indexedWords: [IndexedWord]
    let sentences: [PrecomputedSentence]
    let totalWords: Int
    let audioDuration: Double?
    
    // OPTIMIZATION: Preloaded asset to avoid duplicate loading
        let audioAsset: AVURLAsset?
        
        // Preloaded cover image and dominant color for instant rendering
        let coverImage: UIImage?
        let coverDominantColor: Color?
        
        init(book: Book, chapter: Chapter, audioURL: URL, indexedWords: [IndexedWord], sentences: [PrecomputedSentence], totalWords: Int, audioDuration: Double? = nil, audioAsset: AVURLAsset? = nil, coverImage: UIImage? = nil, coverDominantColor: Color? = nil) {
            self.book = book
            self.chapter = chapter
            self.audioURL = audioURL
            self.indexedWords = indexedWords
            self.sentences = sentences
            self.totalWords = totalWords
            self.audioDuration = audioDuration
            self.audioAsset = audioAsset
            self.coverImage = coverImage
            self.coverDominantColor = coverDominantColor
        }
}

// Loading state for the reader
enum ReaderLoadingState {
    case idle
    case loadingBook
    case loadingTranscript
    case buildingIndex
    case loadingAudio
    case ready(PreloadedReaderData)
    case error(Error)
    
    var progressText: String {
        switch self {
        case .idle:
            return "Preparing..."
        case .loadingBook:
            return "Loading book..."
        case .loadingTranscript:
            return "Loading transcript..."
        case .buildingIndex:
            return "Matching words to sentences..."
        case .loadingAudio:
            return "Preparing audio..."
        case .ready:
            return "Ready!"
        case .error:
            return "Error loading"
        }
    }
    
    var progress: Double {
        switch self {
        case .idle: return 0.0
        case .loadingBook: return 0.15
        case .loadingTranscript: return 0.30
        case .buildingIndex: return 0.50
        case .loadingAudio: return 0.85
        case .ready: return 1.0
        case .error: return 0.0
        }
    }
}

