import Foundation
import RFCKit

/// A point on a verbatim block's monospace grid, in half cells, so a stroke can end
/// on a cell's edge or its center. The cell at column `c`, line `l` spans `x` from
/// `2c` to `2c + 2` and `y` from `2l` to `2l + 2`; its center is `(2c + 1, 2l + 1)`.
/// Independent of font and scale: where it lands in points is `StrokeGeometry`'s.
public struct GridPoint: Hashable, Sendable {
  public var x: Int
  public var y: Int

  public init(x: Int, y: Int) {
    self.x = x
    self.y = y
  }
}

/// A straight line drawn over a block's text. Always horizontal or vertical, with
/// `start` above or left of `end`.
public struct Stroke: Hashable, Sendable {
  public enum Style: Hashable, Sendable {
    case solid
    /// A field of no fixed length.
    case dashed
    /// A double rule, `=`.
    case double
  }

  public var start: GridPoint
  public var end: GridPoint
  public var style: Style

  public init(start: GridPoint, end: GridPoint, style: Style) {
    self.start = start
    self.end = end
    self.style = style
  }
}

/// A block set as its own text on its monospace grid, with the characters that
/// draw borders hidden and real strokes drawn in their place. The text is the
/// block's, unchanged, so find, selection, copy and VoiceOver read what they read
/// today. Ranges are UTF-16, relative to the block's text.
public struct DecoratedText: Equatable, Sendable {
  public var hidden: [NSRange]
  public var secondary: [NSRange]
  public var strokes: [Stroke]
  /// What VoiceOver says in place of the block's drawing, from the model it was
  /// drawn from; nil to say it as any other diagram.
  public var spokenLabel: String?

  public init(
    hidden: [NSRange], secondary: [NSRange], strokes: [Stroke], spokenLabel: String? = nil
  ) {
    self.hidden = hidden
    self.secondary = secondary
    self.strokes = strokes
    self.spokenLabel = spokenLabel
  }
}

/// What a presentation makes of a block. Drawings join as a case when a renderer
/// first needs them.
public enum Rendition: Equatable, Sendable {
  case decorated(DecoratedText)
  /// Code highlighted: the block's own text, unchanged, and the tokens a lexer read
  /// in it, colored by the reader's theme. Ranges are UTF-16, relative to the text
  /// lexed.
  case styled([SyntaxToken])
}

/// What a presentation may measure against.
public struct RenderContext: Sendable {
  public let style: ReadingStyle
  /// What the measure leaves after the block's indent.
  public let column: CGFloat

  public init(style: ReadingStyle, column: CGFloat) {
    self.style = style
    self.column = column
  }
}
