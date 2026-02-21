//
//  CachedBookImage.swift
//  ReadBetterApp3.0
//
//  Displays book cover image from cache or loads on-demand using Kingfisher
//

import SwiftUI
import Kingfisher

struct CachedBookImage: View {
    let url: URL?
    let placeholder: AnyView
    let targetSize: CGSize?
    
    init(url: URL?, placeholder: AnyView = AnyView(ProgressView()), targetSize: CGSize? = nil) {
        self.url = url
        self.placeholder = placeholder
        self.targetSize = targetSize
    }
    
    var body: some View {
        KFImage(url)
            .placeholder { placeholder }
            .fade(duration: 0.2)
            .resizable()
            .cacheMemoryOnly(false) // Cache both memory and disk
            .onSuccess { result in
                // Optional: Track successful loads for analytics
            }
            .onFailure { error in
                print("❌ Image failed to load: \(error.localizedDescription)")
            }
    }
}

