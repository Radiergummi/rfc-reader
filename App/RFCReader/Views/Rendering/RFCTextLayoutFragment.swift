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
        drawChips(at: point, in: context)
        super.draw(at: point, in: context)
    }

    /// A chip's fill and rounding, worked out per *line* fragment. A chip that
    /// wraps is still one contiguous `.rfcChip` run laid out across several
    /// `NSTextLineFragment`s inside this single layout fragment (TextKit 2 lays
    /// out a whole paragraph as one fragment holding many line fragments) — so the
    /// line that holds the run's first character rounds only its left corners, the
    /// line holding its last character rounds only its right corners, and a middle
    /// line (a chip wrapping across three or more lines) rounds neither.
    private struct ChipRect {
        let rect: CGRect
        let roundsLeading: Bool
        let roundsTrailing: Bool
    }

    private static let chipPadding: CGFloat = 5

    /// The chip's own padding (5 pt) is well inside `surfaceInset` (11 pt, from the
    /// rule), so drawing outside the glyph bounds by that much still lands inside
    /// `renderingSurfaceBounds` and needs no separate widening there.
    private func chipRects(at point: CGPoint) -> [ChipRect] {
        guard let textLayoutManager,
              let storage = textLayoutManager.textContentManager as? NSTextContentStorage,
              let text = storage.attributedString else { return [] }
        let documentStart = textLayoutManager.documentRange.location
        let fragmentStart = textLayoutManager.offset(from: documentStart, to: rangeInElement.location)
        guard fragmentStart >= 0 else { return [] }

        var result: [ChipRect] = []
        for line in textLineFragments {
            let lineStart = fragmentStart + line.characterRange.location
            let lineRange = NSRange(location: lineStart, length: line.characterRange.length)
            guard lineRange.location >= 0, NSMaxRange(lineRange) <= text.length else { continue }

            text.enumerateAttribute(.rfcChip, in: lineRange) { value, pieceRange, _ in
                guard value != nil else { return }

                // The piece `enumerateAttribute` hands back is already clipped to
                // this line; the run's own full extent — which may start before or
                // end after this line — decides which ends round.
                var runRange = NSRange(location: 0, length: 0)
                _ = text.attribute(.rfcChip, at: pieceRange.location, effectiveRange: &runRange)
                let roundsLeading = runRange.location >= lineRange.location
                let roundsTrailing = NSMaxRange(runRange) <= NSMaxRange(lineRange)

                // `locationForCharacter(at:)` takes an index relative to
                // `line.attributedString` — the whole paragraph the fragment lays
                // out, not the line — so the index has to be relative to the
                // fragment's start, not the line's. The two coincide only on the
                // fragment's first line, which is why every hand-trace and every
                // single-line fixture looked right before this fix.
                let localStart = pieceRange.location - fragmentStart
                let localEnd = localStart + pieceRange.length
                let startX = line.locationForCharacter(at: localStart).x
                let endX = line.locationForCharacter(at: localEnd).x
                let padLeft: CGFloat = roundsLeading ? Self.chipPadding : 0
                let padRight: CGFloat = roundsTrailing ? Self.chipPadding : 0

                let rect = CGRect(
                    x: point.x + line.typographicBounds.minX + startX - padLeft,
                    y: point.y + line.typographicBounds.minY + 1,
                    width: endX - startX + padLeft + padRight,
                    height: line.typographicBounds.height - 2
                )
                result.append(ChipRect(rect: rect, roundsLeading: roundsLeading, roundsTrailing: roundsTrailing))
            }
        }
        return result
    }

    private func drawChips(at point: CGPoint, in context: CGContext) {
        for chip in chipRects(at: point) {
            var corners: Corners = []
            if chip.roundsLeading { corners.formUnion(.left) }
            if chip.roundsTrailing { corners.formUnion(.right) }
            context.setFillColor(RFCColors.accent.withAlphaComponent(0.15).cgColor)
            context.addPath(Self.roundedPath(in: chip.rect, cornerRadius: 6, corners: corners))
            context.fillPath()
        }
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
        var corners: Corners = []
        if span.isFirst { corners.formUnion(.top) }
        if span.isLast { corners.formUnion(.bottom) }
        context.setFillColor(RFCColors.quaternaryFill.withAlphaComponent(alpha).cgColor)
        context.addPath(Self.roundedPath(in: card, cornerRadius: 8, corners: corners))
        context.fillPath()
    }

    private func drawRule(frame: CGRect, span: DecorationSpan, in context: CGContext) {
        let rule = CGRect(x: frame.minX - Self.rulePadding - Self.ruleWidth, y: frame.minY, width: Self.ruleWidth, height: frame.height)
        var corners: Corners = []
        if span.isFirst { corners.formUnion(.top) }
        if span.isLast { corners.formUnion(.bottom) }
        context.setFillColor(RFCColors.quaternaryFill.cgColor)
        context.addPath(Self.roundedPath(in: rule, cornerRadius: 1.5, corners: corners))
        context.fillPath()
    }

    /// Which corners `roundedPath` should round.
    struct Corners: OptionSet {
        let rawValue: Int
        static let topLeft = Corners(rawValue: 1 << 0)
        static let topRight = Corners(rawValue: 1 << 1)
        static let bottomLeft = Corners(rawValue: 1 << 2)
        static let bottomRight = Corners(rawValue: 1 << 3)
        static let top: Corners = [.topLeft, .topRight]
        static let bottom: Corners = [.bottomLeft, .bottomRight]
        static let left: Corners = [.topLeft, .bottomLeft]
        static let right: Corners = [.topRight, .bottomRight]
        static let all: Corners = [.top, .bottom]
    }

    /// `rect`, rounded only on the corners named — square where a decoration's band
    /// continues into the next or previous fragment, rounded where the band starts
    /// or ends. `CGPath(roundedRect:cornerWidth:cornerHeight:transform:)` has no
    /// per-corner variant, hence the manual path. The reference chip needs this at
    /// a finer grain than the card and the rule do: a chip that wraps across a
    /// line break rounds the left two corners on its first line and the right two
    /// on its last, which top/bottom rounding alone cannot express.
    static func roundedPath(in rect: CGRect, cornerRadius: CGFloat, corners: Corners) -> CGPath {
        let radius = max(0, min(cornerRadius, min(rect.width, rect.height) / 2))
        let topLeftRadius = corners.contains(.topLeft) ? radius : 0
        let topRightRadius = corners.contains(.topRight) ? radius : 0
        let bottomRightRadius = corners.contains(.bottomRight) ? radius : 0
        let bottomLeftRadius = corners.contains(.bottomLeft) ? radius : 0
        let path = CGMutablePath()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY + topLeftRadius))
        path.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.minY), tangent2End: CGPoint(x: rect.minX + topLeftRadius, y: rect.minY), radius: topLeftRadius)
        path.addLine(to: CGPoint(x: rect.maxX - topRightRadius, y: rect.minY))
        path.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.minY), tangent2End: CGPoint(x: rect.maxX, y: rect.minY + topRightRadius), radius: topRightRadius)
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - bottomRightRadius))
        path.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.maxY), tangent2End: CGPoint(x: rect.maxX - bottomRightRadius, y: rect.maxY), radius: bottomRightRadius)
        path.addLine(to: CGPoint(x: rect.minX + bottomLeftRadius, y: rect.maxY))
        path.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.maxY), tangent2End: CGPoint(x: rect.minX, y: rect.maxY - bottomLeftRadius), radius: bottomLeftRadius)
        path.closeSubpath()
        return path
    }
}
