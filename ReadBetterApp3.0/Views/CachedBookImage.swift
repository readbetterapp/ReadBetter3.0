//
//  CachedBookImage.swift
//  ReadBetterApp3.0
//
//  Displays book cover image from cache or loads on-demand
//

import SwiftUI

struct CachedBookImage: View {
    let url: URL?
    let placeholder: AnyView
    let targetSize: CGSize?
    
    @State private var image: UIImage?
    
    init(url: URL?, placeholder: AnyView = AnyView(ProgressView()), targetSize: CGSize? = nil) {
        self.url = url
        self.placeholder = placeholder
        self.targetSize = targetSize
    }
    
    var body: some View {
        Group {
            if let image = image {
                Image(uiImage: image)
                    .resizable()
            } else {
                placeholder
            }
        }
        .task {
            guard let url = url else { return }
            
            // Determine cache key based on target size
            let cacheKey: String
            if let size = targetSize {
                // For downsampled images, use thumbnail cache key
                let width = Int(size.width)
                let height = Int(size.height)
                cacheKey = "\(url.absoluteString)-thumb-\(width)x\(height)"
            } else {
                cacheKey = url.absoluteString
            }
            
            // Check cache first (fast, on main thread is OK)
            if let cached = ImagePreloader.shared.getCachedImage(for: cacheKey) {
                await MainActor.run {
                    image = cached
                }
                return
            }
            
            // If requesting downsampled but not cached, check full image cache
            // and downsample from it if available
            if targetSize != nil {
                if let fullCached = ImagePreloader.shared.getCachedImage(for: url) {
                    // Full image exists, will be downsampled by ImagePreloader
                    // Fall through to load with target size
                }
            }
            
            // Load on-demand in background thread (non-blocking)
            // Use ImagePreloader's optimized session for consistency
            Task.detached(priority: .userInitiated) {
                // Try to load via ImagePreloader with target size for downsampling
                if let loadedImage = await ImagePreloader.shared.loadImageDirectly(url: url, targetSize: targetSize) {
                    await MainActor.run {
                        image = loadedImage
                    }
                }
            }
        }
    }
}

