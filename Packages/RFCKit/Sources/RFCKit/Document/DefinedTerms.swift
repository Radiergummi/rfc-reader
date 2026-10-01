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
/// text, one placed directly in a section, gives way to any entry that has one.
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
  static func defined(in document: RFCDocument, indexed: [DefinedTerm] = [])
    -> [String: DefinedTerm]
  {
    var found: [String: DefinedTerm] = [:]
    func record(_ term: DefinedTerm) {
      guard !term.term.isEmpty, found[term.term] == nil else { return }
      found[term.term] = term
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
              if !defined.definition.isEmpty, undefined.remove(defined.term) != nil {
                found[defined.term] = defined
              } else {
                record(defined)
              }
            }
          }
        }
        read(section.subsections, inherited: inherited || passesTermsOn(title))
      }
    }
    read(document.sections, inherited: false)
    return found
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
