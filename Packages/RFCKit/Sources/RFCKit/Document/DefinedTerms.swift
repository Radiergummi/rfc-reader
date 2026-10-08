import Foundation

/// A term the document defines itself, and where (#176).
public struct DefinedTerm: Sendable, Hashable, Codable {
  /// One spelling of the term, as prose would write it (`DefinedTerms.spellings(of:)`):
  /// `significant change`, `user agent`.
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
  /// The block the entry sits in, as the XML reads it: the definition where the
  /// anchor the model holds defines nothing itself, as a section does for a table
  /// cell, a quotation or a figure without an anchor of its own.
  var definition: [Block] = []
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
    defined(in: document, lookedUp: lookUp(indexed, in: document))
  }

  /// Each primary index entry where the model holds it (#455): at the first of its
  /// anchors the model holds, defined by what holds it. A paragraph, a piece of
  /// artwork or a figure is its own definition, a list item or a definition list
  /// entry its blocks; a section, a table or a table row defines nothing itself, and
  /// the entry is defined by the block it sits in, a table's cell rather than the
  /// whole table. An entry at no anchor the model holds is dropped.
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
      case .table(let table):
        hold(table.anchor, [])
        for row in table.header + table.rows { hold(row.anchor, []) }
      case .paragraph, .preformatted, .figure:
        for anchor in block.anchors { hold(anchor, [block]) }
      case .blockQuote, .aside, .references, .index:
        break
      }
    }
    return indexed.compactMap { entry in
      guard let anchor = entry.anchors.first(where: { definitions[$0] != nil }) else { return nil }
      let held = definitions[anchor] ?? []
      return DefinedTerm(
        term: entry.term, anchor: anchor, definition: held.isEmpty ? entry.definition : held)
    }
  }

  /// Every term the document defines: `lookedUp` first, primary index entries already
  /// looked up in the model, then the definition lists of sections that name terms.
  static func defined(in document: RFCDocument, lookedUp indexed: [DefinedTerm])
    -> [String: DefinedTerm]
  {
    var found: [String: DefinedTerm] = [:]
    // The first definition of each spelling wins, but one with a definition replaces
    // one without, wherever each came from.
    func record(_ term: DefinedTerm, splittingLists: Bool) {
      for spelling in spellings(of: term.term, splittingLists: splittingLists) {
        if let kept = found[spelling], !(kept.definition.isEmpty && !term.definition.isEmpty) {
          continue
        }
        found[spelling] = DefinedTerm(
          term: spelling, anchor: term.anchor, definition: term.definition)
      }
    }
    // An index entry's item is a name, which an index may invert: `cache, private`.
    for term in indexed { record(term, splittingLists: false) }
    // A subsection of a section titled for its terms is one of its parts (`Core Terms`
    // under Terminology), whatever its own title says, unless that title only opens
    // with Definitions.
    func read(_ sections: [Section], inherited: Bool) {
      for section in sections {
        let title = section.title.plainText
        if inherited || namesTerms(title) {
          for items in definitionLists(in: section.blocks) {
            for item in items {
              record(
                DefinedTerm(
                  term: item.term.plainText, anchor: item.anchor ?? section.anchor,
                  definition: item.definition),
                splittingLists: true)
            }
          }
        }
        read(section.subsections, inherited: inherited || passesTermsOn(title))
      }
    }
    read(document.sections, inherited: false)
    return found.filter { !$0.value.definition.isEmpty }
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

  // MARK: Spellings

  /// The spellings a term as its list or index entry writes it stands for, each as
  /// prose would write it on its own; empty when it is none (#396).
  ///
  /// Left off: quotes around it, a citation after it (`Widget datagram [RFC9999]`,
  /// and the trailing ones `Abbreviations` leaves off a glossary phrase, `RFC 9999`,
  /// `BCP 38`), the start of its definition after a colon and a space (`WGW: Widget
  /// Gateway.`), the colon a list sets after a term, and a dash after it. A
  /// parenthetical at the end is a second spelling when one side is a short form the
  /// other expands whole (`WGW (Widget Gateway)`), and a qualifier, left off, when not
  /// (`parent (of a widget)`, `Content-Type (header field)`). With `splittingLists`,
  /// a definition list's term that is a list is the spellings of each item, cleaned
  /// as a term is (`Widget, wdgWidget`), and a list of single letters, a formula's
  /// variables, is none; an index entry's comma is an inverted name's (`cache,
  /// private`), and stays. Notation keeps its colons, commas and brackets: those
  /// inside brackets (`g(x, y)`, `(S: T)`), those with no space before them
  /// (`widget:port`, `W[i..j]`), and a term that opens with a parenthesis.
  static func spellings(of written: String, splittingLists: Bool = true) -> [String] {
    var term = unquoted(written.trimmingCharacters(in: .whitespacesAndNewlines))
    if let definition = topLevelRanges(of: ": ", in: term).first {
      term = String(term[..<definition.lowerBound])
    }
    let separators = splittingLists ? topLevelRanges(of: ", ", in: term) : []
    guard !separators.isEmpty, !isListExpanded(term) else { return spellings(ofName: term) }
    var items: [String] = []
    var start = term.startIndex
    for separator in separators {
      items.append(String(term[start..<separator.lowerBound]))
      start = separator.upperBound
    }
    items.append(String(term[start...]))
    return
      items
      .map { item in
        item.hasPrefix("or ") || item.hasPrefix("and ")
          ? String(item.drop { $0 != " " }.dropFirst()) : item
      }
      .flatMap(spellings(ofName:))
      .filter { $0.count > 1 && $0 != "etc." }
  }

  /// The spellings one name stands for, a list's item or the whole term: see
  /// `spellings(of:splittingLists:)`.
  private static func spellings(ofName written: String) -> [String] {
    var term = withoutCitation(unquoted(written.trimmingCharacters(in: .whitespaces)))
    // The colon or dash after it first: a citation is left off only at the end.
    term = trimmingTrailingPunctuation(term)
    term = trimmingTrailingPunctuation(term.replacing(Abbreviations.citationsPattern, with: ""))
    term = unquoted(term)
    guard !term.isEmpty else { return [] }
    if term.hasPrefix("(") { return [term] }
    if let (outside, inside) = parenthetical(term) {
      guard expands(outside, inside) || expands(inside, outside) else {
        return spellings(ofName: outside)
      }
      return [outside, inside]
    }
    return [term]
  }

  /// `text` before a bracketed citation after it: `Widget datagram [RFC9999]`.
  private static func withoutCitation(_ text: String) -> String {
    guard let citation = topLevelRanges(of: " [", in: text).first else { return text }
    return String(text[..<citation.lowerBound])
  }

  /// The name before a parenthetical that ends `term`, and the parenthetical's own
  /// text, without a citation it carries: `KMAC (Widget MAC [RFC9999])`.
  private static func parenthetical(_ term: String) -> (outside: String, inside: String)? {
    guard term.hasSuffix(")"), let open = term.range(of: " (", options: .backwards) else {
      return nil
    }
    return (
      String(term[..<open.lowerBound]), withoutCitation(String(term[open.upperBound...].dropLast()))
    )
  }

  /// Whether `term` is a list that a short form after it abbreviates as a whole,
  /// `Widgets, Gadgets, and Gizmos (WGGs)`: one name, not a list of three.
  private static func isListExpanded(_ term: String) -> Bool {
    guard let (outside, inside) = parenthetical(trimmingTrailingPunctuation(term)) else {
      return false
    }
    return expands(inside, outside)
  }

  /// Where `separator` occurs in `text` outside parentheses, brackets and braces, so
  /// notation such as `g(x, y)` or `{0, 1}` is not cut at what it holds.
  private static func topLevelRanges(of separator: String, in text: String)
    -> [Range<String.Index>]
  {
    var ranges: [Range<String.Index>] = []
    var depth = 0
    var index = text.startIndex
    while index < text.endIndex {
      if depth == 0, text[index...].hasPrefix(separator) {
        let end = text.index(index, offsetBy: separator.count)
        ranges.append(index..<end)
        index = end
        continue
      }
      switch text[index] {
      case "(", "[", "{": depth += 1
      case ")", "]", "}": depth = max(0, depth - 1)
      default: break
      }
      index = text.index(after: index)
    }
    return ranges
  }

  /// `text` without the colons and dashes after it, and the spaces around them.
  private static func trimmingTrailingPunctuation(_ text: String) -> String {
    var text = text.trimmingCharacters(in: .whitespaces)
    while let last = text.last, [":", "-", "\u{2013}", "\u{2014}"].contains(last) {
      text.removeLast()
      text = text.trimmingCharacters(in: .whitespaces)
    }
    return text
  }

  /// `text` without the quotes around it, double or single, straight or typographic:
  /// only when they enclose it whole, not when they open its first item and close its
  /// last.
  private static func unquoted(_ text: String) -> String {
    let families: [Set<Character>] = [
      ["\"", "\u{201C}", "\u{201D}"], ["'", "\u{2018}", "\u{2019}"],
    ]
    guard text.count > 1, let first = text.first, let last = text.last,
      let quotes = families.first(where: { $0.contains(first) && $0.contains(last) })
    else { return text }
    let inside = text.dropFirst().dropLast()
    return inside.contains(where: quotes.contains) ? text : String(inside)
  }

  /// Whether `short` is a short form that abbreviates all of `long`, as
  /// `Abbreviations` reads a glossary entry: `WGW` and `Widget Gateway`, not
  /// `Content-Type` and `header field`, nor `WGW` and `Upstream Widget Gateway`, whose
  /// first word qualifies the expansion.
  private static func expands(_ short: String, _ long: String) -> Bool {
    Abbreviations.isShortForm(short) && Abbreviations.longForm(of: short, in: long) == long
  }
}
