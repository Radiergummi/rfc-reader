import CoreGraphics
import Foundation

/// The Figure | Source control in a rendered block's card: which of the block's
/// presentations is showing, and the way to the other. A native segmented control
/// the coordinator lays over the text view, in a strip the builder reserves above
/// the block's first line, so it is nothing in the storage. Which blocks have one,
/// and where it goes, are answered here.
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

  /// A block that has a control: where the block starts, and what its control shows.
  public struct Block: Equatable, Sendable {
    public let location: Int
    public let control: Control
  }

  /// AppKit's mini segmented control, fitted to the two labels.
  public static let width: CGFloat = 91
  public static let height: CGFloat = 16
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

  /// Every block that has a control, in document order.
  public static func blocks(in text: NSAttributedString) -> [Block] {
    var blocks: [Block] = []
    text.enumerateAttribute(
      .rfcVerbatim, in: NSRange(location: 0, length: text.length),
      options: .longestEffectiveRangeNotRequired
    ) { value, range, _ in
      guard value != nil, let control = control(atFragment: range, in: text) else { return }
      blocks.append(Block(location: range.location, control: control))
    }
    return blocks
  }

  /// The block with a control that holds `location`, by ordinal: the one the
  /// pointer is over.
  public static func ordinal(at location: Int, in text: NSAttributedString) -> Int? {
    guard location >= 0, location < text.length,
      text.attribute(.rfcFigureControl, at: location, effectiveRange: nil) != nil
    else { return nil }
    return (text.attribute(.rfcVerbatim, at: location, effectiveRange: nil) as? VerbatimBox)?
      .ordinal
  }

  public static func shown(atFragment fragment: NSRange, in text: NSAttributedString)
    -> Segment?
  {
    control(atFragment: fragment, in: text)?.shown
  }
}
