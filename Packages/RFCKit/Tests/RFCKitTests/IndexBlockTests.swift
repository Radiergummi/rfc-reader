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

  /// Made-up terms in prep's shape: an entry with its own locator and a subentry, a
  /// heading entry with a subentry, and an entry with two locators.
  static let index = IndexBlock(groups: [
    IndexBlock.Group(
      anchor: "rfc.index.u71",
      entries: [
        IndexBlock.Entry(
          term: [.text("gadget")], locators: [locator("gadgets", "Section 3")],
          subentries: [
            IndexBlock.Entry(
              term: [.text("tray")], locators: [locator("gadget-tray", "Section 3.1")])
          ]),
        IndexBlock.Entry(
          term: [.text("Grammar")],
          subentries: [
            IndexBlock.Entry(
              term: [.text("WSP")], locators: [locator("notation", "Section 1.2", primary: true)])
          ]),
      ]),
    IndexBlock.Group(
      anchor: "rfc.index.u87",
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
    #expect(runs.map(\.plainText) == ["gadget", "tray", "Grammar", "WSP", "widget"])
    #expect(runs.flatMap { $0 }.compactMap(\.crossReference).isEmpty)
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

  /// Prep's markup, written by hand with made-up terms: the letters' paragraph, then
  /// per group an anchored empty paragraph and a list holding a `<dl>`. `gadget` has a
  /// locator and heads `tray` after an entry without a term, and `Grammar` has none and
  /// heads `WSP`, as RFC 9110 writes them; `widget`'s own locators sit in a subentry
  /// without a term, as RFC 9051 and 9499 write them, separated by a semicolon, as
  /// prep separates them.
  static let preppedXML = """
    <section anchor="name-index"><name>Index</name>
      <t anchor="rfc.index.index"><xref target="rfc.index.u71" format="none">G</xref> <xref target="rfc.index.u87" format="none">W</xref></t>
      <ul empty="true">
        <li><t anchor="rfc.index.u71"/>
          <ul empty="true"><li><dl>
            <dt>gadget</dt><dd><t><xref target="gadgets" derivedContent="Section 3"/></t></dd>
            <dt/><dd><dl>
              <dt>tray</dt><dd><t><xref target="gadget-tray" derivedContent="Section 3.1"/></t></dd>
            </dl></dd>
            <dt>Grammar</dt><dd/>
            <dt/><dd><dl>
              <dt>WSP</dt><dd><t><strong><em><xref target="notation" derivedContent="Section 1.2"/></em></strong></t></dd>
            </dl></dd>
          </dl></li></ul>
        </li>
        <li><t anchor="rfc.index.u87"/>
          <ul empty="true"><li><dl>
            <dt>widget</dt><dd/>
            <dt/><dd><dl>
              <dt/><dd><t><xref target="widgets" derivedContent="Section 2"/>; <strong><em><xref target="widget-def" derivedContent="Section 2.1"/></em></strong></t></dd>
            </dl></dd>
          </dl></li></ul>
        </li>
      </ul>
    </section>
    """

  /// The index `parse` reads from a document holding `section`, if it reads one.
  static func readIndex(_ section: String) throws -> IndexBlock? {
    let document = try RFCXMLParser.parse(Data("<rfc><middle>\(section)</middle></rfc>".utf8))
    return document.blocks.compactMap(\.index).first
  }

  @Test func `prep's index reads as one block of letter groups of entries`() throws {
    let index = try #require(try Self.readIndex(Self.preppedXML))
    #expect(index == Self.index)
  }

  @Test func `a section of any other shape is not an index`() throws {
    // Each variant must differ from the original, or the replacement found nothing
    // and the check proves nothing.
    let unanchored = Self.preppedXML.replacingOccurrences(
      of: #"<t anchor="rfc.index.index">"#, with: "<t>")
    #expect(unanchored != Self.preppedXML)
    #expect(try Self.readIndex(unanchored) == nil)
    let withProse = Self.preppedXML.replacingOccurrences(
      of: "<dt>gadget</dt><dd><t>", with: "<dt>gadget</dt><dd><t>see <em>also</em> ")
    #expect(withProse != Self.preppedXML)
    #expect(try Self.readIndex(withProse) == nil)
    let extraParagraph = Self.preppedXML.replacingOccurrences(
      of: "<ul empty=\"true\">\n    <li>", with: "<t>A note.</t><ul empty=\"true\">\n    <li>")
    #expect(extraParagraph != Self.preppedXML)
    #expect(try Self.readIndex(extraParagraph) == nil)
    let withWords = Self.preppedXML.replacingOccurrences(
      of: "<dt>gadget</dt><dd><t>", with: "<dt>gadget</dt><dd><t>see also ")
    #expect(withWords != Self.preppedXML)
    #expect(try Self.readIndex(withWords) == nil, "words between locators are not separators")
    let secondList = Self.preppedXML.replacingOccurrences(
      of: "</dl></dd>\n        <dt>Grammar</dt>",
      with: "</dl><dl><dt>lid</dt><dd/></dl></dd>\n        <dt>Grammar</dt>")
    #expect(secondList != Self.preppedXML)
    #expect(try Self.readIndex(secondList) == nil, "an entry holds one list of subentries")
  }

  @Test func `an index is a fixed point of writing and reading`() throws {
    let document = RFCDocument(
      header: DocumentHeader(title: "Indexed"),
      sections: [Section(anchor: "name-index", title: "Index", blocks: [.index(Self.index)])],
      source: .xml)
    let written = RFCXMLSerializer().serialize(document)
    let read = try RFCXMLParser.parse(Data(written.utf8))
    let section = try #require(read.allSections.first { $0.anchor == "name-index" })
    #expect(section.blocks == [.index(Self.index)])
  }

  /// A term names something, so an RFC number in it is part of the name, not a
  /// citation, as in a fetch item named after the format it takes.
  @Test func `an RFC number in a term is not a citation`() throws {
    let xml = Self.preppedXML.replacingOccurrences(
      of: "<dt>gadget</dt>", with: "<dt>RFC1234.LENGTH (widget item)</dt>")
    #expect(xml != Self.preppedXML)
    let index = try #require(try Self.readIndex(xml))
    #expect(index.groups[0].entries[0].term == [.text("RFC1234.LENGTH (widget item)")])
  }
}
