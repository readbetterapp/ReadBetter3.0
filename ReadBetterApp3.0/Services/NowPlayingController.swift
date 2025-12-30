//
//  NowPlayingController.swift
//  ReadBetterApp3.0
//
//  Lock Screen / Control Center Now Playing integration.
//  Owns MPRemoteCommandCenter handlers and updates MPNowPlayingInfoCenter.
//

import Foundation
import MediaPlayer
import OSLog
import QuartzCore
import UIKit

@MainActor
final class NowPlayingController {
    static let shared = NowPlayingController()

    private let logger = Logger(subsystem: "ReadBetterApp3.0", category: "NowPlaying")

    // MARK: - Session state
    private var chapterTitle: String = ""
    private var bookTitle: String = ""
    private var duration: Double = 0
    private var artwork: MPMediaItemArtwork?

    // Control hooks (set by the active reader session)
    private var playHandler: (() -> Void)?
    private var pauseHandler: (() -> Void)?
    private var seekHandler: ((Double) -> Void)?
    private var currentTimeProvider: (() -> Double)?
    private var isPlayingProvider: (() -> Bool)?

    private var remoteCommandTargets: [(command: MPRemoteCommand, token: Any)] = []

    // Throttle NowPlayingInfo writes (time updates can be frequent)
    private var lastNowPlayingWrite: CFTimeInterval = 0
    private let minNowPlayingWriteInterval: CFTimeInterval = 0.8

    private init() {}

    // MARK: - Public API

    /// Activate Now Playing for the current reader session and register remote controls.
    /// Call this once when the reader becomes active (and whenever chapter/book changes).
    func activateSession(
        chapterTitle: String,
        bookTitle: String,
        coverURL: URL?,
        duration: Double,
        play: @escaping () -> Void,
        pause: @escaping () -> Void,
        seek: @escaping (Double) -> Void,
        currentTime: @escaping () -> Double,
        isPlaying: @escaping () -> Bool
    ) {
        self.chapterTitle = chapterTitle
        self.bookTitle = bookTitle
        self.duration = duration

        self.playHandler = play
        self.pauseHandler = pause
        self.seekHandler = seek
        self.currentTimeProvider = currentTime
        self.isPlayingProvider = isPlaying

        UIApplication.shared.beginReceivingRemoteControlEvents()

        registerRemoteCommands()
        writeNowPlayingInfo(force: true)

        // Load artwork asynchronously (optional)
        loadArtworkIfNeeded(from: coverURL)
    }

    /// Update Now Playing playback state (elapsed time + rate). Safe to call frequently.
    func updatePlaybackState(elapsedTime: Double, isPlaying: Bool, force: Bool = false) {
        // Only update frequently-changing fields here; metadata is cached.
        writeNowPlayingInfo(overrideElapsed: elapsedTime, overrideIsPlaying: isPlaying, force: force)
    }

    /// Clear Now Playing and remove remote command handlers (call when leaving the reader).
    func deactivateSession() {
        removeRemoteCommands()

        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil

        UIApplication.shared.endReceivingRemoteControlEvents()

        chapterTitle = ""
        bookTitle = ""
        duration = 0
        artwork = nil

        playHandler = nil
        pauseHandler = nil
        seekHandler = nil
        currentTimeProvider = nil
        isPlayingProvider = nil
    }

    // MARK: - Remote Commands

    private func registerRemoteCommands() {
        removeRemoteCommands()

        let commandCenter = MPRemoteCommandCenter.shared()

        commandCenter.playCommand.isEnabled = true
        commandCenter.pauseCommand.isEnabled = true
        commandCenter.togglePlayPauseCommand.isEnabled = true

        // +/- 15s skip
        commandCenter.skipForwardCommand.isEnabled = true
        commandCenter.skipBackwardCommand.isEnabled = true
        commandCenter.skipForwardCommand.preferredIntervals = [15]
        commandCenter.skipBackwardCommand.preferredIntervals = [15]

        // Scrubbing
        commandCenter.changePlaybackPositionCommand.isEnabled = true

        remoteCommandTargets.append((
            command: commandCenter.playCommand,
            token: commandCenter.playCommand.addTarget { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.playHandler?()
                    self.writeNowPlayingInfo(force: true)
                }
                return .success
            }
        ))

        remoteCommandTargets.append((
            command: commandCenter.pauseCommand,
            token: commandCenter.pauseCommand.addTarget { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.pauseHandler?()
                    self.writeNowPlayingInfo(force: true)
                }
                return .success
            }
        ))

        remoteCommandTargets.append((
            command: commandCenter.togglePlayPauseCommand,
            token: commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    let isPlaying = self.isPlayingProvider?() ?? false
                    if isPlaying {
                        self.pauseHandler?()
                    } else {
                        self.playHandler?()
                    }
                    self.writeNowPlayingInfo(force: true)
                }
                return .success
            }
        ))

        remoteCommandTargets.append((
            command: commandCenter.skipForwardCommand,
            token: commandCenter.skipForwardCommand.addTarget { [weak self] event in
                guard let event = event as? MPSkipIntervalCommandEvent else { return .commandFailed }
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    let delta = event.interval
                    let now = self.currentTimeProvider?() ?? 0
                    self.seekHandler?(now + delta)
                    self.writeNowPlayingInfo(force: true)
                }
                return .success
            }
        ))

        remoteCommandTargets.append((
            command: commandCenter.skipBackwardCommand,
            token: commandCenter.skipBackwardCommand.addTarget { [weak self] event in
                guard let event = event as? MPSkipIntervalCommandEvent else { return .commandFailed }
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    let delta = event.interval
                    let now = self.currentTimeProvider?() ?? 0
                    self.seekHandler?(now - delta)
                    self.writeNowPlayingInfo(force: true)
                }
                return .success
            }
        ))

        remoteCommandTargets.append((
            command: commandCenter.changePlaybackPositionCommand,
            token: commandCenter.changePlaybackPositionCommand.addTarget { [weak self] event in
                guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.seekHandler?(event.positionTime)
                    self.writeNowPlayingInfo(force: true)
                }
                return .success
            }
        ))
    }

    private func removeRemoteCommands() {
        for entry in remoteCommandTargets {
            entry.command.removeTarget(entry.token)
        }
        remoteCommandTargets.removeAll()
    }

    // MARK: - Now Playing Info

    private func writeNowPlayingInfo(
        overrideElapsed: Double? = nil,
        overrideIsPlaying: Bool? = nil,
        force: Bool = false
    ) {
        guard !chapterTitle.isEmpty else { return }

        let now = CACurrentMediaTime()
        if !force, (now - lastNowPlayingWrite) < minNowPlayingWriteInterval {
            return
        }
        lastNowPlayingWrite = now

        let elapsed = overrideElapsed ?? (currentTimeProvider?() ?? 0)
        let isPlaying = overrideIsPlaying ?? (isPlayingProvider?() ?? false)

        var info: [String: Any] = [
            MPMediaItemPropertyTitle: chapterTitle,
            MPMediaItemPropertyAlbumTitle: bookTitle,
            MPMediaItemPropertyPlaybackDuration: max(duration, 0),
            MPNowPlayingInfoPropertyElapsedPlaybackTime: max(elapsed, 0),
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
        ]

        if let artwork {
            info[MPMediaItemPropertyArtwork] = artwork
        }

        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func loadArtworkIfNeeded(from url: URL?) {
        guard let url else { return }

        Task.detached(priority: .utility) { [url] in
            // Use your existing image loader/cache.
            let image = await ImagePreloader.shared.loadImageDirectly(
                url: url,
                targetSize: CGSize(width: 600, height: 600)
            )

            guard let image else { return }

            let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }

            await MainActor.run { [weak self] in
                guard let self else { return }
                self.artwork = artwork
                self.logger.info("Now Playing artwork updated.")
                self.writeNowPlayingInfo(force: true)
            }
        }
    }
}


