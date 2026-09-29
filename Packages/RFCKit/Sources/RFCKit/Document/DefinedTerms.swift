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
/// it defines terms (`namesTerms`): most lists describe fields or notation, and
/// `Type: 8 bits` defines no term. A list nested in a definition is not read either: it
/// describes that term's parts. Free prose ("a connection record called
/// a Transmission Control Block") is not read: that is a heuristic nothing has measured.
/// The first definition of a term wins, except that a definition list entry replaces an
/// index entry with no definition text, one placed directly in a section.
enum DefinedTerms {
  /// Whether a section titled `title` defines terms: a Terminology or Glossary section,
  /// one titled `Conventions and …`, or one whose Definitions open the title or follow
  /// `Terms and` or `Conventions and`. A bare `Conventions` or `Notational Conventions`
  /// describes notation, not terms, and `Field Definitions` or `Option Definitions` the
  /// parts of a format.
  static func namesTerms(_ title: String) -> Bool {
    let lowered = title.lowercased()
    let words = lowered.split(whereSeparator: { !$0.isLetter }).map(String.init)
    if words.contains("terminology") || words.contains("glossary")
      || lowered.hasPrefix("conventions and ")
    {
      return true
    }
    for (position, word) in words.enumerated() where word == "definitions" {
      if position == 0 {
        return true
      }
      if position >= 2, words[position - 1] == "and",
        ["terms", "conventions"].contains(words[position - 2])
      {
        return true
      }
    }
    return false
  }

  /// Every term the document defines: `indexed` first, from primary index entries, then
  /// the definition lists of sections that name terms.
  static func defined(in document: RFCDocument, indexed: [DefinedTerm] = [])
    -> [String: DefinedTerm]
  {
    var found: [String: DefinedTerm] = [:]
    func record(_ term: DefinedTerm) {
      guard !term.term.isEmpty, found[term.term] == nil else { return }
      found[term.term] = term
    }
    indexed.forEach(record)
    // An index entry placed directly in a section has no definition text, which a
    // definition list entry for the same term supplies.
    var undefined = Set(found.values.filter(\.definition.isEmpty).map(\.term))
    for section in document.allSections where namesTerms(section.title.plainText) {
      for items in definitionLists(in: section.blocks) {
        for item in items {
          let defined = DefinedTerm(
            term: term(item.term.plainText), anchor: item.anchor ?? section.anchor,
            definition: item.definition)
          if undefined.remove(defined.term) != nil {
            found[defined.term] = defined
          } else {
            record(defined)
          }
        }
      }
    }
    return found
  }

  /// The definition lists among `blocks`, however deep, but not those nested in a
  /// definition: that list describes its term's parts, not terms of the document's own.
  /// A list set in a list item is still the section's (RFC 8843 indents its terminology
  /// that way).
  static func definitionLists(in blocks: [Block]) -> [[DefinitionItem]] {
    blocks.flatMap { block -> [[DefinitionItem]] in
      if case .definitionList(let items) = block {
        return [items]
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
