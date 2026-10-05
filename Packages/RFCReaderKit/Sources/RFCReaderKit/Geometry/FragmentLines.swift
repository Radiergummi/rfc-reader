import Foundation

#if canImport(UIKit)
  import UIKit
#else
  import AppKit
#endif

/// A layout fragment as the geometry reads it: the characters it lays out, in the
/// document, and the lines it lays them out in.
///
/// One value for what the fragment geometry used to take as a range here, a start
/// offset there and the lines beside either, so the one index convention that is easy
/// to get wrong lives in one place: an `NSTextLineFragment`'s character indices count
/// from the start of the whole paragraph the *fragment* lays out, not from the line's.
/// The reader's two hardest bugs were an index taken relative to the line.
public struct FragmentLines {
  /// The fragment's characters, document-relative.
  public let range: NSRange
  public let lines: [NSTextLineFragment]

  public init(range: NSRange, lines: [NSTextLineFragment]) {
    self.range = range
    self.lines = lines
  }

  /// `fragment`'s characters and lines in `layout`; nil where its range has no offsets
  /// there.
  public init?(_ fragment: NSTextLayoutFragment, in layout: NSTextLayoutManager) {
    guard let range = layout.range(of: fragment.rangeInElement) else { return nil }
    self.init(range: range, lines: fragment.textLineFragments)
  }

  /// Where the fragment starts in the document.
  public var start: Int { range.location }

  /// A document-relative offset as the index `NSTextLineFragment` wants.
  ///
  /// `locationForCharacter(at:)` and `characterIndex(for:)` are both indexed against
  /// `line.attributedString`, the whole paragraph the fragment lays out, not the
  /// line, so the base is the fragment's start, never the line's. The two coincide
  /// only on a fragment's first line, which is why every hand-trace and every
  /// single-line fixture looked right while this was wrong.
  public func elementIndex(of documentOffset: Int) -> Int {
    documentOffset - start
  }

  /// The inverse of `elementIndex(of:)`.
  public func documentOffset(ofElementIndex index: Int) -> Int {
    start + index
  }

  /// `line`'s characters, document-relative.
  public func documentRange(of line: NSTextLineFragment) -> NSRange {
    NSRange(
      location: documentOffset(ofElementIndex: line.characterRange.location),
      length: line.characterRange.length)
  }
}
