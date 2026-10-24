import Foundation

#if canImport(UIKit)
  import UIKit
#else
  import AppKit
#endif

extension FragmentGeometry {
  /// One line's piece of a requirement band (#700), and which of its corners round.
  public struct BandRect: Equatable, Sendable {
    public let rect: CGRect
    public let corners: Corners
  }

  /// Where the requirement bands in `bands` are drawn on the lines of the fragment
  /// spanning `fragment`: behind each band's own text, one rect a line. The rects of
  /// one band are joined into one shape, a line's bottom meeting the next line's
  /// top, which rounds only its outer corners, where the sentence starts and ends; there they are
  /// centered on the glyphs, padded as a chip is, rather than on the line box,
  /// whose leading is all above its text. `bands` are document ranges; a band that
  /// starts before the fragment or ends after it continues square.
  public static func bandRects(
    _ bands: [NSRange],
    in text: NSAttributedString,
    lines: [NSTextLineFragment],
    fragment: NSRange,
    origin: CGPoint
  ) -> [BandRect] {
    guard !bands.isEmpty else { return [] }
    var result: [BandRect] = []
    for line in lines {
      let lineRange = NSRange(
        location: fragment.location + line.characterRange.location,
        length: line.characterRange.length)
      guard NSMaxRange(lineRange) <= text.length else { continue }
      let bounds = line.typographicBounds
      let baseline = bounds.minY + line.glyphOrigin.y
      for band in bands {
        guard let piece = band.intersection(lineRange), piece.length > 0 else { continue }
        let starts = band.location >= lineRange.location
        let ends = NSMaxRange(band) <= NSMaxRange(lineRange)
        let font =
          text.attribute(.font, at: piece.location, effectiveRange: nil) as? PlatformFont
          ?? PlatformFont.systemFont(ofSize: PlatformFont.systemFontSize, weight: .regular)
        let startX = line.locationForCharacter(at: piece.location - fragment.location).x
        let endX = line.locationForCharacter(at: NSMaxRange(piece) - fragment.location).x
        let left = bounds.minX + startX - (starts ? chipPadding : 0)
        let right = bounds.minX + endX + (ends ? chipPadding : 0)
        let top = starts ? baseline - font.ascender - chipVerticalPadding : bounds.minY
        let bottom = ends ? baseline - font.descender + chipVerticalPadding : bounds.maxY
        // Only the shape's outer corners. A first row's bottom-left sits on the row
        // under it, which starts at its line's start, and a last row's top-right
        // under the row over it, which runs to its line's end: rounding either
        // notches the joined shape.
        var corners: Corners = []
        if starts { corners.formUnion(ends ? [.left, .right] : .top) }
        if ends { corners.formUnion(starts ? [.left, .right] : .bottom) }
        result.append(
          BandRect(
            rect: CGRect(
              x: origin.x + left, y: origin.y + top, width: right - left, height: bottom - top),
            corners: corners))
      }
    }
    return result
  }
}

extension FragmentGeometry {
  /// One line's piece of a highlight (#522): a fill shaped as a requirement band is,
  /// or for an underline a rule under the text.
  public struct HighlightRect: Equatable, Sendable {
    public let rect: CGRect
    public let corners: Corners
    public let color: HighlightColor
  }

  /// How thick a highlight's underline is, and how far under the baseline it sits.
  public static let highlightRuleWidth: CGFloat = 2
  public static let highlightRuleOffset: CGFloat = 2

  /// Where the highlights in `marks` are drawn on the lines of the fragment spanning
  /// `fragment`. A fill is a requirement band's shape (`bandRects`): one rect a line,
  /// joined into one shape across the lines of one highlight, with rounded ends. An
  /// underline is a rule under each line's piece of it, from the glyphs' start to
  /// their end, which never reaches past them.
  public static func highlightRects(
    _ marks: [HighlightMark],
    in text: NSAttributedString,
    lines: [NSTextLineFragment],
    fragment: NSRange,
    origin: CGPoint
  ) -> [HighlightRect] {
    var result: [HighlightRect] = []
    for mark in marks {
      guard mark.color.isUnderline else {
        for band in bandRects(
          [mark.range], in: text, lines: lines, fragment: fragment, origin: origin)
        {
          result.append(HighlightRect(rect: band.rect, corners: band.corners, color: mark.color))
        }
        continue
      }
      for line in lines {
        let lineRange = NSRange(
          location: fragment.location + line.characterRange.location,
          length: line.characterRange.length)
        guard NSMaxRange(lineRange) <= text.length,
          let piece = mark.range.intersection(lineRange), piece.length > 0
        else { continue }
        let bounds = line.typographicBounds
        let baseline = bounds.minY + line.glyphOrigin.y
        let startX = line.locationForCharacter(at: piece.location - fragment.location).x
        let endX = line.locationForCharacter(at: NSMaxRange(piece) - fragment.location).x
        let rect = CGRect(
          x: origin.x + bounds.minX + startX, y: origin.y + baseline + highlightRuleOffset,
          width: endX - startX, height: highlightRuleWidth)
        result.append(HighlightRect(rect: rect, corners: [], color: mark.color))
      }
    }
    return result
  }
}
