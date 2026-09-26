import Foundation

/// An abbreviation the document expands itself, so a reader can be shown the
/// expansion wherever the abbreviation is used (issue #67).
public struct Abbreviation: Sendable, Hashable {
  /// As written between the parentheses: `TLS`, `IPv6`, `TCs`.
  public var short: String
  /// The author's own words for it, as first written: `Transport Layer Security`.
  public var expansion: String
  /// The section the expansion is in, for a reader who wants its context.
  public var sectionAnchor: String?

  public init(short: String, expansion: String, sectionAnchor: String? = nil) {
    self.short = short
    self.expansion = expansion
    self.sectionAnchor = sectionAnchor
  }
}

/// Collects the abbreviations a document expands, at parse time, the way cross
/// references are resolved: from the document's own text, so the expansion is
/// the author's and correct for this document.
///
/// RFC style expands an abbreviation at its first use, `Transport Layer Security
/// (TLS)`, and some documents also keep a glossary, `TLS: Transport Layer
/// Security`. Both are read. The first expansion of an abbreviation wins.
///
/// A wrong expansion shown confidently is worse than none, so this finds the long
/// form with Schwartz and Hearst's algorithm (*A simple algorithm for identifying
/// abbreviation definitions in biomedical text*, 2003), which is built for
/// precision: every letter and digit of the short form has to be matched, in
/// order, right to left, against the words before the parenthesis, and its first
/// one has to start a word. When they cannot all be matched, there is no
/// expansion. `480p (EDTV)` in a table cell stays unexpanded; `Transport Layer
/// Security (TLS)` and `textual conventions (TCs)` both expand.
enum Abbreviations {
  static func defined(in document: RFCDocument) -> [String: Abbreviation] {
    var found: [String: Abbreviation] = [:]
    func record(_ pairs: [(short: String, long: String)], in anchor: String?) {
      for pair in pairs where found[pair.short] == nil {
        found[pair.short] = Abbreviation(
          short: pair.short, expansion: pair.long, sectionAnchor: anchor)
      }
    }
    visit(document.header.abstract) { record($0, in: nil) }
    for section in document.allSections {
      visit(section.blocks) { record($0, in: section.anchor) }
    }
    return found
  }

  /// Every block that holds prose, in document order. Artwork and source code are
  /// set as the author typed them rather than written as prose, and bibliography
  /// entries are other documents' words.
  private static func visit(
    _ blocks: [Block], _ found: ([(short: String, long: String)]) -> Void
  ) {
    for block in blocks {
      switch block {
      case .paragraph(let paragraph):
        found(expansions(in: paragraph.inlines.plainText))
      case .list(let list):
        for item in list.items { visit(item.blocks, found) }
      case .definitionList(let items):
        for item in items {
          let term = item.term.plainText
          found(expansions(in: term))
          if let pair = glossaryEntry(term: term, definition: item.definition) {
            found([pair])
          }
          visit(item.definition, found)
        }
      case .figure(let figure):
        visit(figure.blocks, found)
      case .table(let table):
        for cell in (table.header + table.rows).joined() {
          found(expansions(in: cell.plainText))
        }
      case .blockQuote(let inner), .aside(let inner):
        visit(inner, found)
      case .preformatted, .references:
        break
      }
    }
  }

  /// `Words (ABBR)` pairs in one run of prose, in order.
  static func expansions(in text: String) -> [(short: String, long: String)] {
    let characters = Array(text)
    var result: [(short: String, long: String)] = []
    var index = 0
    while let open = characters[index...].firstIndex(of: "(") {
      index = open + 1
      guard
        let close = characters[index...].firstIndex(where: { $0 == ")" || $0 == "(" }),
        characters[close] == ")"
      else { continue }
      let short = String(characters[index..<close])
      index = close + 1
      // `key(s)` and `f(x)` are not a definition: one is set off by a space.
      guard open > 0, characters[open - 1].isWhitespace, isShortForm(short) else { continue }
      let candidate = candidateLongForm(before: characters[..<open], short: short)
      if let long = longForm(of: short, in: candidate) {
        result.append((short, long))
      }
    }
    return result
  }

  /// `TLS: Transport Layer Security, as defined in [RFC8446].`: a definition-list
  /// term that is an abbreviation, whose definition opens with its expansion. Here
  /// the whole opening phrase has to be the long form, or the definition is prose
  /// about the term rather than its expansion, as in `RTT: The round-trip time`.
  static func glossaryEntry(term: String, definition: [Block]) -> (short: String, long: String)? {
    var short = term.trimmingCharacters(in: .whitespacesAndNewlines)
    if short.hasSuffix(":") { short.removeLast() }
    guard isShortForm(short), case .paragraph(let first)? = definition.first else { return nil }
    let text = first.inlines.plainText.trimmingCharacters(in: .whitespacesAndNewlines)
    let phrase = String(text.prefix { !".;,([".contains($0) }).trimmingCharacters(
      in: .whitespacesAndNewlines)
    guard let long = longForm(of: short, in: phrase), long == phrase else { return nil }
    return (short, long)
  }

  /// Two to ten characters, with no spaces, starting with a letter or digit, and
  /// holding at least two capitals, which is what separates `TLS`, `IPv6` and
  /// `TCs` from `s`, `i`, `Ed.` and `see below`.
  static func isShortForm(_ text: String) -> Bool {
    guard (2...10).contains(text.count), let first = text.first,
      first.isLetter || first.isNumber
    else { return false }
    guard text.allSatisfy({ $0.isLetter || $0.isNumber || "-/&".contains($0) }) else {
      return false
    }
    return text.filter(\.isUppercase).count >= 2
  }

  /// The words before the parenthesis that could be its long form: back to the
  /// last sentence or clause boundary, and no more than `min(n + 5, 2n)` words for
  /// an `n`-character short form, the bound Schwartz and Hearst use.
  private static func candidateLongForm(before text: ArraySlice<Character>, short: String)
    -> String
  {
    var start = text.startIndex
    if let boundary = text.lastIndex(where: { ".;:!?()[]\"".contains($0) }) {
      start = boundary + 1
    }
    let words = String(text[start...]).split(whereSeparator: \.isWhitespace)
    let limit = min(short.count + 5, short.count * 2)
    return words.suffix(limit).joined(separator: " ")
  }

  /// Schwartz and Hearst's match: each letter and digit of `short`, right to left,
  /// against `long`, right to left, case-insensitively; the first has to start a
  /// word. The long form runs from that word to the end.
  static func longForm(of short: String, in long: String) -> String? {
    let shortCharacters = Array(short).map(folded)
    let longCharacters = Array(long).map(folded)
    var shortIndex = shortCharacters.count - 1
    var longIndex = longCharacters.count - 1
    while shortIndex >= 0 {
      let current = shortCharacters[shortIndex]
      guard current.isLetter || current.isNumber else {
        shortIndex -= 1
        continue
      }
      while longIndex >= 0 {
        let matches = longCharacters[longIndex] == current
        let startsWord =
          longIndex == 0
          || !(longCharacters[longIndex - 1].isLetter || longCharacters[longIndex - 1].isNumber)
        if matches, shortIndex > 0 || startsWord { break }
        longIndex -= 1
      }
      guard longIndex >= 0 else { return nil }
      longIndex -= 1
      shortIndex -= 1
    }
    let result = String(Array(long)[(longIndex + 1)...]).trimmingCharacters(
      in: .whitespacesAndNewlines)
    guard result.count > short.count else { return nil }
    return result
  }

  private static func folded(_ character: Character) -> Character {
    let lowered = character.lowercased()
    return lowered.count == 1 ? Character(lowered) : character
  }
}
