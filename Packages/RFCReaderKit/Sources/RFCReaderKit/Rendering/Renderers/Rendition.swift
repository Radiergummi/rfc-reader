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

/// A block set as its own text, with places in it that are anchors and runs of it
/// that are links (#185). Nothing visual: find, selection, copy and VoiceOver read
/// the block as they do unlinked. Ranges are UTF-16, relative to the block's text.
public struct LinkedText: Equatable, Sendable {
  /// A place another link can go to, such as a rule's definition.
  public struct Definition: Equatable, Sendable {
    public var range: NSRange
    public var anchor: String
  }

  /// A run that goes somewhere, as a cross reference does.
  public struct Link: Equatable, Sendable {
    public var range: NSRange
    public var target: CrossReference.Target
  }

  public var definitions: [Definition]
  public var links: [Link]

  public init(definitions: [Definition], links: [Link]) {
    self.definitions = definitions
    self.links = links
  }
}

/// What a presentation makes of a block. Styled text and drawings join as cases
/// when a renderer first needs them.
public enum Rendition: Equatable, Sendable {
  case decorated(DecoratedText)
  case linked(LinkedText)
}

/// What a presentation may measure against, and what the document's blocks gave
/// before any of them was set.
public struct RenderContext: Sendable {
  public let style: ReadingStyle
  /// What the measure leaves after the block's indent.
  public let column: CGFloat
  /// The rules the document's grammar blocks define, collected over all of them
  /// (#185).
  public let grammar: DocumentGrammar

  public init(style: ReadingStyle, column: CGFloat, grammar: DocumentGrammar = DocumentGrammar()) {
    self.style = style
    self.column = column
    self.grammar = grammar
  }
}
