//
//  BackgroundChapterLoader.swift
//  ReadBetterApp3.0
//
//  Runs the full ReaderLoadingView pipeline in the background
//  so chapter transitions work seamlessly from lock screen / background audio
//

import Foundation
import AVFoundation

class BackgroundChapterLoader {
    static let shared = BackgroundChapterLoader()
    private init() {}
    
    private var currentTask: Task<Void, Never>? = nil
    
    func cancelCurrentLoad() {
        currentTask?.cancel()
        currentTask = nil
    }
    
    /// Load the next chapter fully in background (same pipeline as ReaderLoadingView)
    /// On completion, stores result in OptimizedAudioPlayer and starts playback
    func loadAndPlay(bookId: String, chapterNumber: Int) {
        cancelCurrentLoad()
        
        currentTask = Task {
            do {
                try await performLoad(bookId: bookId, chapterNumber: chapterNumber)
            } catch {
                print("❌ BackgroundChapterLoader: Task failed - \(error.localizedDescription)")
            }
        }
    }
    
    private func performLoad(bookId: String, chapterNumber: Int) async throws {
        print("🔄 BackgroundChapterLoader: Starting background load for chapter \(chapterNumber)")
        
        do {
            // Step 1: Fetch book
            guard let book = try await BookService.shared.getBook(isbn: bookId) else {
                print("❌ BackgroundChapterLoader: Book not found")
                return
            }
            
            guard !Task.isCancelled else { return }
            
            // Step 2: Find chapter
            guard let chapter = book.chapters.first(where: { $0.order == chapterNumber - 1 }) else {
                print("❌ BackgroundChapterLoader: Chapter \(chapterNumber) not found")
                return
            }
            
            print("✅ BackgroundChapterLoader: Found chapter '\(chapter.title)'")

            guard !Task.isCancelled else { return }

            // Check for offline downloads — prefer local files over streaming
            let effectiveAudioUrl: String
            let effectiveJsonUrl: String

            if let localAudio = await DownloadManager.shared.localAudioURL(bookId: bookId, chapterOrder: chapter.order),
               let localJson = await DownloadManager.shared.localTranscriptURL(bookId: bookId, chapterOrder: chapter.order) {
                effectiveAudioUrl = localAudio.absoluteString
                effectiveJsonUrl = localJson.absoluteString
                print("📱 BackgroundChapterLoader: Using offline files")
            } else {
                effectiveAudioUrl = chapter.audioUrl
                effectiveJsonUrl = chapter.jsonUrl
            }

            // Step 3: Load transcript
            let transcriptData = try await TranscriptService.shared.loadTranscript(
                from: effectiveJsonUrl,
                bookId: bookId,
                chapterId: chapter.id
            )

            guard !transcriptData.words.isEmpty else {
                print("❌ BackgroundChapterLoader: Empty transcript")
                return
            }

            guard !Task.isCancelled else { return }

            // Step 4: Build KaraokeEngine index (must be on MainActor)
            let engine = KaraokeEngine()
            await MainActor.run {
                engine.buildIndex(from: transcriptData)
            }
            let indexedWords = engine.getIndexedWords()
            let sentences = engine.getSentences()
            let totalWords = engine.getTotalWords()

            guard !indexedWords.isEmpty, !sentences.isEmpty else {
                print("❌ BackgroundChapterLoader: Empty index")
                return
            }

            guard !Task.isCancelled else { return }

            // Step 5: Preload audio asset
            guard let audioURL = URL(string: effectiveAudioUrl) else {
                print("❌ BackgroundChapterLoader: Invalid audio URL")
                return
            }
            
            let asset = AVURLAsset(url: audioURL)
            let duration = try await asset.load(.duration).seconds
            let tracks = try await asset.loadTracks(withMediaType: .audio)
            
            guard !tracks.isEmpty else {
                print("❌ BackgroundChapterLoader: No audio tracks")
                return
            }
            
            guard !Task.isCancelled else { return }
            
            // Step 6: Preload explainable terms (fire and forget)
            ExplainableTermsService.shared.preloadTerms(for: bookId, chapterId: chapter.id)
            
            // Step 7: Build PreloadedReaderData
            let preloadedData = PreloadedReaderData(
                book: book,
                chapter: chapter,
                audioURL: audioURL,
                indexedWords: indexedWords,
                sentences: sentences,
                totalWords: totalWords,
                audioDuration: duration,
                audioAsset: asset
            )
            
            guard !Task.isCancelled else { return }
            
            // Step 8: Hand off to audio player — DO NOT play yet, ReaderLoadingView controls timing
            await OptimizedAudioPlayer.shared.loadForBackgroundAdvance(
                asset: asset,
                preloadedDuration: duration,
                chapterTitle: chapter.title,
                bookTitle: book.title,
                coverURL: book.coverUrl.flatMap { URL(string: $0) },
                bookId: bookId,
                chapterNumber: chapterNumber
            )

            await MainActor.run {
                OptimizedAudioPlayer.shared.setPreloadedData(preloadedData)
                print("✅ BackgroundChapterLoader: Data ready, waiting for UI to trigger play")
                // NOTE: play() is now called by ReaderLoadingView after the nav transition completes
            }
        }
    }
}
