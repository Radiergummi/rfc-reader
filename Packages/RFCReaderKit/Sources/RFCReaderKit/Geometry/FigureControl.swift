import CoreGraphics
import Foundation

/// The Figure | Source control in a rendered block's card: which of the block's
/// presentations is showing, and the pointer's way to the other. Drawn by the layout
/// fragment and hit-tested by the coordinator, as a reference chip is, so it is
/// nothing in the storage and never a view. Where it goes and what a point on it
/// means are answered here.
public enum FigureControl {
  public enum Segment: String, Sendable {
    case figure
    case source
  }

  /// What a fragment shows the control for: the block it opens, and which segment
  /// is on.
  public struct Control: Equatable, Sendable {
    public let ordinal: Int
    public let shown: Segment
  }

  public static let height: CGFloat = 18
  public static let segmentWidth: CGFloat = 54
  public static var width: CGFloat { segmentWidth * 2 }
  /// From the card's top and right edges: half the card's padding, where the
  /// card's own rounding leaves room.
  public static let inset: CGFloat = FragmentGeometry.cardPadding / 2
  /// The spacing a controlled block's first line is set below, which the control
  /// sits in, so showing it moves no text.
  public static let strip: CGFloat = 22

  public static func label(of segment: Segment) -> String {
    switch segment {
    case .figure: "Figure"
    case .source: "Source"
    }
  }

  /// The control in `card`, the rect of the card a block's first fragment fills.
  public static func rect(inCard card: CGRect) -> CGRect {
    CGRect(x: card.maxX - inset - width, y: card.minY + inset, width: width, height: height)
  }

  /// Where one segment is drawn within `control`.
  public static func rect(of segment: Segment, in control: CGRect) -> CGRect {
    CGRect(
      x: segment == .figure ? control.minX : control.minX + segmentWidth, y: control.minY,
      width: segmentWidth, height: control.height)
  }

  /// The segment under `point`, or nil off the control.
  public static func segment(at point: CGPoint, in control: CGRect) -> Segment? {
    guard control.contains(point) else { return nil }
    return point.x < control.minX + segmentWidth ? .figure : .source
  }

  /// The control a fragment shows, when the fragment opens a block that has one.
  /// Only the first: the control sits in the strip above the block's first line.
  public static func control(atFragment fragment: NSRange, in text: NSAttributedString)
    -> Control?
  {
    guard fragment.location >= 0, fragment.location < text.length,
      let raw = text.attribute(.rfcFigureControl, at: fragment.location, effectiveRange: nil)
        as? String,
      let shown = Segment(rawValue: raw),
      let box = text.attribute(.rfcVerbatim, at: fragment.location, effectiveRange: nil)
        as? VerbatimBox,
      text.extent(ofBox: .rfcVerbatim, at: fragment.location)?.location == fragment.location
    else { return nil }
    return Control(ordinal: box.ordinal, shown: shown)
  }

  public static func shown(atFragment fragment: NSRange, in text: NSAttributedString)
    -> Segment?
  {
    control(atFragment: fragment, in: text)?.shown
  }
}
