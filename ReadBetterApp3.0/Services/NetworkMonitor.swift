//
//  NetworkMonitor.swift
//  ReadBetterApp3.0
//
//  Lightweight singleton that tracks network reachability using NWPathMonitor.
//  Used to distinguish between "bookmark saved to server" and "bookmark queued offline".
//

import Foundation
import Network
import Combine

final class NetworkMonitor: ObservableObject {
    static let shared = NetworkMonitor()

    /// `true` when the device has a usable network path (WiFi, cellular, etc.)
    @Published private(set) var isConnected: Bool = true

    /// `true` only when connected via WiFi (not cellular/hotspot)
    @Published private(set) var isOnWiFi: Bool = true

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.readbetter.network", qos: .background)

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                self?.isConnected = path.status == .satisfied
                self?.isOnWiFi = path.usesInterfaceType(.wifi)
            }
        }
        monitor.start(queue: queue)
    }

    deinit {
        monitor.cancel()
    }
}
