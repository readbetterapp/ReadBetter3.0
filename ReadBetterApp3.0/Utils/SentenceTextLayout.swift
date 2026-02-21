//
//  SentenceTextLayout.swift
//  ReadBetterApp3.0
//
//  Lightweight text layout helper used for auto-scrolling:
//  - Measure rendered text height for a given width/font/lineSpacing
//  - Compute bounding rects for specific character ranges (words)
//
//  Uses TextKit 2 for modern, consistent text layout matching UITextView.
//

import Foundation
import UIKit

enum SentenceTextLayout {
    struct Measurement {
        let height: CGFloat
        let usedRect: CGRect
    }
    
    struct Layout {
        let usedRect: CGRect
        let rectsByWordIndex: [Int: CGRect]
    }
    
    // Simple in-memory cache (good enough for a single reader session).
    private static var measurementCache: [MeasurementKey: Measurement] = [:]
    private static var layoutCache: [LayoutKey: Layout] = [:]
    
    // MARK: - Public
    
    static func measure(text: String, width: CGFloat, font: UIFont, lineSpacing: CGFloat) -> Measurement {
        let w = max(width, 1)
        let key = MeasurementKey(text: text, width: w, font: font, lineSpacing: lineSpacing)
        if let cached = measurementCache[key] { return cached }
        
        let (textLayoutManager, textContainer, _) = makeTextKit2Layout(text: text, width: w, font: font, lineSpacing: lineSpacing)
        textLayoutManager.ensureLayout(for: textLayoutManager.documentRange)
        
        // Calculate used rect from all layout fragments
        var usedRect = CGRect.zero
        textLayoutManager.enumerateTextLayoutFragments(
            from: textLayoutManager.documentRange.location,
            options: [.ensuresLayout]
        ) { fragment in
            usedRect = usedRect.union(fragment.layoutFragmentFrame)
            return true
        }
        
        let result = Measurement(height: ceil(usedRect.height), usedRect: usedRect)
        measurementCache[key] = result
        return result
    }
    
    static func layoutWordRects(
        sentenceId: UUID,
        text: String,
        wordRanges: [(wordIndex: Int, range: Range<String.Index>)],
        width: CGFloat,
        font: UIFont,
        lineSpacing: CGFloat
    ) -> Layout {
        let w = max(width, 1)
        let key = LayoutKey(sentenceId: sentenceId, text: text, width: w, font: font, lineSpacing: lineSpacing)
        if let cached = layoutCache[key] { return cached }
        
        let (textLayoutManager, textContainer, textContentStorage) = makeTextKit2Layout(text: text, width: w, font: font, lineSpacing: lineSpacing)
        textLayoutManager.ensureLayout(for: textLayoutManager.documentRange)
        
        // Calculate used rect
        var usedRect = CGRect.zero
        textLayoutManager.enumerateTextLayoutFragments(
            from: textLayoutManager.documentRange.location,
            options: [.ensuresLayout]
        ) { fragment in
            usedRect = usedRect.union(fragment.layoutFragmentFrame)
            return true
        }
        
        var rects: [Int: CGRect] = [:]
        rects.reserveCapacity(wordRanges.count)
        
        for (wordIndex, swiftRange) in wordRanges {
            let nsRange = NSRange(swiftRange, in: text)
            guard nsRange.location != NSNotFound, nsRange.length > 0 else { continue }
            
            // Convert NSRange to NSTextRange for TextKit 2
            guard let startLocation = textContentStorage.location(textContentStorage.documentRange.location, offsetBy: nsRange.location),
                  let endLocation = textContentStorage.location(startLocation, offsetBy: nsRange.length),
                  let textRange = NSTextRange(location: startLocation, end: endLocation) else {
                continue
            }
            
            // Get bounding rect for this text range
            var wordRect = CGRect.zero
            textLayoutManager.enumerateTextSegments(
                in: textRange,
                type: .standard,
                options: []
            ) { segmentRange, segmentFrame, baselinePosition, textContainer in
                if wordRect.isEmpty {
                    wordRect = segmentFrame
                } else {
                    wordRect = wordRect.union(segmentFrame)
                }
                return true
            }
            
            if !wordRect.isEmpty {
                rects[wordIndex] = wordRect
            }
        }
        
        let result = Layout(usedRect: usedRect, rectsByWordIndex: rects)
        layoutCache[key] = result
        return result
    }
    
    // MARK: - Internals
    
    private static func makeTextKit2Layout(text: String, width: CGFloat, font: UIFont, lineSpacing: CGFloat) -> (NSTextLayoutManager, NSTextContainer, NSTextContentStorage) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = lineSpacing
        paragraph.lineBreakMode = .byWordWrapping
        
        let attributed = NSAttributedString(
            string: text,
            attributes: [
                .font: font,
                .paragraphStyle: paragraph
            ]
        )
        
        // Create TextKit 2 infrastructure
        let textContentStorage = NSTextContentStorage()
        textContentStorage.attributedString = attributed
        
        let textLayoutManager = NSTextLayoutManager()
        textContentStorage.addTextLayoutManager(textLayoutManager)
        
        let textContainer = NSTextContainer(size: CGSize(width: width, height: .greatestFiniteMagnitude))
        textContainer.lineFragmentPadding = 0
        textLayoutManager.textContainer = textContainer
        
        return (textLayoutManager, textContainer, textContentStorage)
    }
    
    private struct MeasurementKey: Hashable {
        let textHash: Int
        let width: Int
        let fontName: String
        let fontSize: Int
        let fontWeightHash: Int
        let lineSpacing: Int
        
        init(text: String, width: CGFloat, font: UIFont, lineSpacing: CGFloat) {
            self.textHash = text.hashValue
            self.width = Int(width.rounded())
            self.fontName = font.fontName
            self.fontSize = Int(font.pointSize.rounded())
            self.fontWeightHash = font.fontDescriptor.symbolicTraits.rawValue.hashValue
            self.lineSpacing = Int(lineSpacing.rounded())
        }
    }
    
    private struct LayoutKey: Hashable {
        let sentenceId: UUID
        let textHash: Int
        let width: Int
        let fontName: String
        let fontSize: Int
        let fontWeightHash: Int
        let lineSpacing: Int
        
        init(sentenceId: UUID, text: String, width: CGFloat, font: UIFont, lineSpacing: CGFloat) {
            self.sentenceId = sentenceId
            self.textHash = text.hashValue
            self.width = Int(width.rounded())
            self.fontName = font.fontName
            self.fontSize = Int(font.pointSize.rounded())
            self.fontWeightHash = font.fontDescriptor.symbolicTraits.rawValue.hashValue
            self.lineSpacing = Int(lineSpacing.rounded())
        }
    }
}
