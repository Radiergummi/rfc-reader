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
  /// it: a paragraph's text, each definition's term, each table cell, each
  /// reference's annotation. Artwork and source code are set as the author typed
  /// them, and the rest of a bibliography entry is not prose.
  public var proseRuns: [[Inline]] {
    switch self {
    case .paragraph(let paragraph): [paragraph.inlines]
    case .definitionList(let items): items.map(\.term)
    case .table(let table): (table.header + table.rows).flatMap(\.cells)
    case .references(let list): list.entries.map(\.annotation)
    case .list, .preformatted, .figure, .blockQuote, .aside: []
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
      case .table(let table): [table.anchor] + (table.header + table.rows).map(\.anchor)
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

extension RFCDocument {
  /// Every block in the document, in document order: the abstract's first, then
  /// each section's, depth first through nesting and through subsections, each
  /// block ahead of what it holds. The one definition of "every block" (#131).
  public var blocks: [Block] {
    (header.abstract + allSections.flatMap(\.blocks)).flattened
  }

  /// Every inline a reader sees as prose, in document order: the abstract, then
  /// each section's heading and its blocks' own runs of prose. The one definition
  /// of "everywhere the text can cite something" (#131); a walk that missed the
  /// headings was #127.
  ///
  /// Flattened as `[Inline].flattened` is: an emphasis, strong text or link comes
  /// ahead of the inlines it holds, and they come too. So this is for finding
  /// inlines, such as cross references, not for reading text, where a wrapper's
  /// words would be counted twice.
  ///
  /// Not captions, which are plain strings in the model, and not artwork or source
  /// code, which are set as typed; see `Block.proseRuns`.
  public var proseInlines: [Inline] {
    proseInlinesBySection.flatMap(\.inlines)
  }

  /// `proseInlines`, grouped by the place they are read in: the abstract first, with
  /// no anchor, then each section with its own heading and blocks, not its
  /// subsections'. For a question that has to say where a citation sits.
  public var proseInlinesBySection: [(sectionAnchor: String?, inlines: [Inline])] {
    let abstract = header.abstract.flattened.flatMap(\.proseRuns)
    let sections = allSections.map { section in
      let runs = [section.title] + section.blocks.flattened.flatMap(\.proseRuns)
      return (sectionAnchor: Optional(section.anchor), inlines: runs.flatMap(\.flattened))
    }
    return [(sectionAnchor: nil, inlines: abstract.flatMap(\.flattened))] + sections
  }

  /// The first section, depth first, that `matches`, without building the list of
  /// every section to look through.
  func firstSection(where matches: (Section) -> Bool) -> Section? {
    func search(_ sections: [Section]) -> Section? {
      for section in sections {
        if matches(section) { return section }
        if let found = search(section.subsections) { return found }
      }
      return nil
    }
    return search(sections)
  }
}
