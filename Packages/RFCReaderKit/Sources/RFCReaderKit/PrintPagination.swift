import CoreGraphics
import Foundation

/// Where a laid-out document breaks into pages (#375).
///
/// Pure arithmetic over line positions: no layout manager, no drawing context. The
/// renderer in the app lays the document out, reads every line's vertical extent off
/// its layout fragments, and draws each page as the slice of the document between a
/// page's `top` and `bottom`. Which lines those slices hold is decided here, where it
/// is under test, for the reason `FragmentGeometry` lives in this package.
///
/// Pages break between lines, never through one, so a paragraph may continue onto
/// the next page but no line is cut in half.
public enum PrintPagination {
  /// One line of the laid-out document, in document coordinates, top-down.
  public struct Line: Equatable, Sendable {
    public let minY: CGFloat
    public let maxY: CGFloat
    /// A heading's line: a page never ends on it, because a heading at the foot of
    /// a page with its text on the next says nothing where it stands.
    public let keepsWithNext: Bool

    public init(minY: CGFloat, maxY: CGFloat, keepsWithNext: Bool = false) {
      self.minY = minY
      self.maxY = maxY
      self.keepsWithNext = keepsWithNext
    }
  }

  /// One page: the slice of the document from `top` to `bottom`, which holds every
  /// line that starts at or below `top` and ends at or above `bottom`.
  public struct Page: Equatable, Sendable {
    public let top: CGFloat
    public let bottom: CGFloat

    public var height: CGFloat { bottom - top }
  }

  /// The pages `lines` fill, each at most `pageHeight` tall.
  ///
  /// Lines are taken in order, and a page ends before the first line that would
  /// run past its foot. When the lines before that break keep with what follows —
  /// a heading — the break moves up above them, so the heading opens the next page
  /// instead of closing this one; unless they are all the page holds, which would
  /// leave it empty.
  ///
  /// A line taller than a page — a figure no page can hold — gets a page of its own
  /// and is clipped there, rather than pushing every page after it out of step or
  /// being dropped.
  ///
  /// - Parameter lines: in document order, top-down; nothing is sorted here.
  public static func pages(of lines: [Line], pageHeight: CGFloat) -> [Page] {
    guard let first = lines.first, pageHeight > 0 else { return [] }
    var pages: [Page] = []
    var start = 0
    var index = 1
    var top = first.minY
    while index < lines.count {
      guard lines[index].maxY - top > pageHeight else {
        index += 1
        continue
      }
      var breakAt = index
      while breakAt > start + 1, lines[breakAt - 1].keepsWithNext {
        breakAt -= 1
      }
      // Headings all the way up: moving them would move the whole page.
      if breakAt == start + 1, lines[start].keepsWithNext {
        breakAt = index
      }
      pages.append(Page(top: top, bottom: lines[breakAt - 1].maxY))
      start = breakAt
      top = lines[start].minY
      index = start + 1
    }
    pages.append(Page(top: top, bottom: lines[lines.count - 1].maxY))
    return pages
  }

  /// A laid-out paragraph's vertical extent, in document coordinates: what a
  /// page draws, whole, and clips to itself.
  public struct Span: Equatable, Sendable {
    public let minY: CGFloat
    public let maxY: CGFloat

    public init(minY: CGFloat, maxY: CGFloat) {
      self.minY = minY
      self.maxY = maxY
    }
  }

  /// Which of `spans` reach into `page`, for it to draw: every one that ends
  /// below the page's top and starts above its foot. A paragraph that continues
  /// onto the next page is drawn on both, each clipping it to its own lines.
  ///
  /// - Parameter spans: in document order, top-down, as a layout manager
  ///   enumerates its fragments. Searched by bisection, so a page of a long
  ///   document does not walk every paragraph before it.
  public static func spans(_ spans: [Span], on page: Page) -> Range<Int> {
    let first = spans.partitioningIndex { $0.maxY > page.top }
    let end = spans[first...].partitioningIndex { $0.minY >= page.bottom }
    return first..<end
  }

  /// The page holding `y`, a position in the laid-out document: the last page
  /// whose top is at or above it. What an exported PDF places a destination or a
  /// link on (#376). Nil above the first page, or with no pages.
  public static func page(containing y: CGFloat, in pages: [Page]) -> Int? {
    let after = pages.partitioningIndex { $0.top > y }
    return after > 0 ? after - 1 : nil
  }
}
