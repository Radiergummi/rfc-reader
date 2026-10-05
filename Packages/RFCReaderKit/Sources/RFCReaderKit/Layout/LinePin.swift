import CoreGraphics
import Foundation

#if canImport(UIKit)
  import UIKit
#else
  import AppKit
#endif

/// The reader's place: the character that starts the line at the top of the
/// viewport, and how far into that line the viewport's top is, as a share of the
/// line's height. A line, not a paragraph: after a re-wrap the character is still at
/// the top, not the first line of its paragraph.
public struct ReaderAnchor: Sendable, Equatable {
  public let characterOffset: Int
  public let fraction: CGFloat

  public init(characterOffset: Int, fraction: CGFloat = 0) {
    self.characterOffset = characterOffset
    self.fraction = fraction
  }
}

/// An anchor and a y within one paragraph fragment, each from the other.
///
/// A line's span runs from its top to its bottom, except that a fragment's first
/// line starts at the fragment's top, the spacing above it included, which is where
/// a jump to an anchor has always put a paragraph's first character.
/// Both directions measure against the same span, so they are inverses.
public enum LinePin {
  /// The anchor for the viewport's top at `fragmentY`, in the fragment's own
  /// coordinates, and the range of the line it names, document-relative.
  public static func anchor(atFragmentY fragmentY: CGFloat, in fragment: FragmentLines)
    -> (anchor: ReaderAnchor, line: NSRange)
  {
    let lines = fragment.lines
    guard let line = lines.first(where: { fragmentY < $0.typographicBounds.maxY }) ?? lines.last
    else {
      return (
        ReaderAnchor(characterOffset: fragment.start),
        NSRange(location: fragment.start, length: 0)
      )
    }
    let range = fragment.documentRange(of: line)
    let span = span(of: line)
    let share = span.height > 0 ? (fragmentY - span.top) / span.height : 0
    let fraction = min(max(share, 0), maximumFraction)
    return (ReaderAnchor(characterOffset: range.location, fraction: fraction), range)
  }

  /// Where the viewport's top goes, in the fragment's own coordinates, to show
  /// `anchor`: the top of the line holding its character, plus its fraction.
  public static func fragmentY(of anchor: ReaderAnchor, in fragment: FragmentLines) -> CGFloat {
    let index = fragment.elementIndex(of: anchor.characterOffset)
    let lines = fragment.lines
    guard let line = lines.first(where: { index < NSMaxRange($0.characterRange) }) ?? lines.last
    else { return 0 }
    let span = span(of: line)
    return span.top + anchor.fraction * span.height
  }

  /// Short of 1, so a fraction never names the next line's top.
  static let maximumFraction: CGFloat = 0.999

  private static func span(of line: NSTextLineFragment) -> (top: CGFloat, height: CGFloat) {
    let bounds = line.typographicBounds
    let top = line.characterRange.location == 0 ? 0 : bounds.minY
    return (top, bounds.maxY - top)
  }
}
