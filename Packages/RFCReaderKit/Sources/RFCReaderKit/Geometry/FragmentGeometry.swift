import Foundation

#if canImport(UIKit)
  import UIKit
#else
  import AppKit
#endif

/// Where the decorations a text layout fragment draws actually go.
///
/// Pure geometry over an attributed string, its line fragments and the fragment's
/// own start offset — no `NSTextLayoutFragment`, no drawing context, no state. The
/// app's fragment subclass is the shell that owns drawing; this is the arithmetic
/// it draws by.
///
/// It lives in this package on purpose. The reader's two hardest bugs were both in
/// these few lines — an index taken relative to a *line* where TextKit 2 wanted it
/// relative to the *element* — and while they lived in the app target, which has no
/// test bundle, the only thing a test could do was re-implement them and check the
/// copy. Here they can simply be called.
public enum FragmentGeometry {
  /// The padding a chip's tint extends past its glyphs, on the ends that round.
  public static let chipPadding: CGFloat = 5

  /// The padding a chip's tint extends above its font's ascender and below its
  /// descender.
  public static let chipVerticalPadding: CGFloat = 2

  /// The padding a card extends past its column on either side, and half of it
  /// past its run's own first and last line.
  public static let cardPadding: CGFloat = 10

  /// How far a verbatim block's text is set in from the column on either side,
  /// inside its card, which stays where it is (`.rfcCardInset`): the card's padding
  /// alone left the code close to its edge, against the larger padding below it.
  public static let cardInset: CGFloat = cardPadding / 2

  /// A decoration a fragment's own range carries, plus whether it is the first
  /// and/or last fragment of that decoration's run.
  public struct DecorationSpan: Equatable, Sendable {
    public let decoration: RFCDecoration
    public let isFirst: Bool
    public let isLast: Bool
    /// The whole run this fragment belongs to, which is what the band is
    /// measured against.
    public let runRange: NSRange
    /// The shallowest paragraph indent anywhere in that run: where the band
    /// starts. Computed with the span because it is a scan over the run, and
    /// the drawing path asks for it on every draw.
    public let indent: CGFloat
    /// Whether the run starts directly below another card, and ends directly
    /// above one: the ends `Placement.cardRect` cuts rather than caps.
    public let meetsCardAbove: Bool
    public let meetsCardBelow: Bool
    /// How wide the run's content is set, where the card hugs it: a figure's
    /// widest line. Nil where the card spans the column.
    public let contentWidth: CGFloat?
    /// The paragraph spacing before and after this fragment's own paragraph, which
    /// its frame includes, and a card's capped end leaves out.
    public var spacingBefore: CGFloat = 0
    public var spacingAfter: CGFloat = 0
  }

  /// A chip's fill and rounding, worked out per *line* fragment.
  public struct ChipRect: Equatable, Sendable {
    public let rect: CGRect
    public let roundsLeading: Bool
    public let roundsTrailing: Bool
    public let isInformative: Bool
  }

  /// A decoration can span several fragments — a multi-line artwork block lays out
  /// one fragment per line, and a multi-row table one per row — because the builder
  /// stores the attribute once per contiguous run rather than once per fragment.
  /// `decorationRun(at:)` names that whole run; comparing the fragment's own start and
  /// end against it says whether this fragment is the run's first, its last, both
  /// (the common single-fragment case), or neither (a middle fragment, which draws
  /// no cap and must not repeat the run's outer padding or its rounding, or the
  /// band would show a seam at every fragment boundary).
  ///
  /// A run whose rest a reading mode folds away, an aside closed under its caption
  /// (#700), ends where what is shown of it ends, and the run after it meets no card
  /// there: `hidden` is what the mode hides.
  public static func decorationSpan(
    in text: NSAttributedString, fragment: NSRange, hidden: HiddenText = HiddenText()
  ) -> DecorationSpan? {
    // The block's whole run, across its storage runs (`decorationRun(at:)`). Artwork
    // depends on that as much as a table does: its last line carries the block's
    // spacing alone (#31), which is a storage run of its own.
    guard let run = text.decorationRun(at: fragment.location) else { return nil }
    var effective = verbatimBlock(in: text, at: fragment.location, within: run.range)
    let shownEnd = hidden.shownEnd(of: effective)
    let isFolded = shownEnd < NSMaxRange(effective)
    effective.length = shownEnd - effective.location
    let paragraph =
      text.attribute(.paragraphStyle, at: fragment.location, effectiveRange: nil)
      as? NSParagraphStyle
    return DecorationSpan(
      decoration: run.decoration,
      isFirst: fragment.location <= effective.location,
      isLast: NSMaxRange(fragment) >= NSMaxRange(effective),
      runRange: effective,
      // The card is measured from where the block's text would sit without its
      // inset, so the inset is room inside the card rather than a moved card.
      indent: indent(in: text, over: effective)
        - (text.attribute(.rfcCardInset, at: effective.location, effectiveRange: nil) as? CGFloat
          ?? 0),
      // A card the mode has folded away above this one is not met either.
      meetsCardAbove: !hidden.contains(effective.location - 1)
        && drawsCard(in: text, at: effective.location - 1),
      meetsCardBelow: !isFolded && drawsCard(in: text, at: NSMaxRange(effective)),
      contentWidth: text.attribute(.rfcContentWidth, at: effective.location, effectiveRange: nil)
        as? CGFloat,
      spacingBefore: paragraph?.paragraphSpacingBefore ?? 0,
      spacingAfter: paragraph?.paragraphSpacing ?? 0
    )
  }

  /// Whether the character at `location` belongs to a block drawn as a card. A
  /// quote is decorated too, but draws a rule beside its text, which no card's cap
  /// can stack on.
  static func drawsCard(in text: NSAttributedString, at location: Int) -> Bool {
    let decoration = text.decoration(at: location)
    return decoration != nil && decoration != .blockQuote
  }

  /// `run` cut down to the one verbatim block at `location`, when there is one.
  ///
  /// Two verbatim blocks in a row carry the same `.artwork` value with nothing
  /// between them, so the decoration's run alone reads them as one card, and a
  /// source block's language label lands mid-card. What tells them apart is the
  /// block's own `VerbatimBox`, one instance per block.
  private static func verbatimBlock(
    in text: NSAttributedString, at location: Int, within run: NSRange
  ) -> NSRange {
    guard text.attribute(.rfcVerbatim, at: location, effectiveRange: nil) is VerbatimBox,
      let block = text.extent(ofBox: .rfcVerbatim, at: location)
    else { return run }
    return NSIntersectionRange(run, block)
  }

  /// One probe over a whole fragment, so a chipless paragraph — which is most of
  /// them — skips the per-line walk in `chipRects` entirely.
  private static func hasChips(in text: NSAttributedString, fragment: NSRange) -> Bool {
    guard fragment.location >= 0, fragment.length > 0, NSMaxRange(fragment) <= text.length else {
      return false
    }
    var found = false
    text.enumerateAttribute(.rfcChip, in: fragment) { value, _, stop in
      if value != nil {
        found = true
        stop.pointee = true
      }
    }
    return found
  }

  /// The rects to fill for every chip in a fragment, in the coordinate space whose
  /// origin is `origin`.
  ///
  /// A chip that wraps is still one contiguous `.rfcChip` run laid out across
  /// several `NSTextLineFragment`s inside a single layout fragment (TextKit 2 lays
  /// out a whole paragraph as one fragment holding many line fragments) — so the
  /// line holding the run's first character rounds only its left corners, the line
  /// holding its last character rounds only its right corners, and a middle line (a
  /// chip wrapping across three or more lines) rounds neither.
  public static func chipRects(
    in text: NSAttributedString,
    lines: [NSTextLineFragment],
    fragment: NSRange,
    origin: CGPoint
  ) -> [ChipRect] {
    let fragmentStart = fragment.location
    guard fragmentStart >= 0, hasChips(in: text, fragment: fragment) else { return [] }
    var result: [ChipRect] = []
    for line in lines {
      let lineStart = fragmentStart + line.characterRange.location
      let lineRange = NSRange(location: lineStart, length: line.characterRange.length)
      guard lineRange.location >= 0, NSMaxRange(lineRange) <= text.length else { continue }

      text.enumerateAttribute(.rfcChip, in: lineRange) { value, piece, _ in
        guard value != nil else { return }

        // The piece `enumerateAttribute` hands back is already clipped to
        // this line; the run's own full extent — which may start before or
        // end after this line — decides which ends round. The longest range,
        // not the storage run: the chip's symbol is an attachment, a storage
        // run of its own, and ending the chip there rounded the trailing end
        // of every wrapped chip's first line (#122).
        var runRange = NSRange(location: 0, length: 0)
        _ = text.attribute(
          .rfcChip, at: piece.location, longestEffectiveRange: &runRange,
          in: NSRange(location: 0, length: text.length))
        let roundsLeading = runRange.location >= lineRange.location
        let roundsTrailing = NSMaxRange(runRange) <= NSMaxRange(lineRange)

        let startX = line.locationForCharacter(
          at: elementIndex(of: piece.location, fragmentStart: fragmentStart)
        ).x
        // The chip's last character is kerned by the builder to make room for
        // the tint (`reserveChipPadding`), and the next character starts after
        // that room; the glyphs end before it.
        let trailingKern =
          roundsTrailing
          ? text.attribute(.kern, at: NSMaxRange(runRange) - 1, effectiveRange: nil) as? CGFloat
            ?? 0
          : 0
        let endX =
          line.locationForCharacter(
            at: elementIndex(of: NSMaxRange(piece), fragmentStart: fragmentStart)
          ).x - trailingKern
        let padLeft = roundsLeading ? chipPadding : 0
        let padRight = roundsTrailing ? chipPadding : 0

        // Centered on the glyphs, not the line: `lineHeightMultiple` adds all of
        // a line's extra leading above its ascender, so a tint filling the line
        // box had room above the label and none below its descenders.
        let font =
          text.attribute(.font, at: piece.location, effectiveRange: nil) as? PlatformFont
          ?? PlatformFont.systemFont(ofSize: PlatformFont.systemFontSize)
        let baseline = line.typographicBounds.minY + line.glyphOrigin.y
        let top = baseline - font.ascender - chipVerticalPadding
        let bottom = baseline - font.descender + chipVerticalPadding

        result.append(
          ChipRect(
            rect: CGRect(
              x: origin.x + line.typographicBounds.minX + startX - padLeft,
              y: origin.y + top,
              width: endX - startX + padLeft + padRight,
              height: bottom - top
            ),
            roundsLeading: roundsLeading,
            roundsTrailing: roundsTrailing,
            isInformative: text.attribute(.rfcInformative, at: piece.location, effectiveRange: nil)
              != nil
          ))
      }
    }
    return result
  }

  /// The indent a decoration's band starts at: the *shallowest* of any paragraph in
  /// the run.
  ///
  /// Taking each fragment's own indent instead leaves the band ragged down its left
  /// edge wherever a block mixes indents — an authors' block alternating affiliation
  /// and address lines, a stacked table's label and value. One band per run means
  /// one left edge per run, and the shallowest is the only one that encloses every
  /// line rather than cutting into some of them.
  public static func indent(in text: NSAttributedString, over range: NSRange) -> CGFloat {
    let clamped = NSIntersectionRange(range, NSRange(location: 0, length: text.length))
    guard clamped.length > 0 else { return 0 }
    var smallest = CGFloat.greatestFiniteMagnitude
    text.enumerateAttribute(.paragraphStyle, in: clamped) { value, _, _ in
      smallest = min(smallest, (value as? NSParagraphStyle)?.headIndent ?? 0)
    }
    return smallest == .greatestFiniteMagnitude ? 0 : smallest
  }

  /// Where one fragment sits in the column: everything a decoration needs to know
  /// about geometry, so the rect-building below takes one value rather than a
  /// fistful of loose measurements.
  public struct Placement: Equatable, Sendable {
    /// Where the fragment is being drawn.
    public let origin: CGPoint
    /// The fragment's own frame in the text container.
    public let frame: CGRect
    /// The width of the text column.
    public let containerWidth: CGFloat
    /// How far the decorated text is inset from the column's left edge.
    public let indent: CGFloat
    /// How wide the decorated content is set, where the band hugs it rather than
    /// spanning the column (`DecorationSpan.contentWidth`).
    public let contentWidth: CGFloat?
    /// The paragraph spacing the frame includes above and below the text
    /// (`DecorationSpan.spacingBefore`, `spacingAfter`).
    public let spacingBefore: CGFloat
    public let spacingAfter: CGFloat

    public init(
      origin: CGPoint, frame: CGRect, containerWidth: CGFloat, indent: CGFloat,
      contentWidth: CGFloat? = nil, spacingBefore: CGFloat = 0, spacingAfter: CGFloat = 0
    ) {
      self.origin = origin
      self.frame = frame
      self.containerWidth = containerWidth
      self.indent = indent
      self.contentWidth = contentWidth
      self.spacingBefore = spacingBefore
      self.spacingAfter = spacingAfter
    }

    /// The decorated text's own left edge, in the drawing space. The fragment's
    /// `minX` is what maps the container's origin into that space, so this is
    /// stable across fragments of differing width.
    public var columnLeft: CGFloat { origin.x - frame.minX + indent }

    /// The band a decoration fills.
    ///
    /// Measured across the *column*, not the fragment. Artwork is appended with
    /// embedded newlines and does not wrap, so TextKit 2 lays out one paragraph —
    /// and therefore one fragment — per line, each only as wide as its own text.
    /// A card measured from `frame.width` steps in and out line by line, and a
    /// block of artwork reads as a staircase of rounded rectangles instead of one
    /// card. The same applies to a stacked table's cells and the authors' block.
    ///
    /// `capTop`/`capBottom` add the run's outer padding only on its own first and
    /// last fragment, so consecutive fragments tile into one band rather than
    /// overlapping — which, with a translucent fill, would darken every seam.
    ///
    /// Where the content's own width is known, the band ends a padding past it
    /// instead, never past the column: a narrow diagram on a wide window sat at the
    /// left of a card twice its width. Every line of a block reports the same width,
    /// so the right edge is as straight as the left.
    ///
    /// A capped end is measured from the text, not the frame, which holds the
    /// paragraph's spacing: a card that filled it sat directly on the paragraph
    /// before and after it. The spacing is the margin around the card instead.
    /// A line's leading is set above its glyphs, so a card padded alike at both
    /// ends looked padded at the top alone: where the spacing after has room for
    /// it, the bottom reaches a whole padding further past the text than the top.
    public func decorationRect(padding: CGFloat, capTop: Bool, capBottom: Bool) -> CGRect {
      let top = capTop ? padding / 2 - spacingBefore : 0
      let bottom = capBottom ? padding / 2 + min(spacingAfter, padding) - spacingAfter : 0
      return CGRect(
        x: columnLeft - padding,
        y: origin.y - top,
        width: min(max(0, containerWidth - indent), contentWidth ?? .infinity) + padding * 2,
        height: frame.height + top + bottom
      )
    }

    /// The card `span`'s fragment fills: `decorationRect`, capped at the run's own
    /// first and last fragment — except an end where the run meets another card.
    ///
    /// Two blocks with nothing between them — one verbatim block after another,
    /// a table directly followed by artwork — lay out with touching frames, so
    /// the upper card's bottom cap and the lower card's top cap would cover the
    /// same `padding`-high strip, and two translucent fills stack there with
    /// their rounded corners cutting in. At such a cut neither card caps; each
    /// gives up a quarter of the padding of its own frame instead, so the two meet
    /// with a gap of half the padding and no text moves.
    public func cardRect(padding: CGFloat, span: DecorationSpan) -> CGRect {
      let cutAbove = span.isFirst && span.meetsCardAbove
      let cutBelow = span.isLast && span.meetsCardBelow
      let rect = decorationRect(
        padding: padding, capTop: span.isFirst && !cutAbove, capBottom: span.isLast && !cutBelow)
      let top = cutAbove ? padding / 4 : 0
      let bottom = cutBelow ? padding / 4 : 0
      return CGRect(
        x: rect.minX, y: rect.minY + top, width: rect.width,
        height: max(0, rect.height - top - bottom))
    }

    /// The rule a block quote hangs beside its text.
    ///
    /// Left of the decorated text's own edge, not the fragment's: a short line
    /// would otherwise pull the rule inwards and it would zigzag down the quote.
    /// It spans this fragment's height alone, so consecutive fragments' rules
    /// meet end to end.
    public func ruleRect(padding: CGFloat, width: CGFloat) -> CGRect {
      CGRect(x: columnLeft - padding - width, y: origin.y, width: width, height: frame.height)
    }

    /// `rect`, in the drawing space, with the edges it shares with a neighboring
    /// fragment moved onto the device pixel grid: its top when `top`, its bottom
    /// when `bottom`.
    ///
    /// `decorationRect` tiles consecutive fragments exactly in points, but a line
    /// advance like 29.25pt puts the shared edge inside a device pixel. Each
    /// fragment then fills that pixel with partial coverage, and two translucent
    /// partial fills compose to less than one whole one — a darker 1px band at
    /// every line of a card (#31). On the grid, each fragment owns whole pixels
    /// and the band is one flat surface.
    ///
    /// The edge is rounded in *device* space, through the whole of `toDevice` —
    /// its translation as well as its scale — and mapped back. Where a device
    /// pixel falls in the drawing space depends on everything between the
    /// document and the backing store: the scroll offset, the header's top inset,
    /// the text view's own origin, a fragment view's position. Rounding against
    /// the scale alone assumed all of those were whole pixels; the translation
    /// carries them, so nothing has to be. Two neighbors drawn into one context
    /// map the same edge to the same device coordinate whatever local space each
    /// is drawn in, so they round it to the same pixel; drawn into two layers,
    /// each rounds to the pixels of the layer its fill is rasterized into. Rounding
    /// is `floor(y + 0.5)`, so a tie goes one way from both sides.
    ///
    /// `toDevice` is the context's `userSpaceToDeviceSpaceTransform`, not its
    /// `ctm`: inside `NSTextLayoutFragment.draw` the `ctm` is the identity and the
    /// backing scale lives only in the base transform — measured, `(2, -2)`
    /// against an identity `ctm` — so rounding against `ctm` rounds to whole
    /// points and makes overlaps. A transform that rotates leaves the rect alone:
    /// a horizontal edge is then not on one device row.
    ///
    /// The run's own first and last edges are left alone: they are rounded and
    /// antialiased, and shared with nothing.
    public func snappingJoins(
      of rect: CGRect, top: Bool, bottom: Bool, toDevice transform: CGAffineTransform
    ) -> CGRect {
      guard transform.b == 0, transform.d != 0 else { return rect }
      func snap(_ y: CGFloat) -> CGFloat {
        ((y * transform.d + transform.ty + 0.5).rounded(.down) - transform.ty) / transform.d
      }
      let minY = top ? snap(rect.minY) : rect.minY
      let maxY = bottom ? snap(rect.maxY) : rect.maxY
      return CGRect(x: rect.minX, y: minY, width: rect.width, height: maxY - minY)
    }
  }

  /// The document-relative character offset under `pointInFragment`, or nil when
  /// the point falls outside every line. The inverse of `chipRects`' arithmetic,
  /// and the reader's hit test.
  public static func characterOffset(
    in lines: [NSTextLineFragment],
    fragmentStart: Int,
    at pointInFragment: CGPoint
  ) -> Int? {
    for line in lines
    where line.typographicBounds.minY <= pointInFragment.y
      && pointInFragment.y < line.typographicBounds.maxY
    {
      let pointInLine = CGPoint(
        x: pointInFragment.x - line.typographicBounds.minX,
        y: pointInFragment.y - line.typographicBounds.minY
      )
      // Beside the line's text — the gutter, or the space after a short line —
      // is over no character. `characterIndex(for:)` would snap it to the
      // nearest one, or answer `NSNotFound` past a single line's end, which
      // overflowed when added to a nonzero fragment start.
      guard pointInLine.x >= 0, pointInLine.x < line.typographicBounds.width else { return nil }
      // `characterIndex(for:)` already returns an index relative to the whole
      // paragraph (`line.attributedString`), the same element-relative
      // convention `elementIndex(of:fragmentStart:)` documents — so it already
      // includes `line.characterRange.location`, and adding that again
      // double-counts.
      let index = line.characterIndex(for: pointInLine)
      guard index != NSNotFound else { return nil }
      return fragmentStart + index
    }
    return nil
  }

  /// A document-relative offset as the index `NSTextLineFragment` wants.
  ///
  /// `locationForCharacter(at:)` and `characterIndex(for:)` are both indexed
  /// against `line.attributedString` — the whole paragraph the *fragment* lays
  /// out, not the line — so the base is the fragment's start, never the line's.
  /// The two coincide only on a fragment's first line, which is why every
  /// hand-trace and every single-line fixture looked right while this was wrong.
  private static func elementIndex(of documentOffset: Int, fragmentStart: Int) -> Int {
    documentOffset - fragmentStart
  }
}
