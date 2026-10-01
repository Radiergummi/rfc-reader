import Foundation
import Testing

@testable import RFCKit

extension Block {
  /// The paragraph this block is, if it is one: what a test filters a block list by,
  /// written once instead of as an `if case` at every call site.
  var paragraph: Paragraph? {
    if case .paragraph(let paragraph) = self { paragraph } else { nil }
  }

  var list: ListBlock? {
    if case .list(let list) = self { list } else { nil }
  }

  var preformatted: Preformatted? {
    if case .preformatted(let preformatted) = self { preformatted } else { nil }
  }

  var references: ReferenceList? {
    if case .references(let list) = self { list } else { nil }
  }

  var table: Table? {
    if case .table(let table) = self { table } else { nil }
  }

  var figure: Figure? {
    if case .figure(let figure) = self { figure } else { nil }
  }

  var definitionList: DefinitionList? {
    if case .definitionList(let list) = self { list } else { nil }
  }

  var definitionItems: [DefinitionItem]? { definitionList?.items }
}

extension Inline {
  var crossReference: CrossReference? {
    if case .crossReference(let reference) = self { reference } else { nil }
  }
}

extension RFCDocument {
  /// The extractions the assertions open with. Every one of them is a filter of the
  /// same block list, and written out at each call site the filter -- which is the
  /// part that differs -- is the line you have to read four lines to find.
  ///
  /// The blocks directly in a section, not the nested ones and not the abstract:
  /// what these tests count. `RFCDocument.blocks` is every block (#131).
  var everyBlock: [Block] { allSections.flatMap(\.blocks) }

  /// The unnumbered text before the first heading, which the parser keeps as `preamble`.
  var leadIn: [Block] { sections.first { $0.anchor == "preamble" }?.blocks ?? [] }

  var referenceLists: [ReferenceList] { everyBlock.compactMap(\.references) }

  var paragraphs: [Paragraph] { everyBlock.compactMap(\.paragraph) }

  /// The items of each definition list: a catalog, or hanging-indent definitions.
  var definitionLists: [[DefinitionItem]] { everyBlock.compactMap(\.definitionItems) }

  /// Every paragraph at any depth: inside list items, definitions, figures, block
  /// quotes and asides as well as directly in a section.
  var nestedParagraphs: [Paragraph] { everyBlock.flattened.compactMap(\.paragraph) }

  var artworkText: [String] { everyBlock.compactMap(\.preformatted).map(\.text) }

  var lists: [ListBlock] { everyBlock.compactMap(\.list) }

  /// What the XML declares as an ID: every section's anchor and every bibliography entry's.
  var declaredAnchors: [String] {
    allSections.map(\.anchor) + referenceLists.flatMap(\.entries).map(\.anchor)
  }

  var crossReferences: [CrossReference] {
    paragraphs.flatMap { $0.inlines.compactMap(\.crossReference) }
  }

  /// Every citation anywhere the linker runs: headings, the abstract, and prose at any
  /// depth -- lists, definitions, tables, quotes, a reference's annotation -- not only
  /// top-level paragraphs.
  var everyCrossReference: [CrossReference] { proseInlines.compactMap(\.crossReference) }
}
