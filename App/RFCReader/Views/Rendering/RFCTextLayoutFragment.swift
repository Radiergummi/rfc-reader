import RFCReaderKit

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
    static let ruleWidth: CGFloat = 3

    /// The furthest any decoration reaches outside its own fragment frame. The
    /// rule sits `rulePadding + ruleWidth` to the left of the text, which is more
    /// than the card's `cardPadding` — widening by only `cardPadding` clips about a
    /// third of the rule.
    private static let surfaceInset = max(cardPadding, rulePadding + ruleWidth)

    /// Without widening this, the card and the rule are clipped to the glyph bounds.
    override var renderingSurfaceBounds: CGRect {
        super.renderingSurfaceBounds.union(
            CGRect(origin: .zero, size: layoutFragmentFrame.size)
                .insetBy(dx: -Self.surfaceInset, dy: -Self.cardPadding)
        )
    }

    /// A decoration this fragment's own range carries, plus whether it is the
    /// first and/or last fragment of that decoration's run.
    private struct DecorationSpan {
        let decoration: RFCDecoration
        let isFirst: Bool
        let isLast: Bool
    }

    /// A decoration can span several fragments — a multi-line artwork block lays
    /// out one fragment per line, and a multi-row table one per row — because the
    /// builder stores the attribute once per contiguous run rather than once per
    /// fragment. `effectiveRange` names that whole run; comparing this fragment's
    /// own start and end against it says whether this fragment is the run's first,
    /// its last, both (the common single-fragment case), or neither (a middle
    /// fragment, which draws no cap and must not repeat the run's outer padding
    /// or its rounding, or the band would show a seam at every fragment boundary).
    private var decorationSpan: DecorationSpan? {
        guard let textLayoutManager,
              let storage = textLayoutManager.textContentManager as? NSTextContentStorage,
              let text = storage.attributedString else { return nil }
        let documentStart = textLayoutManager.documentRange.location
        let start = textLayoutManager.offset(from: documentStart, to: rangeInElement.location)
        guard start >= 0, start < text.length else { return nil }
        var effectiveRange = NSRange(location: 0, length: 0)
        guard let decoration = text.attribute(.rfcDecoration, at: start, effectiveRange: &effectiveRange) as? RFCDecoration else { return nil }
        let end = textLayoutManager.offset(from: documentStart, to: rangeInElement.endLocation)
        return DecorationSpan(
            decoration: decoration,
            isFirst: start <= effectiveRange.location,
            isLast: end >= NSMaxRange(effectiveRange)
        )
    }

    override func draw(at point: CGPoint, in context: CGContext) {
        if let span = decorationSpan {
            let frame = CGRect(origin: point, size: layoutFragmentFrame.size)
            context.saveGState()
            switch span.decoration {
            case .artwork, .table:
                drawCard(frame: frame, span: span, alpha: 0.3, in: context)
            case .aside:
                drawCard(frame: frame, span: span, alpha: 0.4, in: context)
            case .blockQuote:
                drawRule(frame: frame, span: span, in: context)
            }
            context.restoreGState()
        }
        super.draw(at: point, in: context)
    }

    /// The card's outer padding is only added on the run's own top and/or bottom
    /// edge — a middle fragment sits flush against its neighbours, so consecutive
    /// fragments' cards tile into one continuous band instead of overlapping (and
    /// darkening, since the fill is translucent) at every line boundary.
    private func drawCard(frame: CGRect, span: DecorationSpan, alpha: CGFloat, in context: CGContext) {
        let topInset = span.isFirst ? Self.cardPadding / 2 : 0
        let bottomInset = span.isLast ? Self.cardPadding / 2 : 0
        let card = CGRect(
            x: frame.minX - Self.cardPadding,
            y: frame.minY - topInset,
            width: frame.width + Self.cardPadding * 2,
            height: frame.height + topInset + bottomInset
        )
        context.setFillColor(RFCColors.quaternaryFill.withAlphaComponent(alpha).cgColor)
        context.addPath(Self.roundedPath(in: card, cornerRadius: 8, roundTop: span.isFirst, roundBottom: span.isLast))
        context.fillPath()
    }

    private func drawRule(frame: CGRect, span: DecorationSpan, in context: CGContext) {
        let rule = CGRect(x: frame.minX - Self.rulePadding - Self.ruleWidth, y: frame.minY, width: Self.ruleWidth, height: frame.height)
        context.setFillColor(RFCColors.quaternaryFill.cgColor)
        context.addPath(Self.roundedPath(in: rule, cornerRadius: 1.5, roundTop: span.isFirst, roundBottom: span.isLast))
        context.fillPath()
    }

    /// `rect`, rounded only on the edges named — square where a decoration's band
    /// continues into the next or previous fragment, rounded where the band
    /// starts or ends. `CGPath(roundedRect:cornerWidth:cornerHeight:transform:)`
    /// has no per-corner variant, hence the manual path. Task 12's reference chip
    /// can wrap across a line break, which is the same shape problem, so this is
    /// written to be reused there rather than duplicated.
    static func roundedPath(in rect: CGRect, cornerRadius: CGFloat, roundTop: Bool, roundBottom: Bool) -> CGPath {
        let radius = max(0, min(cornerRadius, min(rect.width, rect.height) / 2))
        let topRadius = roundTop ? radius : 0
        let bottomRadius = roundBottom ? radius : 0
        let path = CGMutablePath()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY + topRadius))
        path.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.minY), tangent2End: CGPoint(x: rect.minX + topRadius, y: rect.minY), radius: topRadius)
        path.addLine(to: CGPoint(x: rect.maxX - topRadius, y: rect.minY))
        path.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.minY), tangent2End: CGPoint(x: rect.maxX, y: rect.minY + topRadius), radius: topRadius)
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - bottomRadius))
        path.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.maxY), tangent2End: CGPoint(x: rect.maxX - bottomRadius, y: rect.maxY), radius: bottomRadius)
        path.addLine(to: CGPoint(x: rect.minX + bottomRadius, y: rect.maxY))
        path.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.maxY), tangent2End: CGPoint(x: rect.minX, y: rect.maxY - bottomRadius), radius: bottomRadius)
        path.closeSubpath()
        return path
    }
}
