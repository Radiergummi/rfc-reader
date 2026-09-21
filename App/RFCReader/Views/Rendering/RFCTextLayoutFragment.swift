import RFCReaderKit
import SwiftUI

#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

/// Draws what attributed text cannot express: the card behind artwork and tables,
/// the rule beside a block quote, the tint behind an aside — and, from Task 12, the
/// reference chip.
final class RFCTextLayoutFragment: NSTextLayoutFragment {
    static let cardPadding: CGFloat = 10
    static let rulePadding: CGFloat = 8

    /// Without widening this, the card and the rule are clipped to the glyph bounds.
    override var renderingSurfaceBounds: CGRect {
        super.renderingSurfaceBounds.union(
            CGRect(origin: .zero, size: layoutFragmentFrame.size)
                .insetBy(dx: -Self.cardPadding, dy: -Self.cardPadding)
        )
    }

    /// What this fragment's own range is decorated with, if anything. Decoration
    /// nesting is already resolved by the time the builder writes the attribute — an
    /// aside inside a block quote leaves `.blockQuote` on the surrounding paragraphs
    /// and `.aside` on its own — so one fragment (one paragraph) reads as one value,
    /// or none, never a mix; this samples the attribute at the fragment's own start
    /// rather than assuming a decoration carried over from the block around it.
    private var decoration: RFCDecoration? {
        guard let textLayoutManager,
              let storage = textLayoutManager.textContentManager as? NSTextContentStorage,
              let text = storage.attributedString else { return nil }
        let offset = textLayoutManager.offset(from: textLayoutManager.documentRange.location, to: rangeInElement.location)
        guard offset >= 0, offset < text.length else { return nil }
        return text.attribute(.rfcDecoration, at: offset, effectiveRange: nil) as? RFCDecoration
    }

    override func draw(at point: CGPoint, in context: CGContext) {
        if let decoration {
            let frame = CGRect(origin: point, size: layoutFragmentFrame.size)
            context.saveGState()
            switch decoration {
            case .artwork, .table:
                let card = frame.insetBy(dx: -Self.cardPadding, dy: -Self.cardPadding / 2)
                context.setFillColor(RFCColors.quaternaryFill.withAlphaComponent(0.3).cgColor)
                context.addPath(CGPath(roundedRect: card, cornerWidth: 8, cornerHeight: 8, transform: nil))
                context.fillPath()
            case .blockQuote:
                let rule = CGRect(x: frame.minX - Self.rulePadding - 3, y: frame.minY, width: 3, height: frame.height)
                context.setFillColor(RFCColors.quaternaryFill.cgColor)
                context.addPath(CGPath(roundedRect: rule, cornerWidth: 1.5, cornerHeight: 1.5, transform: nil))
                context.fillPath()
            case .aside:
                let card = frame.insetBy(dx: -Self.cardPadding, dy: -Self.cardPadding / 2)
                context.setFillColor(RFCColors.quaternaryFill.withAlphaComponent(0.4).cgColor)
                context.addPath(CGPath(roundedRect: card, cornerWidth: 8, cornerHeight: 8, transform: nil))
                context.fillPath()
            }
            context.restoreGState()
        }
        super.draw(at: point, in: context)
    }
}
