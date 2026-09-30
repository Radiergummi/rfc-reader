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
///
/// `nonisolated`, as its superclass is: TextKit 2 may lay out and draw off the
/// main thread.
nonisolated final class RFCTextLayoutFragment: NSTextLayoutFragment {
  /// The fragment every layout manager of built text asks its delegate for: the
  /// reader's, and a print's (`DocumentPDF`), so the two cannot draw differently.
  ///
  /// - Parameter hover: which rendered block the pointer is over, on macOS, where
  ///   a block's Figure | Source control shows only then; nil for a print.
  static func make(for textElement: NSTextElement, hover: FigureHover? = nil)
    -> NSTextLayoutFragment
  {
    let fragment = RFCTextLayoutFragment(textElement: textElement, range: textElement.elementRange)
    fragment.figureHover = hover
    return fragment
  }

  /// Set once, as the fragment is made. See `make(for:hover:)`.
  private var figureHover: FigureHover?

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
    // A point of slack all round: a stroke is a line a point wide, centered on its
    // path, and antialiasing puts ink just outside it.
    if let strokes = StrokeGeometry.bounds(of: strokeSegments) {
      bounds = bounds.union(strokes.insetBy(dx: -1, dy: -1))
    }
    // Whether the control shows or not, so showing it on hover needs no new surface.
    if let control = controlRect(at: .zero) {
      bounds = bounds.union(control.insetBy(dx: -1, dy: -1))
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
    cachedStrokeSegments = nil
    super.invalidateLayout()
  }

  /// The segments of its block's strokes this fragment draws, cached for the reason
  /// the decoration span is, at the origin.
  private var cachedStrokeSegments: [StrokeGeometry.Segment]?

  private var strokeSegments: [StrokeGeometry.Segment] {
    if let cachedStrokeSegments { return cachedStrokeSegments }
    guard let text = textLayoutManager?.attributedText, let range = documentRange,
      let lineFragment = textLineFragments.first
    else { return [] }
    // Cached empty too: most fragments are prose, and this is read on every draw.
    var segments: [StrokeGeometry.Segment] = []
    if let (strokes, line) = StrokeGeometry.line(of: range, in: text),
      let font = text.attribute(.font, at: range.location, effectiveRange: nil) as? PlatformFont
    {
      segments = StrokeGeometry.segments(
        strokes, line: line, in: lineFragment, font: font, origin: .zero)
    }
    cachedStrokeSegments = segments
    return segments
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
      indent: span.indent,
      contentWidth: span.contentWidth
    )
  }

  // MARK: - Drawing

  override func draw(at point: CGPoint, in context: CGContext) {
    if let span = decorationSpan {
      context.saveGState()
      switch span.decoration {
      case .artwork, .table:
        drawCard(at: point, span: span, color: RFCColors.cardFill, in: context)
      case .aside:
        drawCard(at: point, span: span, color: RFCColors.asideFill, in: context)
      case .blockQuote:
        drawRule(at: point, span: span, in: context)
      }
      context.restoreGState()
    }
    drawChips(at: point, in: context)
    drawStrokes(at: point, in: context)
    super.draw(at: point, in: context)
    drawFigureControl(at: point, in: context)
  }

  // MARK: - Figure | Source

  /// The block's control this fragment draws, when it opens a block that has one.
  private var figureControl: FigureControl.Control? {
    guard let text = textLayoutManager?.attributedText, let range = documentRange else {
      return nil
    }
    return FigureControl.control(atFragment: range, in: text)
  }

  /// Where the control goes, in the space whose origin is `point`: the top-right
  /// corner of this fragment's card.
  private func controlRect(at point: CGPoint) -> CGRect? {
    guard figureControl != nil, let span = decorationSpan else { return nil }
    let card = placement(at: point, span: span).cardRect(
      padding: Self.cardPadding, span: span)
    return FigureControl.rect(inCard: card)
  }

  /// The two segments, the one showing filled. On macOS only while the pointer is
  /// over the block, so a page of diagrams is not covered in controls; on iOS,
  /// which has no hover, always.
  private func drawFigureControl(at point: CGPoint, in context: CGContext) {
    guard let control = figureControl, let rect = controlRect(at: point) else { return }
    #if !canImport(UIKit)
      guard figureHover?.current == control.ordinal else { return }
    #endif
    context.saveGState()
    let outline = CGPath(
      roundedRect: rect, cornerWidth: rect.height / 2, cornerHeight: rect.height / 2,
      transform: nil)
    context.addPath(outline)
    context.setFillColor(RFCColors.cardFill.cgColor)
    context.fillPath()
    for segment in [FigureControl.Segment.figure, .source] {
      let piece = FigureControl.rect(of: segment, in: rect)
      let showing = segment == control.shown
      if showing {
        context.saveGState()
        context.addPath(outline)
        context.clip()
        context.setFillColor(RFCColors.accent.withAlphaComponent(0.18).cgColor)
        context.fill(piece)
        context.restoreGState()
      }
      drawLabel(
        FigureControl.label(of: segment), centeredIn: piece,
        color: showing ? RFCColors.label : RFCColors.secondaryLabel, in: context)
    }
    context.addPath(outline)
    context.setStrokeColor(RFCColors.stroke.cgColor)
    context.setLineWidth(0.5)
    context.strokePath()
    context.restoreGState()
  }

  private func drawLabel(
    _ label: String, centeredIn rect: CGRect, color: PlatformColor, in context: CGContext
  ) {
    let text = NSAttributedString(
      string: label,
      attributes: [
        .font: PlatformFont.systemFont(ofSize: 11, weight: .medium), .foregroundColor: color,
      ])
    let size = text.size()
    let origin = CGPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2)
    #if canImport(UIKit)
      UIGraphicsPushContext(context)
      text.draw(at: origin)
      UIGraphicsPopContext()
    #else
      let previous = NSGraphicsContext.current
      NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
      text.draw(at: origin)
      NSGraphicsContext.current = previous
    #endif
  }

  /// Opaque lines rather than translucent fills, so where two fragments' pieces of
  /// one stroke meet at a shared edge they compose, and #31's seams cannot recur.
  private func drawStrokes(at point: CGPoint, in context: CGContext) {
    let segments = strokeSegments
    guard !segments.isEmpty else { return }
    context.saveGState()
    // Per draw, so a change of appearance or print's light appearance is picked up.
    context.setStrokeColor(RFCColors.stroke.cgColor)
    context.setLineWidth(1)
    context.setLineCap(.butt)
    for segment in segments {
      let start = CGPoint(x: segment.start.x + point.x, y: segment.start.y + point.y)
      let end = CGPoint(x: segment.end.x + point.x, y: segment.end.y + point.y)
      switch segment.style {
      case .solid:
        context.setLineDash(phase: 0, lengths: [])
        context.strokeLineSegments(between: [start, end])
      case .dashed:
        context.setLineDash(phase: segment.dashPhase, lengths: [3, 2])
        context.strokeLineSegments(between: [start, end])
      case .double:
        context.setLineDash(phase: 0, lengths: [])
        let across = start.y == end.y ? CGVector(dx: 0, dy: 1) : CGVector(dx: 1, dy: 0)
        for side in [-1.0, 1.0] {
          context.strokeLineSegments(between: [
            CGPoint(x: start.x + across.dx * side, y: start.y + across.dy * side),
            CGPoint(x: end.x + across.dx * side, y: end.y + across.dy * side),
          ])
        }
      }
    }
    context.restoreGState()
  }

  private func drawChips(at point: CGPoint, in context: CGContext) {
    let chips = chipRects
    guard !chips.isEmpty else { return }
    // Resolved once per draw rather than once per chip, but still per draw, so a
    // change of appearance or accent color is picked up. The geometry is not
    // appearance-dependent, so it comes from the cache and only moves.
    let tint = RFCColors.accent.withAlphaComponent(0.15).cgColor
    // An informative citation is background to the specification rather than part
    // of it, and reads so beside a normative one (#184). Half the tint, not a
    // different shape: a chip whose kind no list says is drawn as a normative one.
    let lighterTint = RFCColors.accent.withAlphaComponent(0.075).cgColor
    for chip in chips {
      fill(
        chip.rect.offsetBy(dx: point.x, dy: point.y),
        radius: FragmentGeometry.chipRadius,
        corners: FragmentGeometry.Corners(
          leading: chip.roundsLeading, trailing: chip.roundsTrailing),
        color: chip.isInformative ? lighterTint : tint,
        in: context
      )
    }
  }

  /// The card's outer padding is only added on the run's own top and/or bottom
  /// edge, and not even there where the run meets another card (`Placement.cardRect`)
  /// — a middle fragment sits flush against its neighbors, so consecutive
  /// fragments' cards tile into one continuous band instead of overlapping (and
  /// darkening, since the fill is translucent) at every line boundary. The joins
  /// are then moved onto the device pixel grid, or both neighbors half-cover the
  /// pixel they share and the band shows a darker line at every seam.
  private func drawCard(
    at point: CGPoint, span: FragmentGeometry.DecorationSpan, color: PlatformColor,
    in context: CGContext
  ) {
    let placement = placement(at: point, span: span)
    let card = placement.cardRect(padding: Self.cardPadding, span: span)
    fill(
      joined(card, placement: placement, span: span, in: context),
      radius: FragmentGeometry.cardRadius,
      corners: FragmentGeometry.Corners(first: span.isFirst, last: span.isLast),
      color: color.cgColor,
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
      corners: FragmentGeometry.Corners(first: span.isFirst, last: span.isLast),
      color: RFCColors.rule.cgColor,
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
    _ rect: CGRect, radius: CGFloat, corners: FragmentGeometry.Corners, color: CGColor,
    in context: CGContext
  ) {
    context.setFillColor(color)
    context.addPath(FragmentGeometry.roundedPath(in: rect, cornerRadius: radius, corners: corners))
    context.fillPath()
  }
}
