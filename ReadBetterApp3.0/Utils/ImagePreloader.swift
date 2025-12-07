//
//  ImagePreloader.swift
//  ReadBetterApp3.0
//
//  Preloads and caches book cover images in background
//

import Foundation
import UIKit
import OSLog
import ImageIO

class ImagePreloader {
    static let shared = ImagePreloader()
    
    // Cache structure: [URL: UIImage] for full images, [String: UIImage] for downsampled (key = "url-thumb-widthxheight")
    private var cache: [String: UIImage] = [:]
    private let cacheQueue = DispatchQueue(label: "com.readbetter.imagepreloader", attributes: .concurrent)
    private let maxConcurrentDownloads = 10 // Increased for faster loading
    private let logger = Logger(subsystem: "com.readbetter", category: "ImagePreloader")
    private var isPreloading = false
    private let preloadQueue = DispatchQueue(label: "com.readbetter.preloadqueue")
    
    // Custom URLSession with higher connection limits for faster image loading
    private lazy var imageSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.httpMaximumConnectionsPerHost = 10 // Allow 10 concurrent connections per host
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        config.requestCachePolicy = .returnCacheDataElseLoad // Use cache when available
        return URLSession(configuration: config)
    }()
    
    private init() {}
    
    /// Downsample image data to target size for efficient decoding
    /// This prevents decoding full-resolution images when only small thumbnails are needed
    private func downsampleImage(data: Data, to size: CGSize, scale: CGFloat = UIScreen.main.scale) -> UIImage? {
        let imageSourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let imageSource = CGImageSourceCreateWithData(data as CFData, imageSourceOptions) else {
            return nil
        }
        
        let maxDimension = max(size.width, size.height) * scale
        let downsampleOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxDimension
        ] as CFDictionary
        
        guard let downsampledImage = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, downsampleOptions) else {
            return nil
        }
        
        return UIImage(cgImage: downsampledImage)
    }
    
    /// Generate cache key for downsampled image
    private func thumbnailCacheKey(for url: URL, size: CGSize) -> String {
        return "\(url.absoluteString)-thumb-\(Int(size.width))x\(Int(size.height))"
    }
    
    func preloadImages(for books: [Book]) async {
        // Prevent duplicate preloading using async-safe approach
        let shouldPreload = await withCheckedContinuation { continuation in
            preloadQueue.async {
                if self.isPreloading {
                    continuation.resume(returning: false)
                } else {
                    self.isPreloading = true
                    continuation.resume(returning: true)
                }
            }
        }
        
        guard shouldPreload else {
            logger.info("🖼️ Image preloading already in progress, skipping duplicate call")
            return
        }
        
        defer {
            preloadQueue.async {
                self.isPreloading = false
            }
        }
        
        // Filter books with valid cover URLs
        let urls = books.compactMap { book -> URL? in
            guard let coverUrl = book.coverUrl,
                  let url = URL(string: coverUrl) else {
                return nil
            }
            // Skip if already cached (check both full and downsampled versions)
            let listViewSize = CGSize(width: 240, height: 360)
            let thumbnailKey = thumbnailCacheKey(for: url, size: listViewSize)
            if getCachedImage(for: url.absoluteString) != nil || getCachedImage(for: thumbnailKey) != nil {
                return nil
            }
            return url
        }
        
        guard !urls.isEmpty else {
            logger.info("No new images to preload (all cached or no valid URLs)")
            return
        }
        
        logger.info("🖼️ Preloading \(urls.count) book cover images in background (max \(self.maxConcurrentDownloads) concurrent)...")
        
        // Preload images at display sizes for list views (SearchView: 120x180, LibraryView: ~200x180)
        // Use larger size to cover both use cases
        let listViewSize = CGSize(width: 240, height: 360) // 2x scale for retina, covers both views
        
        // Preload all images concurrently with downsampling
        await withTaskGroup(of: Void.self) { group in
            for url in urls {
                group.addTask {
                    // Preload at list view size (downsampled)
                    _ = await self.loadImage(url: url, targetSize: listViewSize)
                    // Also preload full size for detail views (lower priority)
                    _ = await self.loadImage(url: url, targetSize: nil)
                }
            }
            // Wait for all tasks to complete
            await group.waitForAll()
        }
        
        logger.info("✅ Preloaded \(urls.count) images")
    }
    
    private func loadImage(url: URL, targetSize: CGSize? = nil) async -> UIImage? {
        // Determine cache key
        let cacheKey: String
        if let size = targetSize {
            cacheKey = thumbnailCacheKey(for: url, size: size)
        } else {
            cacheKey = url.absoluteString
        }
        
        // Check cache first
        if let cached = getCachedImage(for: cacheKey) {
            return cached
        }
        
        // If requesting downsampled version, also check if full image exists
        // We can downsample from full image if available
        if targetSize != nil {
            if let fullImage = getCachedImage(for: url.absoluteString) {
                // Downsample from cached full image
                if let downsampled = await downsampleFromImage(fullImage, to: targetSize!) {
                    setCachedImage(downsampled, for: cacheKey)
                    return downsampled
                }
            }
        }
        
        // Load from network using custom session with higher connection limits
        do {
            let (data, _) = try await imageSession.data(from: url)
            
            // Decode image with downsampling if target size provided
            let image: UIImage?
            if let size = targetSize {
                // Downsample during decode for efficiency
                image = downsampleImage(data: data, to: size)
                if let img = image {
                    setCachedImage(img, for: cacheKey)
                }
                
                // Also cache full image if not already cached (for detail views)
                if getCachedImage(for: url.absoluteString) == nil {
                    if let fullImg = UIImage(data: data) {
                        setCachedImage(fullImg, for: url.absoluteString)
                    }
                }
            } else {
                // Full resolution image
                image = UIImage(data: data)
                if let img = image {
                    setCachedImage(img, for: cacheKey)
                }
            }
            
            return image
        } catch {
            logger.warning("⚠️ Failed to load image from \(url.absoluteString): \(error.localizedDescription)")
        }
        
        return nil
    }
    
    /// Downsample from existing UIImage (used when full image is already cached)
    private func downsampleFromImage(_ image: UIImage, to size: CGSize) async -> UIImage? {
        return await Task.detached(priority: .userInitiated) { [weak self] in
            guard let self = self,
                  let imageData = image.jpegData(compressionQuality: 1.0) else {
                return nil
            }
            return self.downsampleImage(data: imageData, to: size)
        }.value
    }
    
    /// Public method for on-demand image loading (used by CachedBookImage)
    func loadImageDirectly(url: URL, targetSize: CGSize? = nil) async -> UIImage? {
        return await loadImage(url: url, targetSize: targetSize)
    }
    
    func getCachedImage(for url: URL) -> UIImage? {
        return getCachedImage(for: url.absoluteString)
    }
    
    func getCachedImage(for cacheKey: String) -> UIImage? {
        return cacheQueue.sync {
            return cache[cacheKey]
        }
    }
    
    func setCachedImage(_ image: UIImage, for url: URL) {
        setCachedImage(image, for: url.absoluteString)
    }
    
    func setCachedImage(_ image: UIImage, for cacheKey: String) {
        cacheQueue.async(flags: .barrier) {
            self.cache[cacheKey] = image
        }
    }
    
    func clearCache() {
        cacheQueue.async(flags: .barrier) {
            self.cache.removeAll()
        }
    }
}

