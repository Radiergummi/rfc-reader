import Foundation

// One walk over the model, for questions asked of the whole of it.
// `referencedDocuments` and the tests that check the reader holds what a document
// cites each carried a switch over `Block` of their own, and a new field -- a
// `<dd>`'s anchor, a row's (#166) -- had to be taught to every copy.

extension Block {
  /// The blocks nested directly in this one, in document order: a list item's, a
  /// definition's, a figure's, a quotation's or an aside's.
  public var nestedBlocks: [Block] {
    switch self {
    case .list(let list): list.items.flatMap(\.blocks)
    case .definitionList(let items): items.flatMap(\.definition)
    case .figure(let figure): figure.blocks
    case .blockQuote(let inner), .aside(let inner): inner
    case .paragraph, .preformatted, .table, .references: []
    }
  }

  /// The runs of prose this block holds itself, not those of the blocks nested in
  /// it: a paragraph's text, each definition's term, each table cell. Artwork and
  /// source code are set as the author typed them, and bibliography entries are
  /// not prose.
  public var proseRuns: [[Inline]] {
    switch self {
    case .paragraph(let paragraph): [paragraph.inlines]
    case .definitionList(let items): items.map(\.term)
    case .table(let table): Array((table.header + table.rows).joined())
    case .list, .preformatted, .figure, .blockQuote, .aside, .references: []
    }
  }

  /// Every anchor this block carries itself, not those of the blocks nested in it:
  /// a link to any of them has to land somewhere.
  public var anchors: [String] {
    let anchors: [String?] =
      switch self {
      case .paragraph(let paragraph): [paragraph.anchor]
      case .list(let list): list.items.map(\.anchor)
      case .definitionList(let items): items.flatMap { [$0.anchor, $0.definitionAnchor] }
      case .preformatted(let content): [content.anchor]
      case .figure(let figure): [figure.anchor]
      case .table(let table): [table.anchor] + table.headerRowAnchors + table.rowAnchors
      case .blockQuote, .aside: []
      case .references(let list): list.entries.map(\.anchor)
      }
    return anchors.compactMap { $0 }
  }
}

extension Array where Element == Block {
  /// These blocks and every block nested in them, depth first in document order,
  /// each ahead of the blocks it holds.
  public var flattened: [Block] {
    flatMap { [$0] + $0.nestedBlocks.flattened }
  }
}

extension Array where Element == Inline {
  /// These inlines and every inline nested in them -- the words inside emphasis,
  /// strong text and a link -- depth first, each ahead of what it holds.
  public var flattened: [Inline] {
    flatMap { inline -> [Inline] in
      switch inline {
      case .emphasis(let inner), .strong(let inner), .link(_, let inner): [inline] + inner.flattened
      case .text, .code, .superscript, .subscript, .crossReference, .lineBreak: [inline]
      }
    }
  }
}
