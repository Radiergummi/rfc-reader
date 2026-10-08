import RFCReaderKit

#if canImport(UIKit)
  import UIKit
#else
  import AppKit
#endif

/// Draws what attributed text cannot express: the card behind artwork and tables,
/// the rule beside a block quote, the tint behind an aside, Implementer's band behind
/// a requirement, and the reference chip.
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
  /// - Parameter palette: the colors it draws its decoration in: the reader's
  ///   setting, which a theme switch replaces without laying anything out again,
  ///   or for paper the automatic palette, which a print's light appearance
  ///   resolves to a white page's.
  static func make(
    for textElement: NSTextElement, palette: ReaderPaletteBox
  ) -> NSTextLayoutFragment {
    RFCTextLayoutFragment(
      textElement: textElement, range: textElement.elementRange, palette: palette)
  }

  /// A print's palette, whatever the reader's is (#703).
  static let paper = ReaderPaletteBox(.automatic)

  /// Read on every draw, so a replaced palette is picked up by the next one.
  private let paletteBox: ReaderPaletteBox

  init(textElement: NSTextElement, range: NSTextRange?, palette: ReaderPaletteBox) {
    paletteBox = palette
    super.init(textElement: textElement, range: range)
  }

  required init?(coder: NSCoder) {
    paletteBox = Self.paper
    super.init(coder: coder)
  }

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
    for band in bandRects {
      bounds = bounds.union(band.rect)
    }
    if let disclosure {
      bounds = bounds.union(
        FragmentGeometry.disclosureBounds(
          open: disclosure.open, firstLine: disclosure.firstLine, text: disclosure.text))
    }
    // A point of slack all round: a stroke is a line a point wide, centered on its
    // path, and antialiasing puts ink just outside it.
    if let strokes = StrokeGeometry.bounds(of: strokeSegments) {
      bounds = bounds.union(strokes.insetBy(dx: -1, dy: -1))
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
    // The reading mode's folding: a card whose rest it hides ends with what it shows.
    let folding = textLayoutManager?.textContentManager?.delegate as? FoldingDelegate
    let span = FragmentGeometry.decorationSpan(
      in: text, fragment: range, hidden: folding?.hidden ?? HiddenText())
    cachedDecorationSpan = .some(span)
    return span
  }

  private var chipRects: [FragmentGeometry.ChipRect] {
    if let cachedChipRects { return cachedChipRects }
    guard let text = textLayoutManager?.attributedText, let range = documentRange else { return [] }
    let rects = FragmentGeometry.chipRects(
      in: text, fragment: FragmentLines(range: range, lines: textLineFragments), origin: .zero)
    cachedChipRects = rects
    return rects
  }

  /// Where Implementer's requirement bands go on this fragment's lines (#700), from
  /// the bands its layout manager's content holds. Not cached: a change of mode
  /// changes them without changing the fragment's text.
  private var bandRects: [FragmentGeometry.BandRect] {
    guard let range = documentRange,
      let folding = textLayoutManager?.textContentManager?.delegate as? FoldingDelegate,
      let text = textLayoutManager?.attributedText
    else { return [] }
    let bands = folding.bands(meeting: range)
    guard !bands.isEmpty else { return [] }
    return FragmentGeometry.bandRects(
      bands, in: text, lines: textLineFragments, fragment: range, origin: .zero)
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
      contentWidth: span.contentWidth,
      spacingBefore: span.spacingBefore,
      spacingAfter: span.spacingAfter
    )
  }

  // MARK: - Drawing

  override func draw(at point: CGPoint, in context: CGContext) {
    // Once per draw, so a theme switch is picked up by the redraw it asks for.
    let palette = paletteBox.palette
    // What the chips are drawn on: the page, or a card's fill over it.
    var card: PlatformColor?
    if let span = decorationSpan {
      context.saveGState()
      switch span.decoration {
      case .artwork, .table:
        card = palette.cardFill
        drawCard(at: point, span: span, color: palette.cardFill, in: context)
      case .aside:
        card = palette.asideFill
        drawCard(at: point, span: span, color: palette.asideFill, in: context)
      case .blockQuote:
        drawRule(at: point, span: span, color: palette.rule, in: context)
      }
      context.restoreGState()
    }
    let banded = drawBands(at: point, in: context)
    drawChips(at: point, palette: palette, on: card, banded: banded, in: context)
    drawStrokes(at: point, color: palette.stroke, in: context)
    super.draw(at: point, in: context)
    drawDisclosure(at: point, in: context)
  }

  /// Opaque lines rather than translucent fills, so where two fragments' pieces of
  /// one stroke meet at a shared edge they compose, and #31's seams cannot recur.
  private func drawStrokes(at point: CGPoint, color: PlatformColor, in context: CGContext) {
    let segments = strokeSegments
    guard !segments.isEmpty else { return }
    context.saveGState()
    // Per draw, so a change of appearance or print's light appearance is picked up.
    context.setStrokeColor(color.cgColor)
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

  /// Implementer's bands behind this fragment's requirement sentences (#700), over
  /// a card where there is one and under the chips; answers whether there were any.
  private func drawBands(at point: CGPoint, in context: CGContext) -> Bool {
    let bands = bandRects
    guard !bands.isEmpty else { return false }
    context.saveGState()
    let color = RFCColors.requirementBand.cgColor
    for band in bands {
      fill(
        band.rect.offsetBy(dx: point.x, dy: point.y), radius: FragmentGeometry.chipRadius,
        corners: band.corners, color: color, in: context)
    }
    context.restoreGState()
    return true
  }

  /// The chip tint's opacity for `tint` as it resolves now, on the page or on
  /// `card` over it, and under a requirement band where the fragment has one:
  /// lighter than 15% where the link would not clear the minimum contrast on it
  /// (#317). On a card the link is the card's link color (#694).
  private static func chipTintOpacity(
    of tint: PlatformColor, on card: PlatformColor?, banded: Bool
  ) -> Double {
    guard let accent = SRGBColor(resolving: tint),
      let link = SRGBColor(
        resolving: card == nil
          ? RFCColors.readerLink : RFCColors.cardLink(over: RFCColors.readerLink)),
      let backdrop = chipBackdrop(on: card, banded: banded)
    else { return AccentContrast.chipTint }
    return AccentContrast.chipTintOpacity(accent: accent, link: link, page: backdrop)
  }

  /// The hairline a chip is outlined with for `tint` as it resolves now, on the page
  /// or on `card`, and under a band where there is one: held to 3:1 against it
  /// (#457).
  private static func chipOutline(
    of tint: PlatformColor, on card: PlatformColor?, banded: Bool
  ) -> CGColor {
    guard let accent = SRGBColor(resolving: tint),
      let backdrop = chipBackdrop(on: card, banded: banded)
    else { return tint.cgColor }
    let outline = AccentContrast.chipOutline(accent: accent, backdrop: backdrop)
    return CGColor(srgbRed: outline.red, green: outline.green, blue: outline.blue, alpha: 1)
  }

  /// What a chip is drawn over, as it resolves now: the page, a card's fill over it,
  /// and a requirement band over that.
  private static func chipBackdrop(on card: PlatformColor?, banded: Bool) -> SRGBColor? {
    guard var backdrop = SRGBColor(resolving: RFCColors.page) else { return nil }
    if let card, let fill = SRGBColor.resolvingWithOpacity(card) {
      backdrop = fill.color.composited(opacity: fill.opacity, over: backdrop)
    }
    if banded, let band = SRGBColor.resolvingWithOpacity(RFCColors.requirementBand) {
      backdrop = band.color.composited(opacity: band.opacity, over: backdrop)
    }
    return backdrop
  }

  // MARK: - Disclosure

  /// A heading's disclosure, as the outline draws it: whether its section is open,
  /// the heading's first line, and where its text sits on that line.
  private struct Disclosure {
    let open: Bool
    let firstLine: CGRect
    let text: FragmentGeometry.HeadingText
  }

  /// Whether this fragment is a heading the outline discloses, or an aside's caption
  /// Implementer does, and if so its disclosure: from the folding its layout
  /// manager's content holds (#698, #700).
  private var disclosure: Disclosure? {
    guard let range = documentRange,
      let folding = textLayoutManager?.textContentManager?.delegate as? FoldingDelegate,
      let open = folding.disclosure(at: range.location),
      let line = textLineFragments.first
    else { return nil }
    let bounds = line.typographicBounds
    let font =
      line.attributedString.length > line.characterRange.location
      ? line.attributedString.attribute(
        .font, at: line.characterRange.location, effectiveRange: nil)
        as? PlatformFont : nil
    // Without a font, the line's own height stands in for the capitals'.
    let capHeight = font?.capHeight ?? bounds.height * 0.5
    let text = FragmentGeometry.HeadingText(
      baseline: bounds.minY + line.glyphOrigin.y, capHeight: capHeight)
    // Measured from the column's edge, not the line's: an aside's caption is set in
    // from it, and its chevron belongs in the gutter as a heading's does (#700).
    var firstLine = bounds
    firstLine.origin.x = -layoutFragmentFrame.minX
    return Disclosure(open: open, firstLine: firstLine, text: text)
  }

  private func drawDisclosure(at point: CGPoint, in context: CGContext) {
    guard let disclosure else { return }
    let chevron = FragmentGeometry.disclosureChevron(
      open: disclosure.open, firstLine: disclosure.firstLine, text: disclosure.text)
    guard let first = chevron.first else { return }
    context.saveGState()
    context.setStrokeColor(RFCColors.secondaryLabel.cgColor)
    context.setLineWidth(1.5)
    context.setLineCap(.round)
    context.setLineJoin(.round)
    context.move(to: CGPoint(x: point.x + first.x, y: point.y + first.y))
    for next in chevron.dropFirst() {
      context.addLine(to: CGPoint(x: point.x + next.x, y: point.y + next.y))
    }
    context.strokePath()
    context.restoreGState()
  }

  private func drawChips(
    at point: CGPoint, palette: ReaderPalette, on card: PlatformColor?, banded: Bool,
    in context: CGContext
  ) {
    let chips = chipRects
    guard !chips.isEmpty else { return }
    // Resolved once per draw rather than once per chip, but still per draw, so a
    // change of appearance or accent color is picked up. The geometry is not
    // appearance-dependent, so it comes from the cache and only moves.
    let chipTint = palette.chipTint
    let opacity = Self.chipTintOpacity(of: chipTint, on: card, banded: banded)
    let tint = chipTint.withAlphaComponent(opacity).cgColor
    let outline = Self.chipOutline(of: chipTint, on: card, banded: banded)
    for chip in chips {
      // An informative citation is background to the specification rather than
      // part of it, and reads so beside a normative one by its shape (#184, #457):
      // `ReaderPalette.chipMarks` says which marks each kind gets.
      let marks = palette.chipMarks(informative: chip.isInformative)
      let rect = chip.rect.offsetBy(dx: point.x, dy: point.y)
      let corners = FragmentGeometry.Corners(
        leading: chip.roundsLeading, trailing: chip.roundsTrailing)
      if marks.fills {
        fill(rect, radius: FragmentGeometry.chipRadius, corners: corners, color: tint, in: context)
      }
      if marks.outlines {
        // Inside the chip's box, so it covers what the fill would and no more.
        let inset = FragmentGeometry.chipOutlineWidth / 2
        context.setStrokeColor(outline)
        context.setLineWidth(FragmentGeometry.chipOutlineWidth)
        context.addPath(
          FragmentGeometry.roundedPath(
            in: rect.insetBy(dx: inset, dy: inset),
            cornerRadius: FragmentGeometry.chipRadius - inset, corners: corners))
        context.strokePath()
      }
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
    at point: CGPoint, span: FragmentGeometry.DecorationSpan, color: PlatformColor,
    in context: CGContext
  ) {
    let placement = placement(at: point, span: span)
    let rule = placement.ruleRect(padding: Self.rulePadding, width: Self.ruleWidth)
    fill(
      joined(rule, placement: placement, span: span, in: context),
      radius: 1.5,
      corners: FragmentGeometry.Corners(first: span.isFirst, last: span.isLast),
      color: color.cgColor,
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
