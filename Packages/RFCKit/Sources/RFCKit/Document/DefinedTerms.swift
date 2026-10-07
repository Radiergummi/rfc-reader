import Foundation

/// A term the document defines itself, and where (#176).
public struct DefinedTerm: Sendable, Hashable, Codable {
  /// As the document writes it: `significant change`, `user agent`.
  public var term: String
  /// Where the definition is: the definition list item's or the element's own anchor,
  /// or its section's.
  public var anchor: String?
  /// The definition itself, for a reader to show beside the term.
  public var definition: [Block]

  public init(term: String, anchor: String?, definition: [Block]) {
    self.term = term
    self.anchor = anchor
    self.definition = definition
  }
}

/// A primary index entry's term, and the anchors it may be defined at, innermost
/// first: what the XML says of it, before the model is asked which it holds (#455).
struct IndexedTerm: Sendable, Hashable {
  var term: String
  var anchors: [String]
}

/// Collects the terms a document defines, at parse time, the way abbreviations are
/// (#176): from the document's own text, so a definition is the author's and correct
/// for this document.
///
/// Two sources, strictest first. A primary index entry, `<iref primary="true">`, is the
/// author marking where a term is defined; few documents use it (RFC 9110 and the other
/// HTTP core documents). A definition list is a definition only in a section that says
/// it defines terms (`namesTerms`), or a subsection of one: most lists describe fields or notation, and
/// `Type: 8 bits` defines no term. A list nested in a definition is not read either: it
/// describes that term's parts. A term introduced in running prose, where a sentence
/// names a thing and then calls it something, is not read: that is a heuristic nothing
/// has measured.
/// The first definition of a term wins, except that an index entry with no definition
/// text, one placed directly in a section, gives way to any entry that has one. A term
/// still without a definition at the end has none to show, and is dropped (#396).
///
/// A term is kept by each spelling prose would use on its own (`spellings(of:)`):
/// `WGW (Widget Gateway)` as both `WGW` and `Widget Gateway`, a citation or the start
/// of the definition the term carried left off.
enum DefinedTerms {
  /// Whether a section titled `title` defines terms: one opening with Definitions, or
  /// one whose title names terms for its subsections as well (`passesTermsOn`).
  static func namesTerms(_ title: String) -> Bool {
    words(of: title).first == "definitions" || passesTermsOn(title)
  }

  /// Whether a section titled `title` defines terms, and its subsections with it: one
  /// whose title holds Terminology, Glossary or the noun Terms (`New Terms`, `Definition
  /// of Terms`), one titled `Conventions and` Definitions, Terminology, Terms or
  /// Acronyms, or one whose title lists Definitions as an item of its own, as in
  /// `Symbols, Abbreviations, and Definitions`. A title that only opens with Definitions
  /// names terms for its own lists but passes nothing on, because it can head a
  /// specification's body, its subsections the protocol's variables (RFC 8985) or
  /// commands (RFC 9208). A bare `Conventions`, `Notational Conventions` or
  /// `Conventions and Notation` describes notation, not terms. Definitions qualified by a
  /// word before it (`Field`, `Option`, and `General` or `Technical` as readily) are a
  /// format's parts as often as a document's terms, and are left out.
  static func passesTermsOn(_ title: String) -> Bool {
    let words = words(of: title)
    if words.contains("terminology") || words.contains("glossary") || words.contains("terms") {
      return true
    }
    if words.starts(with: ["conventions", "and"]), words.count > 2,
      // Terminology and Terms are already taken above, wherever they stand.
      ["definitions", "acronyms"].contains(words[2])
    {
      return true
    }
    // The title as a list: `Symbols, Abbreviations, and Definitions` has three items.
    let items = title.lowercased().split(separator: ",").flatMap {
      $0.components(separatedBy: " and ")
    }
    return items.count > 1
      && items.contains { item in
        let itemWords = item.split(whereSeparator: { !$0.isLetter })
        return itemWords == ["definitions"] || itemWords == ["and", "definitions"]
      }
  }

  private static func words(of title: String) -> [String] {
    title.lowercased().split(whereSeparator: { !$0.isLetter }).map(String.init)
  }

  /// Every term the document defines: `indexed` first, from primary index entries, then
  /// the definition lists of sections that name terms, and of their subsections.
  static func defined(in document: RFCDocument, indexed: [IndexedTerm] = [])
    -> [String: DefinedTerm]
  {
    defined(in: document, indexed: lookUp(indexed, in: document))
  }

  /// Each primary index entry where the model holds it (#455): at the first of its
  /// anchors the model holds, defined by what holds it. A paragraph, a piece of
  /// artwork, a figure or a table is its own definition, a list item or a definition
  /// list entry its blocks, and a section none, as an entry placed directly in one
  /// marks the section. An entry at no anchor the model holds is dropped.
  static func lookUp(_ indexed: [IndexedTerm], in document: RFCDocument) -> [DefinedTerm] {
    guard !indexed.isEmpty else { return [] }
    var definitions: [String: [Block]] = [:]
    func hold(_ anchor: String?, _ definition: [Block]) {
      guard let anchor, definitions[anchor] == nil else { return }
      definitions[anchor] = definition
    }
    for section in document.allSections {
      hold(section.anchor, [])
    }
    for block in document.blocks {
      switch block {
      case .list(let list):
        for item in list.items { hold(item.anchor, item.blocks) }
      case .definitionList(let list):
        for item in list.items {
          hold(item.anchor, item.definition)
          hold(item.definitionAnchor, item.definition)
        }
      case .paragraph, .preformatted, .figure, .table:
        for anchor in block.anchors { hold(anchor, [block]) }
      case .blockQuote, .aside, .references, .index:
        break
      }
    }
    return indexed.compactMap { entry in
      guard let anchor = entry.anchors.first(where: { definitions[$0] != nil }) else { return nil }
      return DefinedTerm(term: entry.term, anchor: anchor, definition: definitions[anchor] ?? [])
    }
  }

  /// Every term the document defines: `indexed` first, primary index entries already
  /// looked up in the model, then the definition lists of sections that name terms.
  static func defined(in document: RFCDocument, indexed: [DefinedTerm])
    -> [String: DefinedTerm]
  {
    var found: [String: DefinedTerm] = [:]
    func record(_ term: DefinedTerm) {
      for spelling in spellings(of: term.term) where found[spelling] == nil {
        found[spelling] = DefinedTerm(
          term: spelling, anchor: term.anchor, definition: term.definition)
      }
    }
    // An index entry placed directly in a section has no definition text, which
    // another entry for the same term supplies: a later index entry that has one, or
    // a definition list entry.
    indexed.filter { !$0.definition.isEmpty }.forEach(record)
    indexed.filter(\.definition.isEmpty).forEach(record)
    var undefined = Set(found.values.filter(\.definition.isEmpty).map(\.term))
    // A subsection of a section titled for its terms is one of its parts (`Core Terms`
    // under Terminology), whatever its own title says, unless that title only opens
    // with Definitions.
    func read(_ sections: [Section], inherited: Bool) {
      for section in sections {
        let title = section.title.plainText
        if inherited || namesTerms(title) {
          for items in definitionLists(in: section.blocks) {
            for item in items {
              let defined = DefinedTerm(
                term: term(item.term.plainText), anchor: item.anchor ?? section.anchor,
                definition: item.definition)
              for spelling in spellings(of: defined.term) {
                let spelled = DefinedTerm(
                  term: spelling, anchor: defined.anchor, definition: defined.definition)
                if !spelled.definition.isEmpty, undefined.remove(spelling) != nil {
                  found[spelling] = spelled
                } else if found[spelling] == nil {
                  found[spelling] = spelled
                }
              }
            }
          }
        }
        read(section.subsections, inherited: inherited || passesTermsOn(title))
      }
    }
    read(document.sections, inherited: false)
    return found.filter { !$0.value.definition.isEmpty }
  }

  // MARK: Spellings

  /// The spellings a term as its list or index entry writes it stands for, each as
  /// prose would write it on its own; empty when it is none (#396).
  ///
  /// Left off: a citation after it (`Widget datagram [RFC9999]`, `… RFC 9999`), the
  /// start of its definition after a colon and a space (`WGW: Widget Gateway.`), a
  /// dash after it, and quotes around it. A parenthetical at the end is a second
  /// spelling when either side is an abbreviation (`WGW (Widget Gateway)`), and a
  /// qualifier, left off, when neither is (`parent (of a widget)`). A list is a
  /// spelling per item (`Widget, wdgWidget`), and a list of single letters, a
  /// formula's variables, is none. Notation keeps its colons and brackets: those with
  /// no space before them (`widget:port`, `W[i..j]`), and a term that opens with a
  /// parenthesis.
  static func spellings(of written: String) -> [String] {
    var term = written.trimmingCharacters(in: .whitespacesAndNewlines)
    if let citation = term.range(of: " [") { term = String(term[..<citation.lowerBound]) }
    if let citation = term.range(
      of: #"\sRFC[\s\u{00A0}]\d"#, options: .regularExpression)
    {
      term = String(term[..<citation.lowerBound])
    }
    if let definition = term.range(of: ": ") { term = String(term[..<definition.lowerBound]) }
    term = term.trimmingCharacters(in: .whitespaces)
    while let last = term.last, [":", "-", "\u{2013}", "\u{2014}"].contains(last) {
      term.removeLast()
      term = term.trimmingCharacters(in: .whitespaces)
    }
    let quotes: Set<Character> = ["\"", "\u{201C}", "\u{201D}"]
    if term.count > 1, let first = term.first, let last = term.last, quotes.contains(first),
      quotes.contains(last)
    {
      term = String(term.dropFirst().dropLast())
    }
    guard !term.isEmpty else { return [] }
    if term.hasPrefix("(") { return [term] }
    if term.hasSuffix(")"), let open = term.range(of: " (", options: .backwards) {
      let outside = String(term[..<open.lowerBound])
      let inside = String(term[open.upperBound...].dropLast())
      guard isAbbreviation(outside) || isAbbreviation(inside) else { return spellings(of: outside) }
      return [outside, inside].filter { !$0.isEmpty }
    }
    guard term.contains(", ") else { return [term] }
    let items = term.components(separatedBy: ", ").map { item in
      item.hasPrefix("or ") || item.hasPrefix("and ")
        ? String(item.drop { $0 != " " }.dropFirst()) : item
    }
    return items.filter { $0.count > 1 && $0 != "etc." }
  }

  /// Whether `word` is an abbreviation: one word with two capitals or more, `WGW` or
  /// `PoW`.
  private static func isAbbreviation(_ word: String) -> Bool {
    !word.contains(" ") && word.filter(\.isUppercase).count >= 2
  }

  /// The definition lists among `blocks`, however deep, but not those nested in a
  /// definition: that list describes its term's parts, not terms of the document's own.
  /// A list set in a list item is still the section's (RFC 8843 indents its terminology
  /// that way).
  static func definitionLists(in blocks: [Block]) -> [[DefinitionItem]] {
    blocks.flatMap { block -> [[DefinitionItem]] in
      if case .definitionList(let list) = block {
        return [list.items]
      }
      return definitionLists(in: block.nestedBlocks)
    }
  }

  /// A definition list's term as the term itself: `significant change:` without the
  /// colon the list sets after it.
  static func term(_ written: String) -> String {
    var term = written.trimmingCharacters(in: .whitespacesAndNewlines)
    while term.last == ":" { term.removeLast() }
    return term.trimmingCharacters(in: .whitespaces)
  }
}
