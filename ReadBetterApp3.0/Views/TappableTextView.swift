//
//  TappableTextView.swift
//  ReadBetterApp3.0
//
//  UIKit-based text view that supports accurate word-level tap detection.
//  Uses TextKit 2 (NSTextLayoutManager) for modern text layout and rendering.
//

import SwiftUI
import UIKit

/// A UIKit-based text view wrapped for SwiftUI that supports accurate word tap detection
/// Uses TextKit 2 for consistent line break calculations
struct TappableTextView: UIViewRepresentable {
    let attributedText: NSAttributedString
    let explainableWordRanges: [(wordIndex: Int, range: NSRange)]
    let onWordTap: (Int) -> Void  // Called with word index when explainable word is tapped
    let onBackgroundTap: () -> Void  // Called when non-explainable area is tapped
    /// Callback to provide line break positions after layout - used for highlight splitting
    var onLineBreaksCalculated: (([Int]) -> Void)?
    
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
        textView.onLineBreaksCalculated = onLineBreaksCalculated
        
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
        uiView.onLineBreaksCalculated = onLineBreaksCalculated
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    class Coordinator: NSObject {
        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let textView = gesture.view as? TappableUITextView else { return }
            
            let location = gesture.location(in: textView)
            
            // Use TextKit 2 (textLayoutManager) if available, fallback to TextKit 1
            if let textLayoutManager = textView.textLayoutManager,
               let textContentManager = textLayoutManager.textContentManager {
                // TextKit 2 approach
                let locationInContainer = CGPoint(
                    x: location.x - textView.textContainerInset.left,
                    y: location.y - textView.textContainerInset.top
                )
                
                // Find the text location at the tap point
                if let textLayoutFragment = textLayoutManager.textLayoutFragment(for: locationInContainer) {
                    let fragmentOrigin = textLayoutFragment.layoutFragmentFrame.origin
                    let locationInFragment = CGPoint(
                        x: locationInContainer.x - fragmentOrigin.x,
                        y: locationInContainer.y - fragmentOrigin.y
                    )
                    
                    // Get character index from the layout fragment
                    for lineFragment in textLayoutFragment.textLineFragments {
                        if lineFragment.typographicBounds.contains(locationInFragment) {
                            let characterIndex = lineFragment.characterIndex(for: locationInFragment)
                            
                            // Convert to document location
                            if let textRange = textLayoutFragment.textElement?.elementRange,
                               let startLocation = textRange.location as? NSTextLocation {
                                let documentOffset = textContentManager.offset(from: textContentManager.documentRange.location, to: startLocation)
                                let finalIndex = documentOffset + characterIndex
                                
                                // Check if tap is on an explainable word
                                for (wordIndex, range) in textView.explainableWordRanges {
                                    if finalIndex >= range.location && finalIndex < range.location + range.length {
                                        textView.onWordTap?(wordIndex)
                                        let generator = UIImpactFeedbackGenerator(style: .light)
                                        generator.impactOccurred()
                                        return
                                    }
                                }
                            }
                            break
                        }
                    }
                }
                
                // Tapped outside explainable words
                textView.onBackgroundTap?()
            } else {
                // Fallback to TextKit 1 for older iOS versions
                let layoutManager = textView.layoutManager
                let textContainer = textView.textContainer
                
                var fraction: CGFloat = 0
                let characterIndex = layoutManager.characterIndex(
                    for: location,
                    in: textContainer,
                    fractionOfDistanceBetweenInsertionPoints: &fraction
                )
                
                for (wordIndex, range) in textView.explainableWordRanges {
                    if characterIndex >= range.location && characterIndex < range.location + range.length {
                        textView.onWordTap?(wordIndex)
                        let generator = UIImpactFeedbackGenerator(style: .light)
                        generator.impactOccurred()
                        return
                    }
                }
                
                textView.onBackgroundTap?()
            }
        }
    }
}

/// Custom UITextView subclass that stores tap handling closures and calculates line breaks
class TappableUITextView: UITextView {
    var explainableWordRanges: [(wordIndex: Int, range: NSRange)] = []
    var onWordTap: ((Int) -> Void)?
    var onBackgroundTap: (() -> Void)?
    var onLineBreaksCalculated: (([Int]) -> Void)?
    
    private var lastCalculatedLineBreaks: [Int] = []
    
    override var intrinsicContentSize: CGSize {
        let fixedWidth = bounds.width > 0 ? bounds.width : UIScreen.main.bounds.width - 40
        let size = sizeThatFits(CGSize(width: fixedWidth, height: .greatestFiniteMagnitude))
        return CGSize(width: UIView.noIntrinsicMetric, height: size.height)
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        invalidateIntrinsicContentSize()
        
        // Calculate line breaks after layout and notify
        let lineBreaks = calculateLineBreaks()
        if lineBreaks != lastCalculatedLineBreaks {
            lastCalculatedLineBreaks = lineBreaks
            onLineBreaksCalculated?(lineBreaks)
        }
    }
    
    /// Calculate line break positions using the actual layout
    func calculateLineBreaks() -> [Int] {
        var lineBreaks: [Int] = []
        
        // Use TextKit 2 if available
        if let textLayoutManager = self.textLayoutManager,
           let textContentManager = textLayoutManager.textContentManager {
            
            textLayoutManager.enumerateTextLayoutFragments(
                from: textContentManager.documentRange.location,
                options: [.ensuresLayout]
            ) { fragment in
                for lineFragment in fragment.textLineFragments {
                    // Get the character range for this line
                    let lineRange = lineFragment.characterRange
                    let fragmentRange = fragment.rangeInElement
                    
                    // Calculate document offset
                    if let elementRange = fragment.textElement?.elementRange,
                       let startLocation = elementRange.location as? NSTextLocation {
                        let documentOffset = textContentManager.offset(
                            from: textContentManager.documentRange.location,
                            to: startLocation
                        )
                        let lineEnd = documentOffset + lineRange.location + lineRange.length
                        lineBreaks.append(lineEnd)
                    }
                }
                return true // Continue enumeration
            }
        } else {
            // Fallback to TextKit 1
            let layoutManager = self.layoutManager
            let textContainer = self.textContainer
            let textLength = self.text?.count ?? 0
            
            var glyphIndex = 0
            while glyphIndex < layoutManager.numberOfGlyphs {
                var lineRange = NSRange()
                layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: &lineRange)
                let charRange = layoutManager.characterRange(forGlyphRange: lineRange, actualGlyphRange: nil)
                lineBreaks.append(charRange.location + charRange.length)
                glyphIndex = lineRange.location + lineRange.length
                if glyphIndex <= lineRange.location { break }
            }
        }
        
        return lineBreaks
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
