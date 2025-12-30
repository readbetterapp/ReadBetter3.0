//
//  TappableTextView.swift
//  ReadBetterApp3.0
//
//  UIKit-based text view that supports accurate word-level tap detection.
//  Uses NSLayoutManager to determine exactly which character/word was tapped.
//

import SwiftUI
import UIKit

/// A UIKit-based text view wrapped for SwiftUI that supports accurate word tap detection
struct TappableTextView: UIViewRepresentable {
    let attributedText: NSAttributedString
    let explainableWordRanges: [(wordIndex: Int, range: NSRange)]
    let onWordTap: (Int) -> Void  // Called with word index when explainable word is tapped
    let onBackgroundTap: () -> Void  // Called when non-explainable area is tapped
    
    func makeUIView(context: Context) -> TappableUITextView {
        let textView = TappableUITextView()
        textView.isEditable = false
        textView.isSelectable = false
        textView.isScrollEnabled = false
        textView.backgroundColor = .clear
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.attributedText = attributedText
        
        // Store references for tap handling
        textView.explainableWordRanges = explainableWordRanges
        textView.onWordTap = onWordTap
        textView.onBackgroundTap = onBackgroundTap
        
        // Add tap gesture - handles both explainable words and sentence navigation
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        textView.addGestureRecognizer(tap)
        
        return textView
    }
    
    func updateUIView(_ uiView: TappableUITextView, context: Context) {
        uiView.attributedText = attributedText
        uiView.explainableWordRanges = explainableWordRanges
        uiView.onWordTap = onWordTap
        uiView.onBackgroundTap = onBackgroundTap
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    class Coordinator: NSObject {
        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let textView = gesture.view as? TappableUITextView else { return }
            
            let location = gesture.location(in: textView)
            
            // Use TextKit to find the character at this location
            let layoutManager = textView.layoutManager
            let textContainer = textView.textContainer
            
            // Get character index at tap point
            var fraction: CGFloat = 0
            let characterIndex = layoutManager.characterIndex(
                for: location,
                in: textContainer,
                fractionOfDistanceBetweenInsertionPoints: &fraction
            )
            
            // Check if tap is on an explainable word
            for (wordIndex, range) in textView.explainableWordRanges {
                if characterIndex >= range.location && characterIndex < range.location + range.length {
                    // Tapped on explainable word - show explanation
                    textView.onWordTap?(wordIndex)
                    
                    // Haptic feedback
                    let generator = UIImpactFeedbackGenerator(style: .light)
                    generator.impactOccurred()
                    return
                }
            }
            
            // Tapped outside explainable words - trigger sentence navigation
            textView.onBackgroundTap?()
        }
    }
}

/// Custom UITextView subclass that stores tap handling closures
class TappableUITextView: UITextView {
    var explainableWordRanges: [(wordIndex: Int, range: NSRange)] = []
    var onWordTap: ((Int) -> Void)?
    var onBackgroundTap: (() -> Void)?
    
    override var intrinsicContentSize: CGSize {
        // Calculate the size needed to display all text
        let fixedWidth = bounds.width > 0 ? bounds.width : UIScreen.main.bounds.width - 40
        let size = sizeThatFits(CGSize(width: fixedWidth, height: .greatestFiniteMagnitude))
        return CGSize(width: UIView.noIntrinsicMetric, height: size.height)
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        invalidateIntrinsicContentSize()
    }
}

// MARK: - Preview
#Preview {
    let text = "This is a test with Adolf Hitler and Wehrmacht mentioned."
    let attrString = NSMutableAttributedString(string: text)
    attrString.addAttribute(.font, value: UIFont.systemFont(ofSize: 20, weight: .semibold), range: NSRange(location: 0, length: text.count))
    attrString.addAttribute(.foregroundColor, value: UIColor.white, range: NSRange(location: 0, length: text.count))
    
    // Underline "Adolf Hitler" (chars 20-31)
    attrString.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: NSRange(location: 20, length: 12))
    
    return TappableTextView(
        attributedText: attrString,
        explainableWordRanges: [(wordIndex: 5, range: NSRange(location: 20, length: 12))],
        onWordTap: { wordIndex in
            print("Tapped word index: \(wordIndex)")
        },
        onBackgroundTap: {
            print("Background tap")
        }
    )
    .frame(height: 100)
    .background(Color.black)
}

