import Foundation

/// An abbreviation the document expands itself, so a reader can be shown the
/// expansion wherever the abbreviation is used (issue #67).
public struct Abbreviation: Sendable, Hashable, Codable {
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
    // A heading's expansion set all in capitals, as legacy headings often are, says
    // nothing of the author's casing, so the next one in mixed case replaces it,
    // from the body or a later heading: `RECIPIENT (RCPT)`.
    var inCapitals: Set<String> = []
    func record(
      _ pairs: [(short: String, long: String)], in anchor: String?, isHeading: Bool = false
    ) {
      for pair in pairs {
        let capitals = isAllCapitals(pair.long)
        guard found[pair.short] == nil || (inCapitals.contains(pair.short) && !capitals)
        else { continue }
        found[pair.short] = Abbreviation(
          short: pair.short, expansion: pair.long, sectionAnchor: anchor)
        if isHeading, capitals {
          inCapitals.insert(pair.short)
        } else {
          inCapitals.remove(pair.short)
        }
      }
    }
    visit(document.header.abstract) { record($0, in: nil) }
    for section in document.allSections {
      // The heading first, as the reader meets it, and defined in its own section:
      // `3. Transport Layer Security (TLS)` over a body that uses `TLS` alone (#319).
      record(expansions(in: section.titleText), in: section.anchor, isHeading: true)
      visit(section.blocks) { record($0, in: section.anchor) }
    }
    return found
  }

  /// Every run of prose in `blocks` and the blocks nested in them, in document
  /// order, as `Block.proseRuns` has it, and a glossary entry where a definition
  /// list is one. Artwork and source code are set as the author typed them rather
  /// than written as prose, and a bibliography is other documents' words -- its
  /// annotations included, which `proseRuns` counts as prose for cross references.
  private static func visit(
    _ blocks: [Block], _ found: ([(short: String, long: String)]) -> Void
  ) {
    for block in blocks.flattened {
      if case .references = block { continue }
      for run in block.proseRuns { found(expansions(in: run.plainText)) }
      if case .definitionList(let list) = block {
        for item in list.items {
          if let pair = glossaryEntry(term: item.term.plainText, definition: item.definition) {
            found([pair])
          }
        }
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
    var text = first.inlines.plainText.trimmingCharacters(in: .whitespacesAndNewlines)
    // An explanation after a dash is not part of the expansion: `ASBR: Autonomous
    // System Border Router -- a router used to connect ASes`. Only a dash set off
    // by spaces, or an em dash, is one; `On-Path Attacker` keeps its hyphen.
    for dash in [" -- ", " - ", " \u{2013} "] {
      if let range = text.range(of: dash) { text = String(text[..<range.lowerBound]) }
    }
    var phrase = String(text.prefix { !".;,([:\u{2014}".contains($0) })
    // Citations the definition ends with are the entry's sources, not its words:
    // `PCE: Path Computation Element [RFC4655]`, which reads as `RFC 4655`.
    phrase = phrase.replacing(citationsPattern, with: "")
    phrase = phrase.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let long = longForm(of: short, in: phrase), long == phrase,
      contentWords(in: long) <= letters(in: short) + 2
    else { return nil }
    return (short, long)
  }

  /// Trailing citations: `RFC 4655`, `RFC-4655`, `BCP 38`, `STD 5`, a bare `I-D`,
  /// and a linked one as the parser writes it, `RFC 4655 § 4` with no-break spaces
  /// (`CrossReference.nonBreakingLabel`), which `\s` matches. The phrase has already
  /// ended at the `.` of a section number such as `4.2`.
  private static let citationsPattern = Pattern(
    #/(\s+((RFC|BCP|STD|FYI)[\s-]?\d+(\s*§\s*\d+)?|I-D))+\s*$/#)

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
    let original = Array(long)
    let longCharacters = original.map(folded)
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
        if matches, shortIndex > 0 || startsWord(original, at: longIndex) { break }
        longIndex -= 1
      }
      guard longIndex >= 0 else { return nil }
      longIndex -= 1
      shortIndex -= 1
    }
    guard let start = startingOnAContentWord(original, at: longIndex + 1, for: short) else {
      return nil
    }
    let result = String(original[start...]).trimmingCharacters(in: .whitespacesAndNewlines)
    guard result.count > short.count, isPlausible(result) else { return nil }
    return result
  }

  /// Whether `index` starts a word. A hyphenated word is one word, so `peer` in
  /// `peer-to-peer` does not start one, and neither does `to`.
  private static func startsWord(_ text: [Character], at index: Int) -> Bool {
    guard index > 0 else { return true }
    let previous = text[index - 1]
    return !(previous.isLetter || previous.isNumber || previous == "-")
  }

  /// The words of `text` from `start`, a hyphenated word counting as one.
  private static func words(_ text: [Character], from start: Int) -> [String] {
    String(text[start...]).split(whereSeparator: { !($0.isLetter || $0.isNumber || $0 == "-") })
      .map(String.init)
  }

  /// Lowercase words an expansion does not start with. The match takes the nearest
  /// word with the right initial, so `Abstraction and Control of TE Networks
  /// (ACTN)` matched from `and`, and `support for this Protocol (TP)` from `this`.
  private static let functionWords: Set<String> = [
    "a", "an", "and", "are", "as", "at", "be", "between", "but", "by", "for", "from", "if",
    "in", "into", "is", "it", "its", "of", "on", "or", "over", "per", "than", "that", "the",
    "their", "these", "this", "those", "to", "under", "using", "via", "was", "were", "which",
    "with", "within",
  ]

  /// Where the long form starts: the matched word, unless it is a lowercase function
  /// word, in which case the nearest earlier word with the same initial that is not
  /// one, capitalized or not, so not a sentence's opening `The` or `A`. With none,
  /// there is no expansion. A hyphenated word is one word, so `on-path attackers
  /// (OPAs)` starts on `on-path`, not on `on`.
  ///
  /// Moving back takes in words the match never looked at, so they are checked: the
  /// initial of every word from the new start that is not a function word has to
  /// be a letter of the short form, in order. `Abstraction and Control of TE
  /// Networks (ACTN)` passes; `all routers in a Border Network (ABN)` does not,
  /// since `routers` has no letter in it. Matching the letters again over the
  /// longer phrase would prove nothing, as it only adds words before the old start.
  private static func startingOnAContentWord(
    _ long: [Character], at start: Int, for short: String
  ) -> Int? {
    func word(at index: Int) -> String {
      String(long[index...].prefix { $0.isLetter || $0.isNumber || $0 == "-" })
    }
    guard functionWords.contains(word(at: start)) else { return start }
    let initial = folded(long[start])
    var index = start - 1
    while index >= 0 {
      if startsWord(long, at: index), folded(long[index]) == initial,
        !functionWords.contains(word(at: index).lowercased())
      {
        return initialsFollow(short, words(long, from: index)) ? index : nil
      }
      index -= 1
    }
    return nil
  }

  /// Whether the initials of `words`, less their function words, are the letters
  /// of `short` or some of them, in order.
  private static func initialsFollow(_ short: String, _ words: [String]) -> Bool {
    var letters = short.filter { $0.isLetter || $0.isNumber }.map(folded)[...]
    for word in words where !functionWords.contains(word.lowercased()) {
      guard let initial = word.first.map(folded), let found = letters.firstIndex(of: initial)
      else { return false }
      letters = letters[(found + 1)...]
    }
    return true
  }

  /// Letters matched across an `=`, an `@` or a `<` are code, an address or markup
  /// (`Hash=Algorithm Name`, `user@Host`, `Type <Length> Value`), not words. A `:`
  /// never gets this far: both a first use and a glossary phrase end at one, which
  /// is what keeps out an IANA registration's `URI: urn:ietf:params:xml:ns:…`.
  private static func isPlausible(_ long: String) -> Bool {
    !long.contains(where: { "=@<".contains($0) })
  }

  /// How many words of `long` are not function words. A glossary definition is
  /// held to about one per letter of what it expands, two more at most, because a
  /// definition can be a sentence that happens to hold the letters: `Type-P: The
  /// legacy Route definition lacks the option to cater for packet-dependent
  /// routing`. A first use needs no such bound: its window is already bounded,
  /// and an expansion there can have more words than letters, `Bottleneck
  /// Bandwidth and Round-trip propagation time (BBR)`.
  private static func contentWords(in long: String) -> Int {
    long.split(whereSeparator: { $0.isWhitespace })
      .map { $0.trimmingCharacters(in: .punctuationCharacters) }
      .filter { !$0.isEmpty && !functionWords.contains($0.lowercased()) }
      .count
  }

  /// Whether every letter of `text` is a capital.
  private static func isAllCapitals(_ text: String) -> Bool {
    !text.contains(where: \.isLowercase)
  }

  private static func letters(in short: String) -> Int {
    short.filter { $0.isLetter || $0.isNumber }.count
  }

  private static func folded(_ character: Character) -> Character {
    let lowered = character.lowercased()
    return lowered.count == 1 ? Character(lowered) : character
  }
}
