//
//  CachedBookImage.swift
//  ReadBetterApp3.0
//
//  Displays book cover image from cache or loads on-demand using Kingfisher.
//  Falls back to a locally-saved copy (Documents/Downloads/{bookId}/cover.jpg)
//  when Kingfisher fails — e.g. offline after Kingfisher's 7-day disk cache expires.
//

import SwiftUI
import Kingfisher

struct CachedBookImage: View {
    let url: URL?
    let placeholder: AnyView
    let targetSize: CGSize?
    /// Pass the book's ISBN/ID to enable the offline cover-art fallback.
    let bookId: String?

    @State private var fallbackImage: UIImage? = nil

    init(
        url: URL?,
        placeholder: AnyView = AnyView(ProgressView()),
        targetSize: CGSize? = nil,
        bookId: String? = nil
    ) {
        self.url = url
        self.placeholder = placeholder
        self.targetSize = targetSize
        self.bookId = bookId
    }

    var body: some View {
        Group {
            if let fallbackImage {
                // Offline fallback: show the locally-saved cover art
                Image(uiImage: fallbackImage)
                    .resizable()
            } else {
                KFImage(url)
                    .placeholder { placeholder }
                    .fade(duration: 0.2)
                    .resizable()
                    .cacheMemoryOnly(false) // Cache both memory and disk
                    .onSuccess { _ in }
                    .onFailure { error in
                        print("❌ CachedBookImage: Kingfisher failed (\(error.localizedDescription)), trying local cover…")
                        loadLocalCover()
                    }
            }
        }
    }

    // MARK: - Private

    private func loadLocalCover() {
        guard let bookId,
              let localURL = DownloadManager.shared.localCoverURL(bookId: bookId),
              let data = try? Data(contentsOf: localURL),
              let image = UIImage(data: data) else { return }
        fallbackImage = image
        print("✅ CachedBookImage: Loaded local cover for \(bookId)")
    }
}
