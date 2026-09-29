import Foundation
import RFCKit

#if canImport(UIKit)
  import UIKit
#else
  import AppKit
#endif

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

    // A chip's symbol and the joiner behind it are silent: the attachment and an
    // invisible character reached VoiceOver as part of the link's name (#300).
    func readSkippingChipSymbols(_ range: NSRange) {
      var start = range.location
      for silent in chipSymbols(in: range, of: text) {
        read(NSRange(location: start, length: silent.location - start))
        start = NSMaxRange(silent)
      }
      read(NSRange(location: start, length: NSMaxRange(range) - start))
    }

    text.enumerateAttribute(.rfcVerbatim, in: range) { value, piece, _ in
      guard let box = value as? VerbatimBox, isDiagram(box),
        let diagram = text.extent(ofBox: .rfcVerbatim, at: piece.location)
      else {
        readSkippingChipSymbols(piece)
        return
      }
      if piece.location == diagram.location {
        pieces.append(.label(label))
      }
      // The builder ends every verbatim block with a line break.
      let last = NSMaxRange(diagram) - 1
      if NSLocationInRange(last, piece) {
        read(NSRange(location: last, length: 1))
      }
    }
    return pieces
  }

  /// The symbol and joiner that open each chip in `range`, clipped to it, in order:
  /// `DocumentTextBuilder.chipRun` puts U+FFFC then U+2060 before the chip's name.
  static func chipSymbols(in range: NSRange, of text: NSAttributedString) -> [NSRange] {
    let whole = NSRange(location: 0, length: text.length)
    let characters = text.string as NSString
    var symbols: [NSRange] = []
    text.enumerateAttribute(.rfcChip, in: range) { value, piece, _ in
      guard value != nil else { return }
      var chip = NSRange()
      _ = text.attribute(.rfcChip, at: piece.location, longestEffectiveRange: &chip, in: whole)
      var length = 0
      for (offset, unit) in [(0, 0xFFFC), (1, 0x2060)] {
        let location = chip.location + offset
        guard location < NSMaxRange(chip), characters.character(at: location) == unit else { break }
        length += 1
      }
      let silent = NSIntersectionRange(NSRange(location: chip.location, length: length), piece)
      if silent.length > 0, symbols.last != silent { symbols.append(silent) }
    }
    return symbols
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

  /// A drawing, unless most of its lines are words: then it is a table, whose
  /// borders or underlines pass `drawingShare` but whose rows are data to be heard.
  ///
  /// A line is words when it has a letter and more than half of its characters
  /// that are not white space are letters and digits. The letter keeps a bit
  /// layout's numbered ruler out; "more than half" keeps out a box's middle line,
  /// `| Client | -------> | Server |`, which is exactly half. "Most" is strictly
  /// more than half of the lines that are not blank, because a bit layout
  /// alternates field rows and borders: RFC 793's header has 7 lines of words in
  /// 19, and its option layouts 2 in 4. So a bordered table needs more rows than
  /// borders to be read, which one with a header row and two data rows does not.
  static func looksLikeDrawing(_ text: String) -> Bool {
    var characters = 0
    var drawing = 0
    var lines = 0
    var linesOfWords = 0
    for line in text.split(whereSeparator: \.isNewline) {
      var lineCharacters = 0
      var alphanumerics = 0
      var hasLetter = false
      for scalar in line.unicodeScalars where !scalar.properties.isWhitespace {
        lineCharacters += 1
        if isDrawing(scalar) {
          drawing += 1
        }
        if scalar.properties.isAlphabetic {
          hasLetter = true
          alphanumerics += 1
        } else if scalar.properties.numericType != nil {
          alphanumerics += 1
        }
      }
      guard lineCharacters > 0 else { continue }
      characters += lineCharacters
      lines += 1
      if hasLetter && 2 * alphanumerics > lineCharacters {
        linesOfWords += 1
      }
    }
    return characters > 0
      && Double(drawing) >= drawingShare * Double(characters)
      && 2 * linesOfWords <= lines
  }

  /// The ASCII an RFC draws with, and Unicode's box drawing and block elements.
  private static let asciiDrawing = Set("+-|/\\_=<>^*~".unicodeScalars)

  private static func isDrawing(_ scalar: Unicode.Scalar) -> Bool {
    asciiDrawing.contains(scalar) || (0x2500...0x259F).contains(scalar.value)
  }

  /// What VoiceOver says in place of a diagram. Not `Preformatted.name`, which is
  /// RFCXML's file name to extract the artwork to, not a title; and not the
  /// figure's caption, which in a document from XML is set as text right after
  /// the diagram and would be read twice. A legacy document keeps its
  /// "Figure 3: …" line inside the artwork, so there it goes unsaid with the
  /// drawing (#361 splits it out into a real title).
  public static let label = "Diagram"

  /// What the Diagrams rotor lists the diagram at `location` as: its figure's
  /// caption, which the rotor never reads through, so it is not said twice there,
  /// and which is what tells one figure from the next; `label` without one.
  public static func rotorLabel(at location: Int, in text: NSAttributedString) -> String {
    text.attribute(.rfcCaption, at: location, effectiveRange: nil) as? String ?? label
  }
}

// MARK: - Rotors

extension AccessibleReading {
  /// One rotor stop: the run's extent, and — for diagrams only — what VoiceOver
  /// says about it. Headings and links keep `label` nil and let VoiceOver read the
  /// text at `range`, which already says the right thing.
  public struct RotorItem: Equatable, Sendable {
    public let range: NSRange
    public let label: String?

    public init(range: NSRange, label: String?) {
      self.range = range
      self.label = label
    }
  }

  /// The stops of the three rotors that restore jump navigation to the one text
  /// view: headings, links and diagrams, read straight off the attributes the
  /// builder tags runs with. Made once per installed document, so a rotor search
  /// is a lookup in a small array rather than a walk of the whole text.
  ///
  /// `.rfcAnchor` is set on heading runs only — not on every anchor `AnchorIndex`
  /// carries, which also covers figures, tables and reference rows — so it is both
  /// the right filter and the only source of a text *range* per heading.
  public struct Rotors: Equatable, Sendable {
    public var headings: [RotorItem]
    public var links: [RotorItem]
    /// Only what VoiceOver says as a diagram (`isDiagram`): code and artwork that
    /// is not a drawing are read as text. One stop per block: the enumeration's
    /// runs are the longest ranges of one `VerbatimBox`, which compares by
    /// identity, so a block of many storage runs is one run here (`BoxExtentTests`).
    public var diagrams: [RotorItem]

    public static let empty = Rotors(headings: [], links: [], diagrams: [])

    public init(headings: [RotorItem], links: [RotorItem], diagrams: [RotorItem]) {
      self.headings = headings
      self.links = links
      self.diagrams = diagrams
    }

    public init(_ text: NSAttributedString) {
      let whole = NSRange(location: 0, length: text.length)
      func items(carrying key: NSAttributedString.Key) -> [RotorItem] {
        var items: [RotorItem] = []
        text.enumerateAttribute(key, in: whole) { value, range, _ in
          guard value != nil else { return }
          items.append(RotorItem(range: range, label: nil))
        }
        return items
      }
      var diagrams: [RotorItem] = []
      text.enumerateAttribute(.rfcVerbatim, in: whole) { value, range, _ in
        guard let box = value as? VerbatimBox, isDiagram(box) else { return }
        diagrams.append(RotorItem(range: range, label: rotorLabel(at: range.location, in: text)))
      }
      self.init(
        headings: items(carrying: .rfcAnchor), links: items(carrying: .link), diagrams: diagrams)
    }
  }

  /// The stop strictly after (or before) `location`, or the first (or last) when
  /// there is no current stop — both platforms' contract for a search that starts
  /// from nothing. Nil past either end, which VoiceOver marks with a boundary
  /// sound rather than repeating the last stop.
  public static func nextRotorItem(
    in items: [RotorItem], after location: Int?, forward: Bool
  ) -> RotorItem? {
    guard let location, location != NSNotFound else { return forward ? items.first : items.last }
    return forward
      ? items.first { $0.range.location > location }
      : items.last { $0.range.location < location }
  }
}
