//
//  AudioSessionController.swift
//  ReadBetterApp3.0
//
//  Configures AVAudioSession for background spoken-audio playback
//  and handles interruptions / route changes.
//

import AVFoundation
import Foundation
import OSLog
import UIKit

@MainActor
final class AudioSessionController {
    static let shared = AudioSessionController()

    private let logger = Logger(subsystem: "ReadBetterApp3.0", category: "AudioSession")

    private var interruptionObserver: NSObjectProtocol?
    private var routeChangeObserver: NSObjectProtocol?

    /// If the user hits "Play" (Control Center / lock screen) while the session is interrupted,
    /// activation can fail. We remember the intent and retry as soon as the interruption ends.
    private var pendingPlayRequest: Bool = false

    /// Last AVAudioSession activation error (OSStatus), if any.
    private var lastActivationErrorCode: Int?

    /// Called when the system indicates playback should pause (interruptions, route changes, etc.)
    var onPauseRequested: (() -> Void)?

    /// Called when an interruption ends and iOS indicates playback may resume.
    var onResumeRequested: (() -> Void)?

    private init() {}

    /// Mark that an external play request occurred but couldn't start yet (usually because of an interruption).
    func markPendingPlayRequest() {
        pendingPlayRequest = true
    }

    /// Consume the pending-play flag (returns true once, then resets to false).
    func consumePendingPlayRequest() -> Bool {
        let v = pendingPlayRequest
        pendingPlayRequest = false
        return v
    }

    func configureIfNeeded() {
        installObserversIfNeeded()
        // Audio session is now configured at app launch in AppDelegate.
        // We just need to ensure observers are installed.
    }

    /// Prepare the audio session for playback and activate it.
    /// Returns true if activation succeeded (or was already active).
    @discardableResult
    func activateForPlayback() -> Bool {
        installObserversIfNeeded()
        
        let session = AVAudioSession.sharedInstance()
        
        // IMPORTANT: iOS can keep the category as `.playback` but still deactivate the session
        // (e.g. after interruptions / lock-screen transitions / media services reset).
        // If we don't re-activate, lock-screen "Play" can fire our handler but audio won't resume.
        //
        // We use a spoken-audio configuration for background + lock-screen playback.
        // We intentionally do NOT use routeSharingPolicy `.longFormAudio` because it can
        // conflict with common category options on some devices/OS versions (causes -50).
        // To avoid -50 errors, we only re-apply category config when needed, but always attempt to activate.
        do {
            if session.category != .playback || session.mode != .spokenAudio {
                do {
                    if #available(iOS 10.0, *) {
                        try session.setCategory(
                            .playback,
                            mode: .spokenAudio,
                            options: [.allowAirPlay, .allowBluetoothA2DP]
                        )
                    } else {
                        try session.setCategory(
                            .playback,
                            mode: .spokenAudio,
                            options: [.allowAirPlay]
                        )
                    }
                } catch {
                    // Fallback to the most compatible configuration.
                    logger.error("Failed to set preferred playback category/mode/options; falling back. error=\(String(describing: error), privacy: .public)")
                    try session.setCategory(.playback)
                }
            }
            try session.setActive(true)
            lastActivationErrorCode = nil
            // If we successfully activated, any pending intent can be cleared.
            pendingPlayRequest = false
            return true
        } catch {
            let nsError = error as NSError
            lastActivationErrorCode = nsError.code
            logger.error("Failed to activate AVAudioSession for playback: \(String(describing: error), privacy: .public) code=\(nsError.code, privacy: .public)")

            // Common case: activation fails because the session is currently interrupted.
            // In that case, don't spam retries/reconfiguration (can trigger -50). We'll retry on interruption end.
            // 561015905 is commonly surfaced as "CannotStartPlaying".
            if nsError.domain == NSOSStatusErrorDomain, nsError.code == 561015905 {
                pendingPlayRequest = true
                return false
            }

            // Best-effort recovery for the common "CannotStartPlaying" activation failure.
            // Try a forced reconfigure + re-activate.
            do {
                // Use a conservative config on recovery (avoid option combos that can throw -50).
                if #available(iOS 10.0, *) {
                    try session.setCategory(
                        .playback,
                        mode: .spokenAudio,
                        options: [.allowAirPlay, .allowBluetoothA2DP]
                    )
                } else {
                    try session.setCategory(
                        .playback,
                        mode: .spokenAudio,
                        options: [.allowAirPlay]
                    )
                }
                try session.setActive(true)
                lastActivationErrorCode = nil
                pendingPlayRequest = false
                return true
            } catch {
                let nsError2 = error as NSError
                lastActivationErrorCode = nsError2.code
                logger.error("Failed to recover AVAudioSession activation: \(String(describing: error), privacy: .public) code=\(nsError2.code, privacy: .public)")
                return false
            }
        }
    }

    @discardableResult
    func setActive(_ active: Bool) -> Bool {
        // For background audio, we should NOT deactivate the session.
        // Deactivating causes iOS to suspend our audio when backgrounded.
        if !active {
            logger.info("Ignoring setActive(false) to preserve background audio capability.")
            return true
        }
        
        let session = AVAudioSession.sharedInstance()
        if session.category == .playback {
            return true
        }
        
        do {
            try session.setCategory(.playback)
            try session.setActive(true)
            return true
        } catch {
            logger.error("Failed to set AVAudioSession active: \(String(describing: error), privacy: .public)")
            return false
        }
    }

    private func installObserversIfNeeded() {
        if interruptionObserver != nil || routeChangeObserver != nil { return }

        // Interruption handling (phone calls, Siri, alarms, etc.)
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor [weak self] in
                self?.handleInterruption(notification)
            }
        }

        // Route changes (AirPods disconnect, speaker change, etc.)
        routeChangeObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor [weak self] in
                self?.handleRouteChange(notification)
            }
        }
    }

    private func handleInterruption(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let rawType = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: rawType) else {
            return
        }

        switch type {
        case .began:
            // IMPORTANT:
            // When the user locks the screen / goes Home, iOS often emits an "interruption began"
            // that is effectively background transition noise (WasSuspendedKey is frequently nil/0).
            // If we pause in response, background playback breaks.
            //
            // Only pause for real interruptions while the app is ACTIVE.
            let appState = UIApplication.shared.applicationState
            if appState != .active {
                return
            }

            let rawReason = userInfo["AVAudioSessionInterruptionReasonKey"] as? UInt // key is not always present
            logger.info("Audio interruption began (active app). reason=\(String(describing: rawReason), privacy: .public)")
            onPauseRequested?()
        case .ended:
            let rawOptions = (userInfo[AVAudioSessionInterruptionOptionKey] as? UInt) ?? 0
            let options = AVAudioSession.InterruptionOptions(rawValue: rawOptions)
            let wasSuspended = (userInfo[AVAudioSessionInterruptionWasSuspendedKey] as? UInt).map { $0 != 0 }
            let rawReason = userInfo["AVAudioSessionInterruptionReasonKey"] as? UInt
            let shouldResume = options.contains(.shouldResume)
            logger.info("Audio interruption ended. shouldResume=\(shouldResume, privacy: .public) wasSuspended=\(String(describing: wasSuspended), privacy: .public) reason=\(String(describing: rawReason), privacy: .public) pendingPlay=\(self.pendingPlayRequest, privacy: .public)")

            // Retry if iOS says it's ok OR if the user explicitly pressed "Play" during the interruption.
            if shouldResume || pendingPlayRequest {
                onResumeRequested?()
            }
        @unknown default:
            break
        }
    }

    private func handleRouteChange(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let rawReason = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: rawReason) else {
            return
        }

        // Route changes are common during lock/unlock and device handoffs.
        // Don't pause automatically; let the player continue unless iOS issues an interruption.
        logger.info("Audio route changed. reason=\(reason.rawValue, privacy: .public)")
    }
}


