//
//  ScrollDebugOverlay.swift
//  ReadBetterApp3.0
//
//  Small overlay to show scroll offset values for debugging.
//

import SwiftUI

// MARK: - Scroll Offset Reader
struct ScrollOffsetReader: View {
    let coordinateSpace: String

    var body: some View {
        GeometryReader { geometry in
            Color.clear
                .preference(
                    key: ScrollOffsetPreferenceKey.self,
                    value: -geometry.frame(in: .named(coordinateSpace)).minY
                )
        }
        .frame(height: 0)
    }
}

// MARK: - Debug Pill
struct ScrollDebugPill: View {
    let value: CGFloat

    var body: some View {
        Text(String(format: "scroll: %.0f", value))
            .font(.system(size: 12, weight: .semibold, design: .monospaced))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.black.opacity(0.6))
            .foregroundColor(.white)
            .clipShape(Capsule())
            .padding(.top, 8)
            .padding(.trailing, 12)
    }
}
