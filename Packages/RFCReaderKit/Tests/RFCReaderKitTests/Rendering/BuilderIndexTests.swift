import Foundation
import RFCKit
import Testing

@testable import RFCReaderKit

/// Until the reader sets an index as one (the design's part 3), it reads as the
/// blocks prep's markup read as: the letters, then each group's terms and locators.
@Suite("Builder: index")
struct BuilderIndexTests {
  private let style = ReadingStyle()

  static func locator(primary: Bool) -> IndexBlock.Locator {
    IndexBlock.Locator(
      reference: CrossReference(target: .anchor("section-1"), text: "Section 1"),
      isPrimary: primary)
  }

  static let index = IndexBlock(groups: [
    IndexBlock.Group(
      anchor: "rfc.index.u67",
      entries: [
        IndexBlock.Entry(term: [.text("cache")], locators: [locator(primary: true)]),
        IndexBlock.Entry(
          term: [.text("Grammar")],
          subentries: [
            IndexBlock.Entry(term: [.text("ALPHA")], locators: [locator(primary: false)])
          ]),
      ])
  ])

  @Test func `an index reads as its letters, terms and locators`() {
    let built = DocumentTextBuilder.build(Fixtures.document(.index(Self.index)), style: style)
    for words in ["cache", "Grammar", "ALPHA", "Section 1"] {
      #expect(built.text.string.contains(words), "\(words)")
    }
  }

  @Test func `the index's anchor and each group's land somewhere`() {
    let built = DocumentTextBuilder.build(Fixtures.document(.index(Self.index)), style: style)
    #expect(built.anchors.offset(of: IndexBlock.anchor) != nil)
    #expect(built.anchors.offset(of: "rfc.index.u67") != nil)
  }

  @Test func `the plain blocks set the primary locator in bold and italic`() {
    let blocks = DocumentTextBuilder.plainBlocks(of: Self.index)
    guard case .definitionList(let list) = blocks[2],
      case .paragraph(let locators) = list.items[0].definition[0]
    else {
      Issue.record("the group's entries are a definition list of locator paragraphs")
      return
    }
    let primary = Inline.crossReference(Self.locator(primary: true).reference)
    #expect(locators.inlines == [.strong([.emphasis([primary])])])
  }
}
