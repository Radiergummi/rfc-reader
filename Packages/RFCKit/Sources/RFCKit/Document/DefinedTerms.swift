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
/// `Type: 8 bits` defines no term. Free prose ("a connection record called a
/// Transmission Control Block") is not read: that is a heuristic nothing has measured.
/// The first definition of a term wins.
enum DefinedTerms {
  /// Whether a section titled `title` defines terms: a Terminology, Definitions or
  /// Glossary section, or one titled `Conventions and …`. A bare `Conventions` or
  /// `Notational Conventions` describes notation, not terms.
  static func namesTerms(_ title: String) -> Bool {
    let lowered = title.lowercased()
    let words = Set(lowered.split(whereSeparator: { !$0.isLetter }))
    return !words.isDisjoint(with: ["terminology", "definitions", "definition", "glossary"])
      || lowered.hasPrefix("conventions and ")
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
    for section in document.allSections where namesTerms(section.title.plainText) {
      for block in section.blocks.flattened {
        guard case .definitionList(let items) = block else { continue }
        for item in items {
          record(
            DefinedTerm(
              term: term(item.term.plainText), anchor: item.anchor ?? section.anchor,
              definition: item.definition))
        }
      }
    }
    return found
  }

  /// A definition list's term as the term itself: `significant change:` without the
  /// colon the list sets after it.
  static func term(_ written: String) -> String {
    var term = written.trimmingCharacters(in: .whitespacesAndNewlines)
    while term.last == ":" { term.removeLast() }
    return term.trimmingCharacters(in: .whitespaces)
  }
}
