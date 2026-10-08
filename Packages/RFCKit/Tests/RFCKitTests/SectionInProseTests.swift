import Foundation
import Testing

@testable import RFCKit

/// A section citation written in prose, `Section 6.1 of <xref target="RFC3550"/>`, folds
/// into the `<xref>` after it, as if the author had given it a `section` (#445), in a
/// document the RFC Editor prepped.
@Suite("XML parser: a section named in prose before a citation")
struct SectionInProseTests {
  /// Each paragraph of a hand-written document in RFCXML's shape, by its anchor.
  static func paragraphs() throws -> [String: Paragraph] {
    let xml = """
      <?xml version="1.0" encoding="UTF-8"?>
      <rfc number="9999" version="3" prepTime="2026-01-01T00:00:00">
        <front><title>Sections in prose</title></front>
        <middle>
          <section anchor="intro"><name>Intro</name>
            <t anchor="of">As in Section 6.1 of <xref target="RFC3550"/>, the sender waits.</t>
            <t anchor="in">The timer of Section 3 in
              <xref target="RFC3550"/> applies.</t>
            <t anchor="appendix">The table in Appendix B of <xref target="RFC3550"/> lists them.</t>
            <t anchor="lowercase">Per section 2.4 of <xref target="RFC3550"/>, it stops.</t>
            <t anchor="has-section">Section 9 of <xref target="RFC3550" section="4"/> differs.</t>
            <t anchor="earlier">Section 5 describes <xref target="RFC3550"/> too.</t>
            <t anchor="words">Section 2 of <xref target="RFC3550">the transport spec</xref> says so.</t>
            <t anchor="tag">Section 4 of <xref target="QUIC-T"/> applies.</t>
            <t anchor="entry">Section 3.2 of <xref target="WEB-X"/> applies.</t>
            <t anchor="local">Section 2 of <xref target="intro"/> is here.</t>
          </section>
        </middle>
        <back>
          <references><name>References</name>
            <reference anchor="RFC3550">
              <front><title>A Transport</title><date year="2003"/></front>
              <seriesInfo name="RFC" value="3550"/>
            </reference>
            <reference anchor="QUIC-T">
              <front><title>A Tagged Transport</title><date year="2021"/></front>
              <seriesInfo name="RFC" value="9000"/>
            </reference>
            <reference anchor="WEB-X" target="https://example.com/spec">
              <front><title>A Web Spec</title><date year="2024"/></front>
            </reference>
          </references>
        </back>
      </rfc>
      """
    let document = try RFCXMLParser.parse(Data(xml.utf8))
    let section = try #require(document.section(anchor: "intro"))
    return Dictionary(
      uniqueKeysWithValues: section.blocks.compactMap(\.paragraph).compactMap { paragraph in
        paragraph.anchor.map { ($0, paragraph) }
      })
  }

  static func citation(_ anchor: String) throws -> (Paragraph, CrossReference) {
    let paragraph = try #require(try paragraphs()[anchor])
    let xref = try #require(paragraph.inlines.compactMap(\.crossReference).first)
    return (paragraph, xref)
  }

  /// The words before the citation become part of it: one chip, to the section.
  @Test(arguments: [
    ("of", "6.1", "As in "), ("in", "3", "The timer of "), ("appendix", "B", "The table in "),
    ("lowercase", "2.4", "Per "),
  ])
  func `a section named before a citation is the citation's`(
    anchor: String, section: String, before: String
  ) throws {
    let (paragraph, xref) = try Self.citation(anchor)
    #expect(xref.target == .document(.rfc(3550), section: section, entry: "RFC3550"))
    #expect(xref.text == nil)
    #expect(xref.display.isChip)
    #expect(paragraph.inlines.first == .text(before))
  }

  /// A citation with a section of its own keeps it, and a section named earlier in the
  /// sentence is not the citation's.
  @Test(arguments: ["has-section", "earlier"])
  func `a section that is not the citation's stays in the prose`(anchor: String) throws {
    let (paragraph, xref) = try Self.citation(anchor)
    #expect(paragraph.plainText.hasPrefix("Section "))
    if anchor == "earlier" {
      #expect(xref.target == .document(.rfc(3550), section: nil, entry: "RFC3550"))
    } else {
      #expect(xref.target == .document(.rfc(3550), section: "4", entry: "RFC3550"))
    }
  }

  /// The author's own words stay the citation's, so the prose before them stays too, and
  /// only the target learns the section.
  @Test func `a citation in the author's words keeps the prose and gains the section`() throws {
    let (paragraph, xref) = try Self.citation("words")
    #expect(xref.target == .document(.rfc(3550), section: "2", entry: "RFC3550"))
    #expect(xref.text == "the transport spec")
    #expect(paragraph.plainText.hasPrefix("Section 2 of the transport spec"))
  }

  /// A citation by a document's tag, and one of an entry outside the series, word the
  /// section around the tag, as a `section` attribute would have.
  @Test func `a tagged citation and an entry outside the series take the section too`() throws {
    let (tagged, tag) = try Self.citation("tag")
    #expect(tag.target == .document(.rfc(9000), section: "4", entry: "QUIC-T"))
    #expect(tag.label == "Section\u{00A0}4 of [QUIC-T]")
    #expect(tagged.inlines.first != .text("Section 4 of "))
    let (_, entry) = try Self.citation("entry")
    guard case .entrySection(let anchor, _, let section, _) = entry.target else {
      Issue.record("expected a section of the entry, got \(entry.target)")
      return
    }
    #expect(anchor == "WEB-X")
    #expect(section == "3.2")
  }

  /// XML corpus-build converted from plain text carries no `prepTime`, and its
  /// citations are the legacy parser's reading, which the XML has to read back as.
  @Test func `a converted document's prose is left as it was written`() throws {
    let xml = """
      <rfc number="9999" version="3"><front><title>Converted</title></front>
      <middle><section anchor="s1"><name>One</name>
      <t>As in Section 6.1 of <xref target="RFC3550"/>, it waits.</t>
      </section></middle>
      <back><references><reference anchor="RFC3550"><front><title>A Transport</title></front>
      <seriesInfo name="RFC" value="3550"/></reference></references></back>
      </rfc>
      """
    let document = try RFCXMLParser.parse(Data(xml.utf8))
    let paragraph = try #require(document.sections.first?.blocks.first?.paragraph)
    let xref = try #require(paragraph.inlines.compactMap(\.crossReference).first)
    #expect(xref.target == .document(.rfc(3550), section: nil, entry: "RFC3550"))
    #expect(paragraph.inlines.first == .text("As in Section 6.1 of "))
  }

  /// A place in this document has no sections of another to take.
  @Test func `a citation within the document is left alone`() throws {
    let (paragraph, xref) = try Self.citation("local")
    #expect(xref.target == .anchor("intro"))
    #expect(paragraph.plainText.hasPrefix("Section 2 of "))
  }
}
