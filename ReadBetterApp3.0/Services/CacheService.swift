//
//  CacheService.swift
//  ReadBetterApp3.0
//
//  Simple in-memory cache for frequently accessed data
//

import Foundation

// Cache version - increment when parsing logic changes to invalidate old cache
private let CACHE_VERSION = 1

// Wrapper for cached transcript data with version
private struct CachedTranscriptData: Codable {
    let version: Int
    let transcript: TranscriptData
}

class CacheService {
    static let shared = CacheService()
    
    private var bookCache: [String: Book] = [:]
    private var transcriptCache: [String: TranscriptData] = [:]
    private let cacheQueue = DispatchQueue(label: "com.readbetter.cache", attributes: .concurrent)
    
    // Disk cache directory (nonisolated - safe to access from any context)
    private nonisolated(unsafe) let cacheDirectory: URL = {
        let paths = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
        let dir = paths[0].appendingPathComponent("ReadBetterCache", isDirectory: true)
        // Create directory if it doesn't exist
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()
    
    private init() {
        // Load cached transcripts from disk on init (background task)
        Task.detached(priority: .background) { [weak self] in
            self?.loadTranscriptsFromDisk()
        }
    }
    
    // MARK: - Book Caching
    func getCachedBook(isbn: String) -> Book? {
        return cacheQueue.sync {
            return bookCache[isbn]
        }
    }
    
    func cacheBook(_ book: Book, isbn: String) {
        cacheQueue.async(flags: .barrier) {
            self.bookCache[isbn] = book
        }
    }
    
    // MARK: - Transcript Caching (Memory + Disk)
    func getCachedTranscript(url: String) -> TranscriptData? {
        // Check memory cache first (fastest)
        if let cached = cacheQueue.sync(execute: { transcriptCache[url] }) {
            return cached
        }
        
        // Check disk cache (slower but persistent)
        return loadTranscriptFromDisk(url: url)
    }
    
    func cacheTranscript(_ transcript: TranscriptData, url: String) {
        // Cache in memory (fast access)
        updateMemoryCache(transcript: transcript, url: url)
        
        // Also cache to disk for persistence (survives app restarts)
        saveTranscriptToDisk(transcript: transcript, url: url)
    }
    
    // Helper method to update memory cache (can be called from any context)
    private func updateMemoryCache(transcript: TranscriptData, url: String) {
        cacheQueue.async(flags: .barrier) {
            self.transcriptCache[url] = transcript
        }
    }
    
    // MARK: - Disk Cache Helpers
    private nonisolated func saveTranscriptToDisk(transcript: TranscriptData, url: String) {
        let cacheDir = self.cacheDirectory
        Task.detached(priority: .utility) {
            do {
                // Create safe filename from URL (base64 encode to handle special chars)
                let cacheKey = url.data(using: .utf8)?.base64EncodedString() ?? ""
                let safeKey = cacheKey.replacingOccurrences(of: "/", with: "_")
                let fileURL = cacheDir.appendingPathComponent("transcript_\(safeKey).json")
                
                // Wrap transcript with version for cache versioning
                let cachedData = CachedTranscriptData(version: CACHE_VERSION, transcript: transcript)
                
                // Encode in detached task (nonisolated context)
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601
                let data = try encoder.encode(cachedData)
                
                try data.write(to: fileURL)
                print("💾 CacheService: Saved transcript to disk (v\(CACHE_VERSION)): \(fileURL.lastPathComponent)")
            } catch {
                print("⚠️ CacheService: Failed to save transcript to disk: \(error.localizedDescription)")
            }
        }
    }
    
    private nonisolated func loadTranscriptFromDisk(url: String) -> TranscriptData? {
        let cacheDir = self.cacheDirectory
        do {
            // Create same safe filename
            let cacheKey = url.data(using: .utf8)?.base64EncodedString() ?? ""
            let safeKey = cacheKey.replacingOccurrences(of: "/", with: "_")
            let fileURL = cacheDir.appendingPathComponent("transcript_\(safeKey).json")
            
            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                return nil
            }
            
            let data = try Data(contentsOf: fileURL)
            // Decode in nonisolated context
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            
            // Try to decode as versioned cache first
            if let cachedData = try? decoder.decode(CachedTranscriptData.self, from: data) {
                // Check version - if old version, invalidate cache
                if cachedData.version != CACHE_VERSION {
                    print("⚠️ CacheService: Old cache version (\(cachedData.version) vs \(CACHE_VERSION)), invalidating: \(fileURL.lastPathComponent)")
                    try? FileManager.default.removeItem(at: fileURL)
                    return nil
                }
                
                // Valid version - load into memory cache
                Task.detached(priority: .utility) {
                    self.cacheQueue.async(flags: .barrier) {
                        self.transcriptCache[url] = cachedData.transcript
                    }
                }
                
                print("💾 CacheService: Loaded transcript from disk (v\(cachedData.version)): \(fileURL.lastPathComponent)")
                return cachedData.transcript
            }
            
            // Fallback: Try to decode as old format (no version) - invalidate it
            if let _ = try? decoder.decode(TranscriptData.self, from: data) {
                print("⚠️ CacheService: Old cache format (no version), invalidating: \(fileURL.lastPathComponent)")
                try? FileManager.default.removeItem(at: fileURL)
                return nil
            }
            
            // Invalid format - delete it
            try? FileManager.default.removeItem(at: fileURL)
            return nil
        } catch {
            print("⚠️ CacheService: Failed to load transcript from disk: \(error.localizedDescription)")
            return nil
        }
    }
    
    private nonisolated func loadTranscriptsFromDisk() {
        let cacheDir = self.cacheDirectory
        guard let files = try? FileManager.default.contentsOfDirectory(at: cacheDir, includingPropertiesForKeys: nil) else {
            return
        }
        
        let transcriptFiles = files.filter { $0.lastPathComponent.hasPrefix("transcript_") }
        print("💾 CacheService: Found \(transcriptFiles.count) cached transcripts on disk")
    }
    
    // MARK: - Cache Management
    func clearCache() {
        cacheQueue.async(flags: .barrier) {
            self.bookCache.removeAll()
            self.transcriptCache.removeAll()
        }
        clearDiskCache()
    }
    
    func clearBookCache() {
        cacheQueue.async(flags: .barrier) {
            self.bookCache.removeAll()
        }
    }
    
    func clearTranscriptCache() {
        cacheQueue.async(flags: .barrier) {
            self.transcriptCache.removeAll()
        }
        clearDiskCache()
        print("✅ CacheService: Cleared all transcript cache (memory + disk)")
    }
    
    /// Clear transcript cache for a specific URL
    func clearTranscriptCache(for url: String) {
        cacheQueue.async(flags: .barrier) {
            self.transcriptCache.removeValue(forKey: url)
        }
        
        // Also clear from disk
        let cacheDir = self.cacheDirectory
        Task.detached(priority: .utility) {
            do {
                let cacheKey = url.data(using: .utf8)?.base64EncodedString() ?? ""
                let safeKey = cacheKey.replacingOccurrences(of: "/", with: "_")
                let fileURL = cacheDir.appendingPathComponent("transcript_\(safeKey).json")
                if FileManager.default.fileExists(atPath: fileURL.path) {
                    try FileManager.default.removeItem(at: fileURL)
                    print("✅ CacheService: Cleared transcript cache for: \(url)")
                }
            } catch {
                print("⚠️ CacheService: Failed to clear transcript cache for \(url): \(error.localizedDescription)")
            }
        }
    }
    
    private nonisolated func clearDiskCache() {
        let cacheDir = self.cacheDirectory
        Task.detached(priority: .utility) {
            do {
                let files = try FileManager.default.contentsOfDirectory(at: cacheDir, includingPropertiesForKeys: nil)
                for file in files {
                    try? FileManager.default.removeItem(at: file)
                }
                print("💾 CacheService: Cleared disk cache")
            } catch {
                print("⚠️ CacheService: Failed to clear disk cache: \(error.localizedDescription)")
            }
        }
    }
}







