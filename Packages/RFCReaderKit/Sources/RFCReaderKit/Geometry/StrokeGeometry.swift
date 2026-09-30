import Foundation

#if canImport(UIKit)
  import UIKit
#else
  import AppKit
#endif

/// Where a decorated block's strokes land in a line's fragment: every "where does
/// it go" question the fragment asks before it draws, under test here.
///
/// Every line of a verbatim block is its own paragraph and so its own layout
/// fragment, and each fragment draws the part of each stroke that crosses its line.
/// Vertical strokes meet at the line boxes' shared edges.
public enum StrokeGeometry {
  public struct Segment: Equatable, Sendable {
    public var start: CGPoint
    public var end: CGPoint
    public var style: Stroke.Style

    public init(start: CGPoint, end: CGPoint, style: Stroke.Style) {
      self.start = start
      self.end = end
      self.style = style
    }
  }

  /// The strokes of the block a fragment belongs to, and which of the block's lines
  /// it is: the newlines between the block's start and the fragment's.
  public static func line(of fragment: NSRange, in text: NSAttributedString) -> (
    strokes: [Stroke], line: Int
  )? {
    guard
      let box = text.attribute(.rfcStrokes, at: fragment.location, effectiveRange: nil)
        as? StrokeBox,
      let block = text.extent(ofBox: .rfcStrokes, at: fragment.location)
    else { return nil }
    let before = (text.string as NSString).substring(
      with: NSRange(location: block.location, length: fragment.location - block.location))
    return (box.strokes, before.utf16.reduce(0) { $1 == 10 ? $0 + 1 : $0 })
  }

  /// The segments a line's fragment draws, in the coordinate space whose origin is
  /// `origin`.
  public static func segments(
    _ strokes: [Stroke], line: Int, in lineFragment: NSTextLineFragment, font: PlatformFont,
    origin: CGPoint
  ) -> [Segment] {
    let bounds = lineFragment.typographicBounds
    return segments(
      strokes, line: line,
      in: LineBox(
        top: origin.y + bounds.minY, height: bounds.height,
        columnZero: origin.x + bounds.minX + lineFragment.locationForCharacter(at: 0).x,
        advance: advance(of: font)))
  }

  /// A line's box on the page: from `top`, `height` tall, its column 0 starting at
  /// `columnZero` and each column `advance` wide.
  struct LineBox {
    var top: CGFloat
    var height: CGFloat
    var columnZero: CGFloat
    var advance: CGFloat
  }

  /// How far a vertical stroke reaches past a line's edge into the next line's, in
  /// points. Where two lines' pieces of one stroke meet on a fractional pixel, each
  /// would antialias half of it and the two compose lighter than the stroke: #31's
  /// seam. Overlapping them, in an opaque color, covers that pixel twice instead,
  /// which does not show.
  static let overlap: CGFloat = 0.5

  /// The pure core, over a line's box.
  static func segments(_ strokes: [Stroke], line: Int, in box: LineBox) -> [Segment] {
    let first = 2 * line
    let last = 2 * line + 2
    func xPosition(_ grid: Int) -> CGFloat { box.columnZero + CGFloat(grid) / 2 * box.advance }
    func yPosition(_ grid: Int) -> CGFloat { box.top + CGFloat(grid - first) / 2 * box.height }
    var result: [Segment] = []
    for stroke in strokes {
      if stroke.start.y == stroke.end.y {
        guard stroke.start.y > first, stroke.start.y < last else { continue }
        result.append(
          Segment(
            start: CGPoint(x: xPosition(stroke.start.x), y: yPosition(stroke.start.y)),
            end: CGPoint(x: xPosition(stroke.end.x), y: yPosition(stroke.end.y)),
            style: stroke.style))
      } else {
        let lower = max(stroke.start.y, first)
        let upper = min(stroke.end.y, last)
        guard lower < upper else { continue }
        // Past the line's edge where the stroke runs on into the next line.
        let above = stroke.start.y < first ? overlap : 0
        let below = stroke.end.y > last ? overlap : 0
        result.append(
          Segment(
            start: CGPoint(x: xPosition(stroke.start.x), y: yPosition(lower) - above),
            end: CGPoint(x: xPosition(stroke.start.x), y: yPosition(upper) + below),
            style: stroke.style))
      }
    }
    return result
  }

  /// The rect every segment lies in, or nil for none: what the fragment widens its
  /// rendering surface by.
  public static func bounds(of segments: [Segment]) -> CGRect? {
    segments.reduce(nil) { rect, segment in
      let piece = CGRect(
        x: min(segment.start.x, segment.end.x), y: min(segment.start.y, segment.end.y),
        width: abs(segment.end.x - segment.start.x), height: abs(segment.end.y - segment.start.y))
      return rect?.union(piece) ?? piece
    }
  }

  /// One column of a monospaced font, measured as the builder measures it.
  static func advance(of font: PlatformFont) -> CGFloat {
    DocumentTextBuilder.lineWidth("0", font: font)
  }

}
