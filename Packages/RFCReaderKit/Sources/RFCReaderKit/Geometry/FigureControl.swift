import CoreGraphics
import Foundation

/// The button in a rendered block's card that switches it between its figure and
/// its source. A native icon button the coordinator lays over the text view, in a strip the builder reserves above
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

  /// A round glass button, as tall as the strip it sits in.
  public static let width: CGFloat = 22
  public static let height: CGFloat = 22
  /// From the card's top and right edges: half the card's padding, where the
  /// card's own rounding leaves room.
  public static let inset: CGFloat = FragmentGeometry.cardPadding / 2
  /// The spacing a controlled block's first line is set below, which the control
  /// sits in, so showing it moves no text.
  public static let strip: CGFloat = 22

  /// What the button says it does when `shown` is showing, as its tooltip and
  /// to VoiceOver: the context menu's words.
  public static func title(offeredFrom shown: Segment) -> String {
    switch shown {
    case .figure: "Show Source"
    case .source: "Show Rendering"
    }
  }

  /// The SF Symbol of what the button switches to: code, or a grid of fields.
  public static func symbol(offeredFrom shown: Segment) -> String {
    switch shown {
    case .figure: "chevron.left.forwardslash.chevron.right"
    case .source: "square.grid.3x3"
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
