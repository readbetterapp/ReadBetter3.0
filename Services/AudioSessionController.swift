//
//  AudioSessionController.swift
//  ReadBetterApp3.0
//
//  Centralized AVAudioSession management for background spoken-audio playback.
//

import AVFoundation
import OSLog

final class AudioSessionController {
    static let shared = AudioSessionController()

    private let logger = Logger(subsystem: "ReadBetterApp3.0", category: "AudioSession")

    private var isConfigured = false
    private var interruptionObserver: NSObjectProtocol?
    private var routeChangeObserver: NSObjectProtocol?
    private var mediaServicesResetObserver: NSObjectProtocol?

    /// Called when an interruption begins (e.g. phone call, Siri).
    /// Typically: pause playback.
    var onInterruptionBegan: (() -> Void)?

    /// Called when an interruption ends and iOS indicates playback should resume.
    var onInterruptionEndedShouldResume: (() -> Void)?

    /// Called when the audio route changes (e.g. headphones disconnected).
    var onRouteChange: ((AVAudioSession.RouteChangeReason) -> Void)?

    private init() {}

    deinit {
        if let interruptionObserver {
            NotificationCenter.default.removeObserver(interruptionObserver)
        }
        if let routeChangeObserver {
            NotificationCenter.default.removeObserver(routeChangeObserver)
        }
        if let mediaServicesResetObserver {
            NotificationCenter.default.removeObserver(mediaServicesResetObserver)
        }
    }

    /// Sets up notification observers once.
    func configureIfNeeded() {
        guard !isConfigured else { return }
        isConfigured = true

        let nc = NotificationCenter.default
        interruptionObserver = nc.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.handleInterruption(notification)
        }

        routeChangeObserver = nc.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.handleRouteChange(notification)
        }

        mediaServicesResetObserver = nc.addObserver(
            forName: AVAudioSession.mediaServicesWereResetNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.logger.warning("AVAudioSession media services were reset; will need re-activation before playback.")
            // If media services reset, our session config may be lost.
            // We keep observers alive and re-apply configuration on next activate call.
        }
    }

    /// Activate an audio session suitable for narration + background playback.
    func activateForSpokenAudio() {
        configureIfNeeded()

        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(
                .playback,
                mode: .spokenAudio,
                options: [.allowAirPlay, .allowBluetooth]
            )
            try session.setActive(true)
        } catch {
            logger.error("Failed to activate AVAudioSession: \(String(describing: error), privacy: .public)")
        }
    }

    /// Deactivate the audio session and optionally notify other audio apps.
    func deactivate(notifyOthers: Bool = true) {
        let session = AVAudioSession.sharedInstance()
        do {
            if notifyOthers {
                try session.setActive(false, options: [.notifyOthersOnDeactivation])
            } else {
                try session.setActive(false)
            }
        } catch {
            logger.error("Failed to deactivate AVAudioSession: \(String(describing: error), privacy: .public)")
        }
    }

    // MARK: - Notification Handlers

    private func handleInterruption(_ notification: Notification) {
        guard
            let userInfo = notification.userInfo,
            let rawType = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
            let type = AVAudioSession.InterruptionType(rawValue: rawType)
        else {
            return
        }

        switch type {
        case .began:
            logger.info("Audio interruption began")
            onInterruptionBegan?()

        case .ended:
            let rawOptions = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            let options = AVAudioSession.InterruptionOptions(rawValue: rawOptions)

            logger.info("Audio interruption ended (shouldResume=\(options.contains(.shouldResume)))")
            if options.contains(.shouldResume) {
                onInterruptionEndedShouldResume?()
            }

        @unknown default:
            break
        }
    }

    private func handleRouteChange(_ notification: Notification) {
        guard
            let userInfo = notification.userInfo,
            let rawReason = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
            let reason = AVAudioSession.RouteChangeReason(rawValue: rawReason)
        else {
            return
        }

        logger.info("Audio route changed (reason=\(reason.rawValue))")
        onRouteChange?(reason)
    }
}


