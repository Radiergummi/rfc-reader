import Foundation

#if canImport(UIKit)
  import UIKit
#else
  import AppKit
#endif

extension DocumentTextBuilder {
  /// Every line of a decorated block set a whole number of points high, and every
  /// space between its paragraphs a whole number of points, so each fragment of
  /// the block advances by whole device pixels at 2x and 3x alike (#273).
  ///
  /// UITextView draws each layout fragment on the pixel at or above its own top.
  /// A card's fragments that are a fraction of a pixel apart — a verbatim line at
  /// 1.1 times a 16 pt line height advances 17.6 pt — are each moved by a
  /// different fraction, and two halves of a join that tile in points are drawn up
  /// to a pixel apart: a light hairline across the translucent card. Whole-point
  /// advances move every fragment of the run by the same fraction, and
  /// `FragmentGeometry.Placement.snappingJoins` meets them as it does on the Mac.
  ///
  /// The line height is fixed, not left to the line's glyphs: the tallest font in
  /// the paragraph at the paragraph's own multiple, to the nearest whole point, as
  /// both the minimum and the maximum, so a glyph from a fallback font cannot make
  /// one line a fraction taller than the rest. A symbol that hangs below the
  /// descender still makes its line taller, which is why a chip's symbol never
  /// hangs below it (`chipSymbolRun`).
  ///
  /// The spacing after the block's last paragraph is left as it is: it is below
  /// the last fragment's lines, where nothing meets the card.
  ///
  /// Whole points rather than whole pixels of one screen: the build does not know
  /// the screen, and a whole point is a whole pixel at 2x and at 3x alike.
  func setDecoratedLinesOnWholePoints() {
    var runs: [NSRange] = []
    output.enumerateAttribute(
      .rfcDecoration, in: NSRange(location: 0, length: output.length)
    ) { value, range, _ in
      if value != nil { runs.append(range) }
    }
    // The backing store itself: `string` would copy the whole document.
    let text = output.mutableString
    for run in runs {
      var location = run.location
      while location < NSMaxRange(run) {
        let paragraph = text.paragraphRange(for: NSRange(location: location, length: 0))
        setOnWholePoints(paragraph, endsRun: NSMaxRange(paragraph) >= NSMaxRange(run))
        location = NSMaxRange(paragraph)
      }
    }
  }

  private func setOnWholePoints(_ paragraph: NSRange, endsRun: Bool) {
    guard
      let style = output.attribute(.paragraphStyle, at: paragraph.location, effectiveRange: nil)
        as? NSParagraphStyle,
      let rounded = style.mutableCopy() as? NSMutableParagraphStyle
    else { return }
    var natural: CGFloat = 0
    output.enumerateAttribute(.font, in: paragraph) { value, _, _ in
      guard let font = value as? PlatformFont else { return }
      natural = max(natural, font.ascender - font.descender + font.leading)
    }
    if natural > 0 {
      let multiple = style.lineHeightMultiple > 0 ? style.lineHeightMultiple : 1
      let height = (natural * multiple).rounded()
      rounded.minimumLineHeight = height
      rounded.maximumLineHeight = height
    }
    rounded.lineSpacing = style.lineSpacing.rounded()
    if !endsRun {
      rounded.paragraphSpacing = style.paragraphSpacing.rounded()
    }
    rounded.paragraphSpacingBefore = style.paragraphSpacingBefore.rounded()
    // An immutable copy, as `paragraphStyle(…)` makes: see `BuiltDocument`.
    // swiftlint:disable:next force_cast
    let immutable = rounded.copy() as! NSParagraphStyle
    output.addAttribute(.paragraphStyle, value: immutable, range: paragraph)
  }
}
