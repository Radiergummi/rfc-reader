import Foundation
import Testing

@testable import RFCKit

/// A document's index (#173's part 2): the terms prep generates from `<iref>`s, under
/// letters, each with the places that mention it.
@Suite("Index block")
struct IndexBlockTests {
  static func locator(_ anchor: String, _ label: String, primary: Bool = false)
    -> IndexBlock.Locator
  {
    IndexBlock.Locator(
      reference: CrossReference(target: .anchor(anchor), text: label), isPrimary: primary)
  }

  /// Made-up terms in prep's shape: an entry, a heading entry with a subentry, and an
  /// entry with two locators.
  static let index = IndexBlock(groups: [
    IndexBlock.Group(
      label: "G", anchor: "rfc.index.u71",
      entries: [
        IndexBlock.Entry(term: [.text("gadget")], locators: [locator("gadgets", "Section 3")]),
        IndexBlock.Entry(
          term: [.text("Grammar")],
          subentries: [
            IndexBlock.Entry(
              term: [.text("WSP")], locators: [locator("notation", "Section 1.2", primary: true)])
          ]),
      ]),
    IndexBlock.Group(
      label: "W", anchor: "rfc.index.u87",
      entries: [
        IndexBlock.Entry(
          term: [.text("widget")],
          locators: [
            locator("widgets", "Section 2"), locator("widget-def", "Section 2.1", primary: true),
          ])
      ]),
  ])

  @Test func `a group's label is the letter its anchor names by code point`() {
    #expect(IndexBlock.label(ofGroupAnchor: "rfc.index.u65") == "A")
    #expect(IndexBlock.label(ofGroupAnchor: "rfc.index.u49") == "1")
    #expect(IndexBlock.label(ofGroupAnchor: "rfc.index.index") == nil)
    #expect(IndexBlock.label(ofGroupAnchor: "section-1") == nil)
  }

  @Test func `an index's anchors are its own and its groups'`() {
    #expect(
      Block.index(Self.index).anchors == ["rfc.index.index", "rfc.index.u71", "rfc.index.u87"])
    #expect(Block.index(Self.index).nestedBlocks.isEmpty)
  }

  /// An index's mention of a section is not a reference the text makes, so its
  /// locators are not prose, and no walk over the prose counts them.
  @Test func `an index's prose is its terms, not its locators`() {
    let runs = Block.index(Self.index).proseRuns
    #expect(runs.map(\.plainText) == ["gadget", "Grammar", "WSP", "widget"])
    #expect(!runs.flatMap { $0 }.contains { if case .crossReference = $0 { true } else { false } })
  }

  @Test func `a mention in the index is not a backlink`() {
    let document = RFCDocument(
      header: DocumentHeader(title: "Indexed"),
      sections: [
        Section(anchor: "widgets", number: "2", title: "Widgets"),
        Section(
          anchor: "usage", number: "3", title: "Usage",
          blocks: [
            .paragraph(
              Paragraph([.crossReference(CrossReference(target: .anchor("widgets")))]))
          ]),
        Section(anchor: "name-index", title: "Index", blocks: [.index(Self.index)]),
      ],
      source: .xml)
    #expect(Backlinks.within(document)["widgets"] == [Backlink(section: "usage", count: 1)])
  }

  @Test func `the serializer writes an index in prep's shape`() {
    let document = RFCDocument(
      header: DocumentHeader(title: "Indexed"),
      sections: [Section(anchor: "name-index", title: "Index", blocks: [.index(Self.index)])],
      source: .xml)
    let written = RFCXMLSerializer().serialize(document)
    #expect(written.contains(#"<t anchor="rfc.index.index"/>"#))
    #expect(written.contains(#"<t anchor="rfc.index.u71"/>"#))
    #expect(written.contains("<dt>gadget</dt>"))
    #expect(written.contains(#"<t><xref target="gadgets">Section 3</xref></t>"#))
    #expect(
      written.contains(#"<strong><em><xref target="notation">Section 1.2</xref></em></strong>"#))
    #expect(written.contains(#"<xref target="widgets">Section 2</xref>, <strong>"#))
    #expect(written.contains("<dt/>"), "a heading entry's subentries follow an empty term")
  }
}
