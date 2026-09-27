import Foundation
import RFCKit

/// What VoiceOver is given for a range of the reader's text (#12).
///
/// The body is one text view, so a diagram is just characters in it, and VoiceOver
/// read its box drawing out one character at a time. This decides what to say
/// instead: prose, and source code, which reads perfectly well, pass through as they
/// are; a diagram becomes one spoken label.
///
/// The label is said once, where the range reaches the diagram's first character.
/// VoiceOver asks a line at a time, so a diagram's first line announces it and its
/// other lines are silent — the label is not repeated per line, and a range that
/// begins inside a diagram does not announce it again. The diagram's closing line
/// break is kept, so what follows starts a line of its own.
///
/// A pure function of the text and the range, where it can be tested; the text
/// view's accessibility overrides assemble the pieces.
public enum AccessibleReading {
  public enum Piece: Equatable {
    /// Characters to read as they are.
    case text(NSRange)
    /// A diagram, said in place of its characters.
    case label(String)
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
      guard let box = value as? VerbatimBox, box.content.kind == .artwork else {
        read(piece)
        return
      }
      var diagram = NSRange()
      _ = text.attribute(
        .rfcVerbatim, at: piece.location, longestEffectiveRange: &diagram, in: whole)
      if piece.location == diagram.location {
        pieces.append(.label(label(for: box)))
      }
      let last = NSMaxRange(diagram) - 1
      if NSLocationInRange(last, piece), (text.string as NSString).character(at: last) == 0x0A {
        read(NSRange(location: last, length: 1))
      }
    }
    return pieces
  }

  /// Every diagram's whole extent, found independently of `pieces`: consecutive
  /// artwork runs over the same `VerbatimBox` are one diagram.
  static func diagrams(in text: NSAttributedString) -> [NSRange] {
    var diagrams: [NSRange] = []
    var open: ObjectIdentifier?
    text.enumerateAttribute(.rfcVerbatim, in: NSRange(location: 0, length: text.length)) {
      value, range, _ in
      guard let box = value as? VerbatimBox, box.content.kind == .artwork else {
        open = nil
        return
      }
      if ObjectIdentifier(box) == open, let last = diagrams.popLast() {
        diagrams.append(NSUnionRange(last, range))
      } else {
        diagrams.append(range)
      }
      open = ObjectIdentifier(box)
    }
    return diagrams
  }

  /// The name, when the source gives one: it is the one thing about a diagram the
  /// text does not already say. Not the figure's caption, which is set right after
  /// the diagram and would be read twice.
  static func label(for box: VerbatimBox) -> String {
    guard let name = box.content.name, !name.isEmpty else { return "Diagram" }
    return "\(name), diagram"
  }
}
