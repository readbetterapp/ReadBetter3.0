//
//  ReaderLoadingView.swift
//  ReadBetterApp3.0
//
//  Preloads all reader data before showing the reader.
//  This ensures smooth, skip-free karaoke highlighting.
//

import SwiftUI
import AVFoundation

struct ReaderLoadingView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @EnvironmentObject var router: AppRouter
    
    let bookId: String
    let chapterNumber: Int?
    let isDescription: Bool // Flag to indicate if loading description instead of chapter
    
    @State private var loadingState: ReaderLoadingState = .idle
    @State private var preloadedData: PreloadedReaderData?
    @State private var showReader = false
    
    init(bookId: String, chapterNumber: Int? = nil, isDescription: Bool = false) {
        self.bookId = bookId
        self.chapterNumber = chapterNumber
        self.isDescription = isDescription
    }
    
    var body: some View {
        ZStack {
            themeManager.colors.background
                .ignoresSafeArea()
            
            VStack(spacing: 32) {
                // Book cover placeholder
                RoundedRectangle(cornerRadius: 8)
                    .fill(themeManager.colors.card)
                    .frame(width: 120, height: 180)
                    .overlay {
                        Image(systemName: "book.fill")
                            .font(.system(size: 40))
                            .foregroundColor(themeManager.colors.textSecondary)
                    }
                    .shadow(color: .black.opacity(0.3), radius: 8, x: 2, y: 4)
                
                VStack(spacing: 16) {
                    // Loading text
                    Text(loadingState.progressText)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(themeManager.colors.text)
                    
                    // Progress bar
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(themeManager.colors.card)
                                .frame(height: 8)
                            
                            RoundedRectangle(cornerRadius: 4)
                                .fill(themeManager.colors.primary)
                                .frame(width: geometry.size.width * loadingState.progress, height: 8)
                                .animation(.easeInOut(duration: 0.3), value: loadingState.progress)
                        }
                    }
                    .frame(height: 8)
                    .frame(maxWidth: 200)
                    
                    // Error state
                    if case .error(let error) = loadingState {
                        VStack(spacing: 12) {
                            Text(error.localizedDescription)
                                .font(.system(size: 14))
                                .foregroundColor(.red)
                                .multilineTextAlignment(.center)
                            
                            Button("Try Again") {
                                Task {
                                    await preloadData()
                                }
                            }
                            .foregroundColor(themeManager.colors.primary)
                        }
                        .padding(.top, 8)
                    }
                }
                .padding(.horizontal, 40)
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button(action: {
                    router.navigateBack()
                }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(themeManager.colors.text)
                        .frame(width: 36, height: 36)
                        .background(themeManager.colors.card)
                        .clipShape(Circle())
                }
            }
        }
        .onAppear {
            // CRITICAL: Reset state when view appears to handle chapter navigation
            // This ensures state is fresh even if SwiftUI reuses the view instance
            loadingState = .idle
            preloadedData = nil
            showReader = false
        }
        .task(id: "\(bookId)-\(chapterNumber ?? -1)-\(isDescription)") {
            // Use task with id to ensure it runs when parameters change
            // This handles chapter navigation where bookId might be same but chapterNumber changes
            await preloadData()
        }
        .fullScreenCover(isPresented: $showReader) {
            if let data = preloadedData {
                OptimizedReaderView(preloadedData: data)
                    .environmentObject(themeManager)
                    .environmentObject(router)
            }
        }
    }
    
    // MARK: - Preload All Data
    private func preloadData() async {
        do {
            // Step 1: Load book
            loadingState = .loadingBook
            guard let book = try await BookService.shared.getBook(isbn: bookId) else {
                throw ReaderLoadingError.bookNotFound
            }
            
            // Get chapter or description
            let chapter: Chapter
            let audioUrl: String
            let jsonUrl: String
            
            if isDescription {
                // Loading description instead of chapter
                guard let descAudioUrl = book.descriptionAudioUrl,
                      let descJsonUrl = book.descriptionJsonUrl else {
                    throw ReaderLoadingError.noChapters
                }
                
                // Create a dummy chapter for description
                chapter = Chapter(
                    id: "\(bookId)-description",
                    title: "Summary",
                    audioUrl: descAudioUrl,
                    jsonUrl: descJsonUrl,
                    order: -1
                )
                audioUrl = descAudioUrl
                jsonUrl = descJsonUrl
            } else {
                // Loading regular chapter
                if let chapterNum = chapterNumber,
                   let foundChapter = book.chapters.first(where: { $0.order == chapterNum - 1 }) {
                    chapter = foundChapter
                } else if let firstChapter = book.chapters.sorted(by: { $0.order < $1.order }).first {
                    chapter = firstChapter
                } else {
                    throw ReaderLoadingError.noChapters
                }
                audioUrl = chapter.audioUrl
                jsonUrl = chapter.jsonUrl
            }
            
            // Step 2: Load transcript (direct from GCS, with caching)
            loadingState = .loadingTranscript
            print("📖 Loading \(isDescription ? "description" : "chapter"): \(chapter.title)")
            print("   Audio URL: \(audioUrl)")
            print("   JSON URL: \(jsonUrl)")
            // Direct download and parse (cached for instant subsequent loads)
            let transcriptData = try await TranscriptService.shared.loadTranscript(
                from: jsonUrl,
                bookId: bookId,
                chapterId: chapter.id
            )
            
            guard !transcriptData.words.isEmpty else {
                throw ReaderLoadingError.emptyTranscript
            }
            
            // Step 3: Build index (done once here, not in reader!)
            loadingState = .buildingIndex
            let engine = KaraokeEngine()
            await MainActor.run {
                engine.buildIndex(from: transcriptData)
            }
            let indexedWords = engine.getIndexedWords()
            let sentences = engine.getSentences()
            let totalWords = engine.getTotalWords()
            
            print("✅ ReaderLoadingView: Built index with \(totalWords) words, \(sentences.count) sentences")
            
            // 📋 COMPLETE WORD TIMING MAP - Log all words with their indices and timing
            print("\n" + String(repeating: "=", count: 80))
            print("📋 COMPLETE WORD TIMING MAP")
            print(String(repeating: "=", count: 80))
            for (arrayIndex, word) in indexedWords.enumerated() {
                let status = word.start >= 0 && word.end > word.start && word.start.isFinite && word.end.isFinite ? "✅" : "⚠️"
                let timingInfo = String(format: "%.3f-%.3f", word.start, word.end)
                print("\(status) Array[\(arrayIndex)] | Index: \(word.id) | '\(word.text)' | Time: \(timingInfo)s")
            }
            print(String(repeating: "=", count: 80))
            print("Total: \(indexedWords.count) words in array")
            print("Note: 'Index' is the original JSON index, 'Array' is the sorted position\n")
            
            // Step 4: ACTUALLY PRELOAD AUDIO FILE (not just duration!)
            loadingState = .loadingAudio
            guard let audioURL = URL(string: audioUrl) else {
                throw ReaderLoadingError.invalidAudioURL
            }
            
            print("📥 ReaderLoadingView: Preloading audio file...")
            
            // Create asset and load ALL properties
            let asset = AVURLAsset(url: audioURL)
            
            // Load duration
            let duration = try await asset.load(.duration).seconds
            print("✅ ReaderLoadingView: Audio duration = \(duration) seconds")
            
            // Load track (ensures file is accessible)
            let tracks = try await asset.loadTracks(withMediaType: .audio)
            guard !tracks.isEmpty else {
                throw ReaderLoadingError.invalidAudioURL
            }
            print("✅ ReaderLoadingView: Audio track loaded")
            
            // OPTIMIZATION: Use proper async observation instead of polling
            // Create player item to trigger loading
            let playerItem = AVPlayerItem(asset: asset)
            
            // Wait for player item to be ready using proper observation
            print("⏳ ReaderLoadingView: Waiting for audio to be ready...")
            if playerItem.status != .readyToPlay {
                // Use async observation instead of polling
                await withCheckedContinuation { continuation in
                    var observation: NSKeyValueObservation?
                    observation = playerItem.observe(\.status, options: [.new]) { item, _ in
                        if item.status == .readyToPlay || item.status == .failed {
                            observation?.invalidate()
                            continuation.resume()
                        }
                    }
                    
                    // Timeout after 5 seconds
                    Task {
                        try? await Task.sleep(nanoseconds: 5_000_000_000)
                        observation?.invalidate()
                        continuation.resume()
                    }
                }
            }
            
            if playerItem.status == .readyToPlay {
                print("✅ ReaderLoadingView: Audio is ready to play!")
            } else {
                print("⚠️ ReaderLoadingView: Audio status = \(playerItem.status.rawValue)")
                // Still continue - might be ready by the time reader loads
            }
            
            // Validate all data is ready
            guard !indexedWords.isEmpty, !sentences.isEmpty, totalWords > 0 else {
                throw ReaderLoadingError.emptyTranscript
            }
            
            print("✅ ReaderLoadingView: All data validated")
            print("   - \(totalWords) words indexed")
            print("   - \(sentences.count) sentences prepared")
            print("   - Audio duration: \(duration) seconds")
            
            // Create preloaded data with ALL indexed data + preloaded asset
            let preloadedData = PreloadedReaderData(
                book: book,
                chapter: chapter,
                audioURL: audioURL,
                indexedWords: indexedWords,
                sentences: sentences,
                totalWords: totalWords,
                audioDuration: duration,
                audioAsset: asset  // OPTIMIZATION: Pass preloaded asset to avoid duplicate loading
            )
            
            // Step 5: Ready!
            // Update state on main thread to avoid "modifying state during view update" warning
            await MainActor.run {
                loadingState = .ready(preloadedData)
                self.preloadedData = preloadedData
                showReader = true
            }
            
        } catch {
            // Update state on main thread to avoid "modifying state during view update" warning
            await MainActor.run {
                loadingState = .error(error)
            }
            // Print detailed error for debugging
            print("❌ ReaderLoadingView Error:")
            print("   Book ID: \(bookId)")
            print("   Error: \(error)")
            if let localizedError = error as? LocalizedError {
                print("   Description: \(localizedError.errorDescription ?? "Unknown")")
            }
        }
    }
}

enum ReaderLoadingError: LocalizedError {
    case bookNotFound
    case noChapters
    case emptyTranscript
    case invalidAudioURL
    
    var errorDescription: String? {
        switch self {
        case .bookNotFound:
            return "Book not found"
        case .noChapters:
            return "No chapters available"
        case .emptyTranscript:
            return "Transcript is empty"
        case .invalidAudioURL:
            return "Invalid audio URL"
        }
    }
}

