import Foundation
import RFCKit

/// What a glossed run means where the document itself says so (#396): its card on
/// hover, force click and long press, and Go to Definition. Abbreviations are to
/// share it (#67).
public enum Gloss: Sendable, Hashable {
  /// A term the document defines, with its definition.
  case term(DefinedTerm)

  /// The card's title: the term, as the document spells it.
  public var title: String {
    switch self {
    case .term(let term): term.term
    }
  }

  /// The card's text: the definition's prose, a line for each paragraph, list item
  /// or term it holds. Document text, so never looked up in a catalog.
  public var text: String {
    switch self {
    case .term(let term):
      term.definition.flattened.flatMap(\.proseRuns).map(\.plainText).joined(separator: "\n")
    }
  }

  /// Where Go to Definition goes, or nil for a definition with no anchor.
  public var anchor: String? {
    switch self {
    case .term(let term): term.anchor
    }
  }
}

/// Boxes a `Gloss`, as `ReferenceBox` does a cross reference: one per use, so two
/// adjacent uses are two.
public final class GlossBox: NSObject, Sendable {
  public let gloss: Gloss
  public init(_ gloss: Gloss) { self.gloss = gloss }
}
