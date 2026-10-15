import Foundation
import RFCKit

/// What a glossed run means where the document itself says so (#396): its card on
/// hover, force click and long press, and Go to Definition or Go to Expansion.
public enum Gloss: Sendable, Hashable {
  /// A term the document defines, with its definition.
  case term(DefinedTerm)
  /// An abbreviation the document expands, with the expansion (#67).
  case abbreviation(Abbreviation)

  /// The card's title: the term or the short form, as the document spells it.
  public var title: String {
    switch self {
    case .term(let term): term.term
    case .abbreviation(let abbreviation): abbreviation.short
    }
  }

  /// The card's text: the definition's prose, a line for each paragraph, list item
  /// or term it holds, or the abbreviation's expansion. Document text, so never
  /// looked up in a catalog.
  public var text: String {
    switch self {
    case .term(let term):
      term.definition.flattened.flatMap(\.proseRuns).map(\.plainText).joined(separator: "\n")
    case .abbreviation(let abbreviation): abbreviation.expansion
    }
  }

  /// Where the menu's item goes: a term's definition, or the section that expands an
  /// abbreviation, the abstract where it expands one. Nil for a definition with no
  /// anchor.
  public var anchor: String? {
    switch self {
    case .term(let term): term.anchor
    case .abbreviation(let abbreviation):
      abbreviation.sectionAnchor ?? DocumentTextBuilder.abstractAnchor
    }
  }

  /// The menu's item that follows `anchor`: Go to Definition for a term, Go to
  /// Expansion for an abbreviation (#67).
  public func followTitle(locale: Locale = .interface) -> String {
    switch self {
    case .term: String(kit: "Go to Definition", locale: locale)
    case .abbreviation: String(kit: "Go to Expansion", locale: locale)
    }
  }
}

/// Boxes a `Gloss`, as `ReferenceBox` does a cross reference: one per use, so two
/// adjacent uses are two.
public final class GlossBox: NSObject, Sendable {
  public let gloss: Gloss
  public init(_ gloss: Gloss) { self.gloss = gloss }
}
