//
//  DownloadManager.swift
//  ReadBetterApp3.0
//
//  Manages offline downloads of audiobook chapters (audio + transcript).
//  Uses URLSession background configuration so downloads survive app kills.
//  Persists download state via a JSON manifest in Documents/Downloads/.
//

import Foundation
import UIKit
import Combine

// MARK: - Data Models

struct DownloadManifest: Codable {
    var books: [String: BookDownloadRecord] = [:]
}

struct BookDownloadRecord: Codable {
    let bookId: String
    let title: String
    let author: String
    let coverUrl: String?
    let totalChapters: Int
    var chapters: [String: ChapterDownloadRecord]
    var status: BookDownloadStatus
    var totalBytes: Int64
    var downloadedAt: Date?
}

enum BookDownloadStatus: String, Codable {
    case notDownloaded
    case downloading
    case completed
    case failed
}

struct ChapterDownloadRecord: Codable {
    let chapterId: String
    let chapterOrder: Int
    var audioDownloaded: Bool
    var transcriptDownloaded: Bool
    var audioBytes: Int64
    var transcriptBytes: Int64

    var isComplete: Bool {
        audioDownloaded && transcriptDownloaded
    }
}

// MARK: - Download Progress (live, not persisted)

struct BookDownloadProgress {
    var bookId: String
    var totalFiles: Int
    var completedFiles: Int
    var status: BookDownloadStatus

    var fractionComplete: Double {
        guard totalFiles > 0 else { return 0 }
        return Double(completedFiles) / Double(totalFiles)
    }
}

// MARK: - URLSession Delegate

/// Separate NSObject delegate for URLSessionDownloadDelegate conformance.
/// Forwards all events to DownloadManager on the main actor.
private class DownloadSessionDelegate: NSObject, URLSessionDownloadDelegate {

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let descriptor = downloadTask.taskDescription else {
            print("⚠️ DownloadManager: No task description on completed download")
            return
        }

        let fileSize = (try? FileManager.default.attributesOfItem(atPath: location.path)[.size] as? Int64) ?? 0

        // Copy file to a temporary location since the system will delete `location` after this method returns
        let tempDir = FileManager.default.temporaryDirectory
        let tempFile = tempDir.appendingPathComponent(UUID().uuidString)
        do {
            try FileManager.default.copyItem(at: location, to: tempFile)
        } catch {
            print("❌ DownloadManager: Failed to copy temp file: \(error.localizedDescription)")
            return
        }

        Task { @MainActor in
            DownloadManager.shared.handleDownloadCompleted(descriptor: descriptor, tempFileURL: tempFile, fileSize: fileSize)
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        // Progress updates handled by counting completed files, not bytes
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error = error else { return }

        // Ignore cancellation errors (user cancelled)
        if (error as NSError).code == NSURLErrorCancelled { return }

        guard let descriptor = task.taskDescription else { return }

        print("❌ DownloadManager: Task failed (\(descriptor)): \(error.localizedDescription)")

        Task { @MainActor in
            DownloadManager.shared.handleDownloadError(descriptor: descriptor, error: error)
        }
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        Task { @MainActor in
            if let appDelegate = UIApplication.shared.delegate as? AppDelegate,
               let handler = appDelegate.backgroundSessionCompletionHandler {
                appDelegate.backgroundSessionCompletionHandler = nil
                handler()
            }
        }
    }
}

// MARK: - DownloadManager

@MainActor
class DownloadManager: ObservableObject {
    static let shared = DownloadManager()

    @Published var manifest: DownloadManifest = DownloadManifest()
    @Published var activeDownloads: [String: BookDownloadProgress] = [:]

    private let downloadsDirectory: URL
    private let manifestURL: URL
    private let sessionDelegate = DownloadSessionDelegate()
    private lazy var backgroundSession: URLSession = {
        let config = URLSessionConfiguration.background(withIdentifier: "com.readbetter.downloads")
        config.isDiscretionary = false
        config.sessionSendsLaunchEvents = true
        return URLSession(configuration: config, delegate: sessionDelegate, delegateQueue: nil)
    }()

    private init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        downloadsDirectory = docs.appendingPathComponent("Downloads", isDirectory: true)
        manifestURL = downloadsDirectory.appendingPathComponent("manifest.json")

        try? FileManager.default.createDirectory(at: downloadsDirectory, withIntermediateDirectories: true)

        loadManifest()

        // Touch the lazy session so it reconnects to any background tasks from a previous launch
        _ = backgroundSession
    }

    // MARK: - Public API

    func downloadBook(_ book: Book) {
        let chapters = book.chapters.sorted(by: { $0.order < $1.order })
        guard !chapters.isEmpty else { return }

        // Create book directory
        let bookDir = downloadsDirectory.appendingPathComponent(book.id, isDirectory: true)
        try? FileManager.default.createDirectory(at: bookDir, withIntermediateDirectories: true)

        // Build chapter records
        var chapterRecords: [String: ChapterDownloadRecord] = [:]
        for chapter in chapters {
            chapterRecords[chapter.id] = ChapterDownloadRecord(
                chapterId: chapter.id,
                chapterOrder: chapter.order,
                audioDownloaded: false,
                transcriptDownloaded: false,
                audioBytes: 0,
                transcriptBytes: 0
            )
        }

        // Create manifest entry
        let record = BookDownloadRecord(
            bookId: book.id,
            title: book.title,
            author: book.author,
            coverUrl: book.coverUrl,
            totalChapters: chapters.count,
            chapters: chapterRecords,
            status: .downloading,
            totalBytes: 0,
            downloadedAt: nil
        )
        manifest.books[book.id] = record
        saveManifest()

        // Set up progress tracking
        let totalFiles = chapters.count * 2 // audio + json per chapter
        activeDownloads[book.id] = BookDownloadProgress(
            bookId: book.id,
            totalFiles: totalFiles,
            completedFiles: 0,
            status: .downloading
        )

        // Enqueue download tasks
        for chapter in chapters {
            // Audio download
            if let audioURL = URL(string: chapter.audioUrl) {
                let audioTask = backgroundSession.downloadTask(with: audioURL)
                audioTask.taskDescription = "\(book.id)|\(chapter.id)|\(chapter.order)|audio"
                audioTask.resume()
            }

            // Transcript JSON download
            if let jsonURL = URL(string: chapter.jsonUrl) {
                let jsonTask = backgroundSession.downloadTask(with: jsonURL)
                jsonTask.taskDescription = "\(book.id)|\(chapter.id)|\(chapter.order)|transcript"
                jsonTask.resume()
            }
        }

        print("📥 DownloadManager: Started downloading '\(book.title)' (\(chapters.count) chapters, \(totalFiles) files)")

        // Also cache explainable terms for offline word definitions.
        // This is a lightweight Firestore fetch (JSON only, ~20-50KB per chapter),
        // completely separate from the URLSession audio/transcript downloads.
        let bookId = book.id
        let chaptersSnapshot = chapters
        Task { @MainActor in
            await ExplainableTermsService.shared.cacheTermsForDownload(bookId: bookId, chapters: chaptersSnapshot)
        }
    }

    func cancelDownload(bookId: String) {
        // Cancel all tasks for this book
        backgroundSession.getTasksWithCompletionHandler { _, _, downloadTasks in
            for task in downloadTasks {
                if let desc = task.taskDescription, desc.hasPrefix("\(bookId)|") {
                    task.cancel()
                }
            }
        }

        // Clean up files
        let bookDir = downloadsDirectory.appendingPathComponent(bookId, isDirectory: true)
        try? FileManager.default.removeItem(at: bookDir)

        // Update manifest
        manifest.books.removeValue(forKey: bookId)
        saveManifest()

        // Remove progress tracking
        activeDownloads.removeValue(forKey: bookId)

        print("🗑️ DownloadManager: Cancelled download for \(bookId)")
    }

    func deleteDownload(bookId: String) {
        // Remove files
        let bookDir = downloadsDirectory.appendingPathComponent(bookId, isDirectory: true)
        try? FileManager.default.removeItem(at: bookDir)

        // Update manifest
        manifest.books.removeValue(forKey: bookId)
        saveManifest()

        // Remove progress tracking
        activeDownloads.removeValue(forKey: bookId)

        print("🗑️ DownloadManager: Deleted download for \(bookId)")
    }

    func isBookDownloaded(_ bookId: String) -> Bool {
        guard let record = manifest.books[bookId], record.status == .completed else {
            return false
        }
        // Verify at least one file still exists on disk
        let bookDir = downloadsDirectory.appendingPathComponent(bookId, isDirectory: true)
        return FileManager.default.fileExists(atPath: bookDir.path)
    }

    func localAudioURL(bookId: String, chapterOrder: Int) -> URL? {
        guard let record = manifest.books[bookId], record.status == .completed else { return nil }

        let fileURL = downloadsDirectory
            .appendingPathComponent(bookId)
            .appendingPathComponent("chapter_\(chapterOrder).m4a")

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            // File missing — manifest is stale, update it
            markBookAsIncomplete(bookId: bookId)
            return nil
        }

        return fileURL
    }

    func localTranscriptURL(bookId: String, chapterOrder: Int) -> URL? {
        guard let record = manifest.books[bookId], record.status == .completed else { return nil }

        let fileURL = downloadsDirectory
            .appendingPathComponent(bookId)
            .appendingPathComponent("chapter_\(chapterOrder).json")

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            markBookAsIncomplete(bookId: bookId)
            return nil
        }

        return fileURL
    }

    func totalStorageUsed() -> Int64 {
        return manifest.books.values
            .filter { $0.status == .completed }
            .reduce(0) { $0 + $1.totalBytes }
    }

    func storageUsedFormatted() -> String {
        let bytes = totalStorageUsed()
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    func downloadStatus(for bookId: String) -> BookDownloadStatus {
        return manifest.books[bookId]?.status ?? .notDownloaded
    }

    // MARK: - Internal Handlers (called from delegate)

    func handleDownloadCompleted(descriptor: String, tempFileURL: URL, fileSize: Int64) {
        let parts = descriptor.split(separator: "|")
        guard parts.count == 4 else {
            try? FileManager.default.removeItem(at: tempFileURL)
            return
        }

        let bookId = String(parts[0])
        let chapterId = String(parts[1])
        let chapterOrder = Int(parts[2]) ?? 0
        let fileType = String(parts[3]) // "audio" or "transcript"

        // Determine destination
        let ext = fileType == "audio" ? "m4a" : "json"
        let destURL = downloadsDirectory
            .appendingPathComponent(bookId)
            .appendingPathComponent("chapter_\(chapterOrder).\(ext)")

        // Ensure directory exists
        let bookDir = downloadsDirectory.appendingPathComponent(bookId, isDirectory: true)
        try? FileManager.default.createDirectory(at: bookDir, withIntermediateDirectories: true)

        // Move file to final location
        do {
            // Remove existing file if any
            if FileManager.default.fileExists(atPath: destURL.path) {
                try FileManager.default.removeItem(at: destURL)
            }
            try FileManager.default.moveItem(at: tempFileURL, to: destURL)
        } catch {
            print("❌ DownloadManager: Failed to move file: \(error.localizedDescription)")
            try? FileManager.default.removeItem(at: tempFileURL)
            return
        }

        // Update manifest
        guard var bookRecord = manifest.books[bookId],
              var chapterRecord = bookRecord.chapters[chapterId] else {
            return
        }

        if fileType == "audio" {
            chapterRecord.audioDownloaded = true
            chapterRecord.audioBytes = fileSize
        } else {
            chapterRecord.transcriptDownloaded = true
            chapterRecord.transcriptBytes = fileSize
        }

        bookRecord.chapters[chapterId] = chapterRecord

        // Recalculate total bytes
        bookRecord.totalBytes = bookRecord.chapters.values.reduce(0) { $0 + $1.audioBytes + $1.transcriptBytes }

        // Check if all chapters are complete
        let allComplete = bookRecord.chapters.values.allSatisfy { $0.isComplete }
        if allComplete {
            bookRecord.status = .completed
            bookRecord.downloadedAt = Date()
            activeDownloads.removeValue(forKey: bookId)
            print("✅ DownloadManager: Book '\(bookRecord.title)' download complete! (\(bookRecord.totalBytes) bytes)")
        }

        // Use a mutable copy to update
        var updatedRecord = bookRecord
        manifest.books[bookId] = updatedRecord
        saveManifest()

        // Update progress
        if var progress = activeDownloads[bookId] {
            progress.completedFiles += 1
            if allComplete {
                progress.status = .completed
            }
            activeDownloads[bookId] = progress
        }
    }

    func handleDownloadError(descriptor: String, error: Error) {
        let parts = descriptor.split(separator: "|")
        guard parts.count >= 1 else { return }

        let bookId = String(parts[0])

        // Mark as failed
        if var record = manifest.books[bookId] {
            record.status = .failed
            manifest.books[bookId] = record
            saveManifest()
        }

        if var progress = activeDownloads[bookId] {
            progress.status = .failed
            activeDownloads[bookId] = progress
        }
    }

    // MARK: - Private Helpers

    private func markBookAsIncomplete(bookId: String) {
        if var record = manifest.books[bookId] {
            record.status = .notDownloaded
            manifest.books[bookId] = record
            saveManifest()
            print("⚠️ DownloadManager: Book \(bookId) marked incomplete (files missing on disk)")
        }
    }

    private func saveManifest() {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(manifest)
            try data.write(to: manifestURL, options: .atomic)
        } catch {
            print("❌ DownloadManager: Failed to save manifest: \(error.localizedDescription)")
        }
    }

    private func loadManifest() {
        guard FileManager.default.fileExists(atPath: manifestURL.path) else { return }

        do {
            let data = try Data(contentsOf: manifestURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            manifest = try decoder.decode(DownloadManifest.self, from: data)

            // Reset any "downloading" states from previous session (they didn't complete)
            for (bookId, var record) in manifest.books {
                if record.status == .downloading {
                    // Check if actually complete (background session may have finished)
                    let allComplete = record.chapters.values.allSatisfy { $0.isComplete }
                    if allComplete {
                        record.status = .completed
                        record.downloadedAt = Date()
                    } else {
                        record.status = .failed
                    }
                    manifest.books[bookId] = record
                }
            }
            saveManifest()

            print("📂 DownloadManager: Loaded manifest with \(manifest.books.count) book(s)")
        } catch {
            print("⚠️ DownloadManager: Failed to load manifest: \(error.localizedDescription)")
            manifest = DownloadManifest()
        }
    }
}
