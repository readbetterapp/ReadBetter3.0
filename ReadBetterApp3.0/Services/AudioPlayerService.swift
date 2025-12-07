//
//  AudioPlayerService.swift
//  ReadBetterApp3.0
//
//  Created by Ermin on 30/11/2025.
//

import Foundation
import AVFoundation
import Combine

class AudioPlayerService: ObservableObject {
    @Published var isPlaying = false
    @Published var currentTime: Double = 0
    @Published var duration: Double = 0
    @Published var isLoading = false
    @Published var error: Error?
    
    private var player: AVPlayer?
    private var timeObserver: Any?
    private var durationObserver: NSKeyValueObservation?
    
    /// Load and prepare audio from URL
    func loadAudio(from urlString: String) async throws {
        guard let url = URL(string: urlString) else {
            throw AudioError.invalidURL
        }
        
        await MainActor.run {
            isLoading = true
            error = nil
        }
        
        let playerItem = AVPlayerItem(url: url)
        let newPlayer = AVPlayer(playerItem: playerItem)
        
        // Observe duration
        durationObserver = playerItem.observe(\.status, options: [.new]) { [weak self] item, _ in
            guard let self = self else { return }
            if item.status == .readyToPlay {
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    self.duration = item.duration.seconds
                    self.isLoading = false
                }
            }
        }
        
        // Observe playback end
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: playerItem,
            queue: .main
        ) { [weak self] _ in
            self?.isPlaying = false
        }
        
        await MainActor.run {
            // Remove old time observer
            if let observer = timeObserver {
                player?.removeTimeObserver(observer)
            }
            
            player = newPlayer
            
                // Add time observer for updates
                let interval = CMTime(seconds: 0.1, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
                timeObserver = newPlayer.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
                    guard let self = self else { return }
                    // Already on main queue, update directly
                    self.currentTime = time.seconds
                }
            
            isLoading = false
        }
    }
    
    /// Play audio
    func play() {
        player?.play()
        isPlaying = true
    }
    
    /// Pause audio
    func pause() {
        player?.pause()
        isPlaying = false
    }
    
    /// Seek to specific time
    func seek(to time: Double) {
        let cmTime = CMTime(seconds: time, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        player?.seek(to: cmTime)
        currentTime = time
    }
    
    /// Toggle play/pause
    func togglePlayPause() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }
    
    /// Cleanup
    deinit {
        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
        }
        durationObserver?.invalidate()
        NotificationCenter.default.removeObserver(self)
        player = nil
    }
}

enum AudioError: Error {
    case invalidURL
    case loadFailed
    case playbackFailed
}

