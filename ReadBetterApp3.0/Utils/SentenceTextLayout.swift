//
//  SentenceTextLayout.swift
//  ReadBetterApp3.0
//
//  Lightweight text layout helper used for auto-scrolling:
//  - Measure rendered text height for a given width/font/lineSpacing
//  - Compute bounding rects for specific character ranges (words)
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
        
        let (layoutManager, textContainer) = makeLayout(text: text, width: w, font: font, lineSpacing: lineSpacing)
        layoutManager.ensureLayout(for: textContainer)
        let used = layoutManager.usedRect(for: textContainer)
        
        let result = Measurement(height: ceil(used.height), usedRect: used)
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
        
        let (layoutManager, textContainer) = makeLayout(text: text, width: w, font: font, lineSpacing: lineSpacing)
        layoutManager.ensureLayout(for: textContainer)
        let used = layoutManager.usedRect(for: textContainer)
        
        var rects: [Int: CGRect] = [:]
        rects.reserveCapacity(wordRanges.count)
        
        for (wordIndex, swiftRange) in wordRanges {
            let nsRange = NSRange(swiftRange, in: text)
            guard nsRange.location != NSNotFound, nsRange.length > 0 else { continue }
            
            let glyphRange = layoutManager.glyphRange(forCharacterRange: nsRange, actualCharacterRange: nil)
            guard glyphRange.length > 0 else { continue }
            
            let rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
            rects[wordIndex] = rect
        }
        
        let result = Layout(usedRect: used, rectsByWordIndex: rects)
        layoutCache[key] = result
        return result
    }
    
    // MARK: - Internals
    
    private static func makeLayout(text: String, width: CGFloat, font: UIFont, lineSpacing: CGFloat) -> (NSLayoutManager, NSTextContainer) {
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
        
        let textStorage = NSTextStorage(attributedString: attributed)
        let layoutManager = NSLayoutManager()
        textStorage.addLayoutManager(layoutManager)
        
        let textContainer = NSTextContainer(size: CGSize(width: width, height: .greatestFiniteMagnitude))
        textContainer.lineFragmentPadding = 0
        layoutManager.addTextContainer(textContainer)
        
        return (layoutManager, textContainer)
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









