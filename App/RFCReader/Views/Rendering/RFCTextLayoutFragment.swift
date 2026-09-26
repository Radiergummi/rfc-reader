import RFCReaderKit

#if canImport(UIKit)
  import UIKit
#else
  import AppKit
#endif

/// Draws what attributed text cannot express: the card behind artwork and tables,
/// the rule beside a block quote, the tint behind an aside, and the reference chip.
///
/// Drawing only. Every "where does it go" question is `FragmentGeometry`, in
/// RFCReaderKit, where it is under test.
final class RFCTextLayoutFragment: NSTextLayoutFragment {
  static let cardPadding = FragmentGeometry.cardPadding
  static let rulePadding: CGFloat = 8
  static let ruleWidth: CGFloat = 3

  /// Everything drawn outside the glyph bounds has to be declared here or it is
  /// clipped away. Derived from the rects actually drawn rather than from a
  /// constant kept in step with them by hand: the card spans the whole column,
  /// which is far wider than a short artwork line's own fragment, the rule hangs
  /// further left still, and a chip's tint reaches past its glyphs at both ends.
  ///
  /// Only a fragment that draws something pays for this. Most of an RFC is plain
  /// prose, and inflating every fragment's backing store for decoration it does
  /// not have is pure cost.
  override var renderingSurfaceBounds: CGRect {
    var bounds = super.renderingSurfaceBounds
    if let span = decorationSpan {
      let placement = placement(at: .zero, span: span)
      // A point of slack above and below: a join snapped onto the pixel grid can
      // move outwards by up to half a pixel.
      let card = placement.decorationRect(padding: Self.cardPadding, capTop: true, capBottom: true)
      bounds = bounds.union(card.insetBy(dx: 0, dy: -1))
      if span.decoration == .blockQuote {
        // A point of slack on each side: the rule is drawn with rounded ends,
        // and antialiasing puts ink just outside the rect it is filled from.
        // This clipped by about a third once already, when the surface was
        // widened by the card's padding alone.
        let rule = placement.ruleRect(padding: Self.rulePadding, width: Self.ruleWidth)
        bounds = bounds.union(rule.insetBy(dx: -1, dy: -1))
      }
    }
    for chip in chipRects {
      bounds = bounds.union(chip.rect)
    }
    return bounds
  }

  // MARK: - Content

  /// The fragment's own span, as the document-relative character range every
  /// `FragmentGeometry` call is expressed in.
  private var documentRange: NSRange? {
    textLayoutManager?.range(of: rangeInElement)
  }

  /// All three are pure functions of content that is immutable once built, so they
  /// are worked out once per fragment rather than on every `renderingSurfaceBounds`
  /// read and every draw — and only once the content is actually reachable, or a
  /// fragment asked before its layout manager is attached would cache "nothing to
  /// draw" for good.
  ///
  /// The chip rects are cached at the origin, because only their position depends
  /// on where the fragment is being drawn.
  private var cachedDecorationSpan: FragmentGeometry.DecorationSpan??
  private var cachedChipRects: [FragmentGeometry.ChipRect]?

  override func invalidateLayout() {
    cachedDecorationSpan = nil
    cachedChipRects = nil
    super.invalidateLayout()
  }

  private var decorationSpan: FragmentGeometry.DecorationSpan? {
    if let cachedDecorationSpan { return cachedDecorationSpan }
    guard let text = textLayoutManager?.attributedText, let range = documentRange else {
      return nil
    }
    let span = FragmentGeometry.decorationSpan(in: text, fragment: range)
    cachedDecorationSpan = .some(span)
    return span
  }

  private var chipRects: [FragmentGeometry.ChipRect] {
    if let cachedChipRects { return cachedChipRects }
    guard let text = textLayoutManager?.attributedText, let range = documentRange else { return [] }
    let rects = FragmentGeometry.chipRects(
      in: text, lines: textLineFragments, fragment: range, origin: .zero)
    cachedChipRects = rects
    return rects
  }

  /// Where this fragment sits in the column, for whatever is drawn around it.
  private func placement(at point: CGPoint, span: FragmentGeometry.DecorationSpan)
    -> FragmentGeometry.Placement
  {
    FragmentGeometry.Placement(
      origin: point,
      frame: layoutFragmentFrame,
      containerWidth: textLayoutManager?.textContainer?.size.width ?? layoutFragmentFrame.width,
      indent: span.indent
    )
  }

  // MARK: - Drawing

  override func draw(at point: CGPoint, in context: CGContext) {
    if let span = decorationSpan {
      context.saveGState()
      switch span.decoration {
      case .artwork, .table:
        drawCard(at: point, span: span, alpha: 0.3, in: context)
      case .aside:
        drawCard(at: point, span: span, alpha: 0.4, in: context)
      case .blockQuote:
        drawRule(at: point, span: span, in: context)
      }
      context.restoreGState()
    }
    drawChips(at: point, in: context)
    super.draw(at: point, in: context)
  }

  private func drawChips(at point: CGPoint, in context: CGContext) {
    let chips = chipRects
    guard !chips.isEmpty else { return }
    // Resolved once per draw rather than once per chip, but still per draw, so a
    // change of appearance or accent colour is picked up. The geometry is not
    // appearance-dependent, so it comes from the cache and only moves.
    let tint = RFCColors.accent.withAlphaComponent(0.15).cgColor
    for chip in chips {
      fill(
        chip.rect.offsetBy(dx: point.x, dy: point.y),
        radius: 6,
        corners: Corners(leading: chip.roundsLeading, trailing: chip.roundsTrailing),
        color: tint,
        in: context
      )
    }
  }

  /// The card's outer padding is only added on the run's own top and/or bottom
  /// edge, and not even there where the run meets another card (`Placement.cardRect`)
  /// — a middle fragment sits flush against its neighbours, so consecutive
  /// fragments' cards tile into one continuous band instead of overlapping (and
  /// darkening, since the fill is translucent) at every line boundary. The joins
  /// are then moved onto the device pixel grid, or both neighbours half-cover the
  /// pixel they share and the band shows a darker line at every seam.
  private func drawCard(
    at point: CGPoint, span: FragmentGeometry.DecorationSpan, alpha: CGFloat, in context: CGContext
  ) {
    let placement = placement(at: point, span: span)
    let card = placement.cardRect(padding: Self.cardPadding, span: span)
    fill(
      joined(card, placement: placement, span: span, in: context),
      radius: 8,
      corners: Corners(first: span.isFirst, last: span.isLast),
      color: RFCColors.quaternaryFill.withAlphaComponent(alpha).cgColor,
      in: context
    )
  }

  /// Where the rule goes is `Placement.ruleRect`; this only fills it.
  private func drawRule(
    at point: CGPoint, span: FragmentGeometry.DecorationSpan, in context: CGContext
  ) {
    let placement = placement(at: point, span: span)
    let rule = placement.ruleRect(padding: Self.rulePadding, width: Self.ruleWidth)
    fill(
      joined(rule, placement: placement, span: span, in: context),
      radius: 1.5,
      corners: Corners(first: span.isFirst, last: span.isLast),
      color: RFCColors.quaternaryFill.cgColor,
      in: context
    )
  }

  /// `rect` with the edges it shares with the run's other fragments on the device
  /// pixel grid; `Placement.snappingJoins` says where they go.
  private func joined(
    _ rect: CGRect,
    placement: FragmentGeometry.Placement,
    span: FragmentGeometry.DecorationSpan,
    in context: CGContext
  ) -> CGRect {
    placement.snappingJoins(
      of: rect,
      top: !span.isFirst,
      bottom: !span.isLast,
      toDevice: context.userSpaceToDeviceSpaceTransform
    )
  }

  /// The tail every decoration shares: pick the corners, fill the rounded path.
  private func fill(
    _ rect: CGRect, radius: CGFloat, corners: Corners, color: CGColor, in context: CGContext
  ) {
    context.setFillColor(color)
    context.addPath(Self.roundedPath(in: rect, cornerRadius: radius, corners: corners))
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
    path.addArc(
      tangent1End: CGPoint(x: rect.minX, y: rect.minY),
      tangent2End: CGPoint(x: rect.minX + topLeftRadius, y: rect.minY), radius: topLeftRadius)
    path.addLine(to: CGPoint(x: rect.maxX - topRightRadius, y: rect.minY))
    path.addArc(
      tangent1End: CGPoint(x: rect.maxX, y: rect.minY),
      tangent2End: CGPoint(x: rect.maxX, y: rect.minY + topRightRadius), radius: topRightRadius)
    path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - bottomRightRadius))
    path.addArc(
      tangent1End: CGPoint(x: rect.maxX, y: rect.maxY),
      tangent2End: CGPoint(x: rect.maxX - bottomRightRadius, y: rect.maxY),
      radius: bottomRightRadius)
    path.addLine(to: CGPoint(x: rect.minX + bottomLeftRadius, y: rect.maxY))
    path.addArc(
      tangent1End: CGPoint(x: rect.minX, y: rect.maxY),
      tangent2End: CGPoint(x: rect.minX, y: rect.maxY - bottomLeftRadius), radius: bottomLeftRadius)
    path.closeSubpath()
    return path
  }
}

extension RFCTextLayoutFragment.Corners {
  /// A band that runs down the page: rounded where the run starts and ends,
  /// square where it continues into the next fragment.
  init(first: Bool, last: Bool) {
    self = []
    if first { formUnion(.top) }
    if last { formUnion(.bottom) }
  }

  /// A chip that runs along a line: rounded at the ends of the run, square where
  /// it continues onto the next line.
  init(leading: Bool, trailing: Bool) {
    self = []
    if leading { formUnion(.left) }
    if trailing { formUnion(.right) }
  }
}
