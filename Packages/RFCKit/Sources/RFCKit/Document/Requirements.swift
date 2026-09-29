import Foundation

/// One of BCP 14's key words (RFC 2119, as RFC 8174 narrows it to uppercase).
public enum BCP14Keyword: String, CaseIterable, Sendable, Hashable, Codable {
  case must = "MUST"
  case mustNot = "MUST NOT"
  case required = "REQUIRED"
  case shall = "SHALL"
  case shallNot = "SHALL NOT"
  case should = "SHOULD"
  case shouldNot = "SHOULD NOT"
  case recommended = "RECOMMENDED"
  case notRecommended = "NOT RECOMMENDED"
  case may = "MAY"
  case optional = "OPTIONAL"
}

/// A sentence that states a requirement: what it says, the key words that make it
/// one, and where it is.
public struct Requirement: Sendable, Hashable {
  /// In the order the sentence uses them.
  public var keywords: [BCP14Keyword]
  public var sentence: String
  /// Where to go to read it: its paragraph's anchor, or its section's where the
  /// paragraph has none, as in every document parsed from legacy text.
  public var anchor: String
  public var sectionAnchor: String
  public var sectionNumber: String?
  public var sectionTitle: String
  /// True for a document parsed from legacy text, whose structure, and so whose
  /// sentences and anchors, the parser recovered by heuristics.
  public var isHeuristic: Bool

  public init(
    keywords: [BCP14Keyword], sentence: String, anchor: String, sectionAnchor: String,
    sectionNumber: String?, sectionTitle: String, isHeuristic: Bool
  ) {
    self.keywords = keywords
    self.sentence = sentence
    self.anchor = anchor
    self.sectionAnchor = sectionAnchor
    self.sectionNumber = sectionNumber
    self.sectionTitle = sectionTitle
    self.isHeuristic = isHeuristic
  }
}

/// Every BCP 14 requirement a document states (#180), in document order.
///
/// Only a document that cites BCP 14, or RFC 2119 or RFC 8174 in it, uses the key
/// words in their BCP 14 sense, and only in uppercase (RFC 8174), so that is what is read, in XML
/// and legacy text alike: RFCXML's `<bcp14>` becomes emphasis in the model, and
/// legacy text never had it. Only prose states requirements: paragraphs, list
/// items, definitions, table cells and asides, not artwork, source code,
/// quotations or the references. The paragraph declaring the key words is not a requirement.
public enum Requirements {
  public static func extract(from document: RFCDocument) -> [Requirement] {
    // A part of BCP 14 uses its own key words in their BCP 14 sense without citing
    // itself, which is not among the documents it references.
    let cited = Set(document.referencedDocuments + [document.header.id].compactMap(\.self))
    let bcp14: Set<DocumentID> = [.rfc(2119), .rfc(8174), DocumentID(series: .bcp, number: 14)]
    guard !cited.isDisjoint(with: bcp14) else { return [] }
    let isHeuristic = document.source == .text
    var found: [Requirement] = []
    for section in document.allSections {
      func record(_ text: String, anchor: String?) {
        // XML keeps the author's line breaks inside a paragraph.
        let text = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        for sentence in sentences(in: text) {
          let keywords = keywords(in: sentence)
          guard !keywords.isEmpty, !declaresKeywords(sentence) else { continue }
          found.append(
            Requirement(
              keywords: keywords, sentence: sentence, anchor: anchor ?? section.anchor,
              sectionAnchor: section.anchor, sectionNumber: section.number,
              sectionTitle: section.titleText, isHeuristic: isHeuristic))
        }
      }
      visit(section.blocks, around: nil, record)
    }
    return found
  }

  /// The prose blocks, in document order, each with the nearest anchor it lands on:
  /// its own, else that of the list item, definition or table around it, else
  /// `outer`, the anchor of what encloses these blocks.
  private static func visit(
    _ blocks: [Block], around outer: String?, _ record: (String, String?) -> Void
  ) {
    for block in blocks {
      switch block {
      case .paragraph(let paragraph):
        record(paragraph.plainText, paragraph.anchor ?? outer)
      case .list(let list):
        for item in list.items { visit(item.blocks, around: item.anchor ?? outer, record) }
      case .definitionList(let items):
        for item in items {
          record(item.term.plainText, item.anchor ?? outer)
          visit(item.definition, around: item.definitionAnchor ?? item.anchor ?? outer, record)
        }
      case .aside(let inner):
        visit(inner, around: outer, record)
      case .table(let table):
        // A profile often states its requirements a row at a time, a cell saying
        // what a field MUST be. A cell of key words alone, as in a table of
        // algorithms and whether each MUST be implemented, says nothing without
        // its row, so that row is one requirement. A row lands on its own anchor
        // where it has one.
        for row in table.rows {
          let anchor = row.anchor ?? table.anchor ?? outer
          let cells = row.cells.map(\.plainText)
          if cells.contains(where: isOnlyKeywords) {
            record(cells.joined(separator: " | "), anchor)
          } else {
            for cell in cells { record(cell, anchor) }
          }
        }
      case .preformatted, .figure, .blockQuote, .references:
        break
      }
    }
  }

  /// The boilerplate that declares the key words, which names them and requires
  /// nothing. It is worded many ways ("as described in BCP 14", "as defined in RFC
  /// 2119", "as specified in [KEYWORDS]"), but it always lists several key words at
  /// once, which no requirement does; a shorter list is known by what it cites,
  /// and by saying the key words are "interpreted" or by naming them in quotes: a
  /// sentence that quotes a key word is about it, not bound by it.
  static func declaresKeywords(_ sentence: String) -> Bool {
    if Set(keywords(in: sentence)).count >= 5 { return true }
    let citesBCP14 = ["BCP 14", "BCP14", "2119", "8174", "KEYWORDS"].contains {
      sentence.contains($0)
    }
    return citesBCP14 && (sentence.contains("interpreted") || namesKeywordsInQuotes(sentence))
  }

  /// Whether `sentence` names a key word in quotes, `"MUST"` or `'MUST'`, rather
  /// than using it.
  private static func namesKeywordsInQuotes(_ sentence: String) -> Bool {
    let quotes = [("\"", "\""), ("'", "'"), ("“", "”"), ("‘", "’")]
    return BCP14Keyword.allCases.contains { keyword in
      quotes.contains { open, close in sentence.contains(open + keyword.rawValue + close) }
    }
  }

  // MARK: - Key words

  /// Whether `text` has key words and no other words: "MUST", "SHOULD NOT".
  static func isOnlyKeywords(_ text: String) -> Bool {
    let words = text.split { !$0.isLetter }.count
    let keywordWords = keywords(in: text).reduce(0) { count, keyword in
      count + keyword.rawValue.split(separator: " ").count
    }
    return words > 0 && keywordWords == words
  }

  /// The key words in `sentence`, in order: uppercase whole words only, a negated
  /// one (`MUST NOT`, `NOT RECOMMENDED`) read whole before the one it contains.
  static func keywords(in sentence: String) -> [BCP14Keyword] {
    let words = sentence.split { !$0.isLetter }.map(String.init)
    var found: [BCP14Keyword] = []
    var index = 0
    while index < words.count {
      let word = words[index]
      let next = index + 1 < words.count ? words[index + 1] : nil
      if let pair = next.flatMap({ BCP14Keyword(rawValue: "\(word) \($0)") }) {
        found.append(pair)
        index += 2
        continue
      }
      if word != "NOT", let single = BCP14Keyword(rawValue: word) {
        found.append(single)
      }
      index += 1
    }
    return found
  }

  // MARK: - Sentences

  /// Words a stop follows without ending the sentence.
  private static let abbreviations: Set<String> = ["e.g", "i.e", "Sec", "cf", "vs", "Fig"]

  /// `text` split into sentences, by a rule of our own, since RFCKit builds on
  /// Linux, where `NLTokenizer` is not: a sentence ends at `.`, `!` or `?`, after any
  /// closing quote or parenthesis, when a space and then a capital letter, a digit,
  /// or an opening quote or bracket follow, and the stop does not end an
  /// abbreviation such as `e.g.`.
  static func sentences(in text: String) -> [String] {
    let characters = Array(text)
    var sentences: [String] = []
    var start = 0
    var index = 0
    while index < characters.count {
      guard ".!?".contains(characters[index]) else {
        index += 1
        continue
      }
      var end = index + 1
      while end < characters.count, "\"')]”’".contains(characters[end]) { end += 1 }
      var next = end
      while next < characters.count, characters[next] == " " { next += 1 }
      let endsSentence =
        next > end && next < characters.count
        && (characters[next].isUppercase || characters[next].isNumber
          || "\"'([“‘".contains(characters[next]))
        && !endsAbbreviation(characters, at: index)
      if endsSentence {
        sentences.append(String(characters[start..<end]).trimmingCharacters(in: .whitespaces))
        start = next
      }
      index = end
    }
    let rest = String(characters[start...]).trimmingCharacters(in: .whitespaces)
    if !rest.isEmpty { sentences.append(rest) }
    return sentences
  }

  /// Whether the stop at `index` ends one of `abbreviations`.
  private static func endsAbbreviation(_ characters: [Character], at index: Int) -> Bool {
    guard characters[index] == "." else { return false }
    var start = index
    while start > 0, characters[start - 1].isLetter || characters[start - 1] == "." {
      start -= 1
    }
    return abbreviations.contains(String(characters[start..<index]))
  }
}
