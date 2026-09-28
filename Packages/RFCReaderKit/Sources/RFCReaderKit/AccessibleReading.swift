import Foundation
import RFCKit

/// What VoiceOver is given for a range of the reader's text (#12).
///
/// The body is one text view, so a diagram is just characters in it, and VoiceOver
/// read its box drawing out one character at a time. This decides what to say
/// instead: prose, source code, and artwork that is not a drawing, all of which read
/// perfectly well, pass through as they are; a diagram becomes one spoken label.
///
/// The label is said once, where the range reaches the diagram's first character.
/// VoiceOver asks a line at a time, so a diagram's first line announces it and its
/// other lines are silent — the label is not repeated per line, and a range that
/// begins inside a diagram does not announce it again. The diagram's closing line
/// break is kept, so what follows starts a line of its own.
///
/// A pure function of the text and the range, where it can be tested; the text
/// view's accessibility overrides call `reading` with their own `super`.
public enum AccessibleReading {
  public enum Piece: Equatable {
    /// Characters to read as they are.
    case text(NSRange)
    /// A diagram, said in place of its characters.
    case label(String)
  }

  /// What an accessor returns for `range`: `text` reads characters as they are,
  /// which is the accessor's `super`, `label` turns a diagram's label into what the
  /// accessor returns, and `join` puts the pieces back together.
  ///
  /// A range that is all text goes to `text` whole, so prose keeps every attribute
  /// AppKit gives VoiceOver, and so does a range with nothing in it, whose answer is
  /// AppKit's to give. Not "a range with no label": a diagram's later lines have
  /// none, and must still be silent rather than read out.
  public static func reading<Reading>(
    _ range: NSRange,
    in text: NSAttributedString,
    text read: (NSRange) -> Reading?,
    label: (String) -> Reading,
    join: ([Reading]) -> Reading
  ) -> Reading? {
    guard NSIntersectionRange(range, NSRange(location: 0, length: text.length)).length > 0
    else { return read(range) }
    let pieces = pieces(of: range, in: text)
    if pieces == [.text(range)] { return read(range) }
    return join(
      pieces.compactMap { piece in
        switch piece {
        case .text(let range): read(range)
        case .label(let spoken): label(spoken)
        }
      })
  }

  public static func pieces(of range: NSRange, in text: NSAttributedString) -> [Piece] {
    let whole = NSRange(location: 0, length: text.length)
    let range = NSIntersectionRange(range, whole)
    guard range.length > 0 else { return [] }

    var pieces: [Piece] = []
    func read(_ range: NSRange) {
      guard range.length > 0 else { return }
      if case .text(let previous) = pieces.last, NSMaxRange(previous) == range.location {
        pieces[pieces.count - 1] = .text(NSUnionRange(previous, range))
      } else {
        pieces.append(.text(range))
      }
    }

    text.enumerateAttribute(.rfcVerbatim, in: range) { value, piece, _ in
      guard let box = value as? VerbatimBox, isDiagram(box) else {
        read(piece)
        return
      }
      var diagram = NSRange()
      _ = text.attribute(
        .rfcVerbatim, at: piece.location, longestEffectiveRange: &diagram, in: whole)
      if piece.location == diagram.location {
        pieces.append(.label(label(for: box)))
      }
      // The builder ends every verbatim block with a line break.
      let last = NSMaxRange(diagram) - 1
      if NSLocationInRange(last, piece) {
        read(NSRange(location: last, length: 1))
      }
    }
    return pieces
  }

  /// Whether a verbatim block is said as a label rather than read: artwork that is
  /// a drawing. Legacy documents set every block that is not prose as artwork —
  /// grammars, message examples, tables — and those read perfectly well as words.
  public static func isDiagram(_ box: VerbatimBox) -> Bool {
    box.content.kind == .artwork && looksLikeDrawing(box.content.text)
  }

  /// A drawing is mostly lines, boxes and arrows: at least this share of the
  /// characters that are not white space are drawing characters. Measured, RFC 793's
  /// header diagram sits at 0.76 and its state diagram at 0.71, RFC 5234's core
  /// rules at 0.07 and RFC 8999's packet notation near 0.
  static let drawingShare = 0.3

  static func looksLikeDrawing(_ text: String) -> Bool {
    var characters = 0
    var drawing = 0
    for scalar in text.unicodeScalars where !scalar.properties.isWhitespace {
      characters += 1
      if isDrawing(scalar) {
        drawing += 1
      }
    }
    return characters > 0 && Double(drawing) >= drawingShare * Double(characters)
  }

  /// The ASCII an RFC draws with, and Unicode's box drawing and block elements.
  private static let asciiDrawing = Set("+-|/\\_=<>^*~".unicodeScalars)

  private static func isDrawing(_ scalar: Unicode.Scalar) -> Bool {
    asciiDrawing.contains(scalar) || (0x2500...0x259F).contains(scalar.value)
  }

  /// The name, when the source gives one: it is the one thing about a diagram the
  /// text does not already say. Not the figure's caption: in a document from XML it
  /// is set as text right after the diagram, and would be read twice. A legacy
  /// document keeps its "Figure 3: …" line inside the artwork, so there it goes
  /// unsaid with the drawing (#361 splits it out into a real title).
  public static func label(for box: VerbatimBox) -> String {
    guard let name = box.content.name, !name.isEmpty else { return "Diagram" }
    return "\(name), diagram"
  }
}
