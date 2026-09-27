/// How RFCXML's `<u>` spells out a non-ASCII character a protocol depends on
/// (RFC 7997; authors.ietf.org, *Non-ASCII characters in RFCXML*).
///
/// The element exists so the character is never left to a font: the vocabulary
/// requires its code point in every rendering, so a reader whose font lacks the
/// glyph, or who cannot tell it from a lookalike, still has the specification.
/// Reading only the element's text drops exactly that (issue #63), so it is spelled
/// out at parse time, like a cross reference, rather than left to the view.
///
/// The literal becomes a `.code` inline, so nothing can link or reflow it. The
/// name, the code point and the ASCII spelling are ordinary text, spelled as the
/// RFC Editor's renderer spells them, so a published plain-text RFC is the
/// reference for what this produces.
enum UnicodeNotation {
  /// `lit-name-num`, the vocabulary's default: `"ש" (HEBREW LETTER SHIN, U+05E9)`.
  static let defaultFormat = "lit-name-num"

  /// `text` spelled out as `format` asks.
  ///
  /// A format is either up to three keywords joined by `-`, where the first stands
  /// alone and the rest follow in parentheses, comma-separated, or a template whose
  /// `{keyword}` placeholders are replaced in place. A keyword the vocabulary does
  /// not define is skipped, and so is `ascii` when the element has no `ascii`
  /// attribute. A format that leaves nothing falls back to the default. An empty
  /// element yields nothing: RFC 8771 has one, for a form feed XML cannot hold,
  /// with the code point typed beside it.
  static func expand(_ text: String, format: String?, ascii: String?) -> [Inline] {
    guard !text.isEmpty else { return [] }
    let format = format.flatMap { $0.isEmpty ? nil : $0 } ?? defaultFormat
    if format.contains("{") {
      return template(format, text: text, ascii: ascii)
    }
    let keywords = format.split(separator: "-").map(String.init)
    let pieces = keywords.compactMap { piece($0, text: text, ascii: ascii) }
    // The default always yields its literal, so this falls back at most once.
    guard let first = pieces.first else {
      return expand(text, format: defaultFormat, ascii: ascii)
    }
    var result = Spelling(first)
    let rest = pieces.dropFirst()
    if !rest.isEmpty {
      result.append(text: " (")
      for (index, piece) in rest.enumerated() {
        if index > 0 { result.append(text: ", ") }
        result.append(piece)
      }
      result.append(text: ")")
    }
    return result.inlines
  }

  /// `{lit} character ({num})`: each placeholder the vocabulary defines is replaced,
  /// and everything else, an unknown placeholder included, is kept as written.
  private static func template(_ format: String, text: String, ascii: String?) -> [Inline] {
    var result = Spelling([])
    var rest = Substring(format)
    while let open = rest.firstIndex(of: "{") {
      result.append(text: String(rest[..<open]))
      guard let close = rest[open...].firstIndex(of: "}") else {
        rest = rest[open...]
        break
      }
      let keyword = String(rest[rest.index(after: open)..<close])
      if let spelled = piece(keyword, text: text, ascii: ascii) {
        result.append(spelled)
      } else {
        result.append(text: String(rest[open...close]))
      }
      rest = rest[rest.index(after: close)...]
    }
    result.append(text: String(rest))
    return result.inlines
  }

  private static func piece(_ keyword: String, text: String, ascii: String?) -> [Inline]? {
    switch keyword {
    case "lit": [.text("\""), .code(text), .text("\"")]
    case "char": [.code(text)]
    case "name": [.text(text.unicodeScalars.map(name).joined(separator: ", "))]
    case "num": [.text(text.unicodeScalars.map(codePoint).joined(separator: " "))]
    case "ascii": ascii.flatMap { $0.isEmpty ? nil : [Inline.text("\"\($0)\"")] }
    default: nil
    }
  }

  /// The character's Unicode name, as the standard library knows it; a scalar
  /// with none (a control character, an unassigned code point) is named by its
  /// code point rather than left out. Not by its alias (`DELETE` for U+007F):
  /// the RFC Editor's renderer does not use aliases either.
  static func name(_ scalar: Unicode.Scalar) -> String {
    scalar.properties.name ?? codePoint(scalar)
  }

  /// `U+05E9`: at least four hex digits, upper case, as the Unicode Standard
  /// writes a code point.
  static func codePoint(_ scalar: Unicode.Scalar) -> String {
    let hex = String(scalar.value, radix: 16, uppercase: true)
    return "U+" + String(repeating: "0", count: max(0, 4 - hex.count)) + hex
  }

  /// Inlines built piece by piece, with adjacent text merged so that a spelling
  /// reads as few runs as it has.
  private struct Spelling {
    var inlines: [Inline]

    init(_ inlines: [Inline]) {
      self.inlines = []
      append(inlines)
    }

    mutating func append(_ more: [Inline]) {
      for inline in more {
        if case .text(let text) = inline {
          append(text: text)
        } else {
          inlines.append(inline)
        }
      }
    }

    mutating func append(text: String) {
      guard !text.isEmpty else { return }
      if case .text(let previous) = inlines.last {
        inlines[inlines.count - 1] = .text(previous + text)
      } else {
        inlines.append(.text(text))
      }
    }
  }
}
