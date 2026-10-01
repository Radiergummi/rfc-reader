import Foundation
import Testing

@testable import RFCKit

@Suite("RFCXML v3 parser")
struct RFCXMLParserTests {
  static func document() throws -> RFCDocument {
    try Fixtures.document("rfc8999.xml")
  }

  @Test func `header`() throws {
    let document = try Self.document()
    #expect(document.source == .xml)
    #expect(document.header.id == .rfc(8999))
    #expect(document.header.title == "Version-Independent Properties of QUIC")
    #expect(document.header.abbreviatedTitle == "QUIC Invariants")
    #expect(
      document.header.authors == [
        Author(
          name: "Martin Thomson",
          contact: AuthorContact(organization: "Mozilla", emails: ["mt@lowentropy.net"]))
      ])
    #expect(document.header.date == PublicationDate(year: 2021, month: 5))
    #expect(document.header.workingGroup == "QUIC")
    #expect(document.header.keywords.count == 7)
    #expect(document.header.category == .standardsTrack)
    #expect(document.header.draftName == "draft-ietf-quic-invariants-13")
    #expect(document.header.abstract.count == 1)
    if case .paragraph(let paragraph) = document.header.abstract[0] {
      #expect(paragraph.plainText.contains("QUIC transport protocol"))
      #expect(!paragraph.plainText.contains("\n"), "whitespace inside <t> is collapsed")
    } else {
      Issue.record("abstract should be a paragraph")
    }
  }

  @Test func `section tree`() throws {
    let document = try Self.document()
    let top = document.sections
    #expect(top.first?.number == "1")
    #expect(top.first?.titleText == "An Extremely Abstract Description of QUIC")
    #expect(top.first?.anchor == "an-extremely-abstract-description-of-quic")

    let packets = try #require(document.section(number: "5"))
    #expect(packets.titleText == "QUIC Packets")
    #expect(packets.subsections.map(\.number) == ["5.1", "5.2", "5.3", "5.4"])
    #expect(packets.subsections[0].displayTitle == "5.1. Long Header")

    let appendix = try #require(document.section(number: "A"))
    #expect(appendix.isAppendix)
    #expect(appendix.displayTitle == "Appendix A. Incorrect Assumptions")

    let addresses = try #require(document.section(anchor: "authors-addresses"))
    #expect(addresses.number == nil, "numbered=\"false\" sections carry no number")

    // Boilerplate and the pre-rendered table of contents never show up as sections.
    #expect(document.section(anchor: "toc") == nil)
    #expect(document.section(anchor: "status-of-memo") == nil)
  }

  /// Unprepped XML -- a draft, or an RFC before the prep tool ran -- has sections with
  /// neither `anchor` nor `pn`. Their anchors key the table of contents, deep links and
  /// reading positions, so they must be the same on every parse and distinct in one.
  @Test func `an unprepped section's anchor is stable and unique`() throws {
    let xml = """
      <?xml version="1.0" encoding="UTF-8"?>
      <rfc number="9999" version="3">
        <front><title>Unprepped</title></front>
        <middle>
          <section><name>First</name>
            <section><name>Nested</name></section>
          </section>
          <section><name>Second</name></section>
        </middle>
        <back>
          <section><name>Appendix</name></section>
        </back>
      </rfc>
      """
    let first = try RFCXMLParser.parse(Data(xml.utf8))
    let second = try RFCXMLParser.parse(Data(xml.utf8))
    #expect(first == second)
    let anchors = first.allSections.map(\.anchor)
    #expect(anchors.count == 4)
    #expect(Set(anchors).count == anchors.count)
  }

  /// Two anchorless reference lists -- normative and informative, in unprepped XML --
  /// would otherwise share one fallback anchor, and a link to the second would land on
  /// the first.
  @Test func `unprepped reference lists get distinct anchors`() throws {
    let xml = """
      <?xml version="1.0" encoding="UTF-8"?>
      <rfc number="9999" version="3">
        <front><title>Unprepped</title></front>
        <middle><section anchor="intro"><name>Intro</name></section></middle>
        <back>
          <references><name>Normative References</name>
            <reference anchor="A"><front><title>A</title></front></reference>
          </references>
          <references><name>Informative References</name>
            <reference anchor="B"><front><title>B</title></front></reference>
          </references>
        </back>
      </rfc>
      """
    let first = try RFCXMLParser.parse(Data(xml.utf8))
    let second = try RFCXMLParser.parse(Data(xml.utf8))
    #expect(first == second)
    let anchors = first.allSections.map(\.anchor)
    #expect(anchors.count == 3)
    #expect(Set(anchors).count == anchors.count)
  }

  /// The schema puts `<references>` in `<back>` only, but XML from elsewhere, and
  /// legacy conversions made before #315, can hold one in `<middle>` or in a chapter.
  /// A citation into it still resolves, and the one in a chapter reads back as that
  /// chapter's subsection.
  @Test func `a reference list outside the back is read`() throws {
    let xml = """
      <?xml version="1.0" encoding="UTF-8"?>
      <rfc number="9999" version="3">
        <front><title>Misplaced</title></front>
        <middle>
          <section anchor="intro"><name>Intro</name>
            <t>See <xref target="A"/> and <xref target="B"/>.</t>
            <references anchor="intro-refs"><name>Chapter References</name>
              <reference anchor="A"><front><title>A</title></front>
                <seriesInfo name="RFC" value="1111"/></reference>
            </references>
          </section>
          <references anchor="refs"><name>References</name>
            <reference anchor="B"><front><title>B</title></front>
              <seriesInfo name="RFC" value="2222"/></reference>
          </references>
        </middle>
      </rfc>
      """
    let document = try RFCXMLParser.parse(Data(xml.utf8))
    let cited = document.everyCrossReference.compactMap { xref -> DocumentID? in
      if case .document(let id, _, _) = xref.target { id } else { nil }
    }
    #expect(cited == [.rfc(1111), .rfc(2222)])
    let intro = try #require(document.section(anchor: "intro"))
    #expect(intro.subsections.map(\.anchor) == ["intro-refs"])
  }

  @Test func `blocks and inlines`() throws {
    let document = try Self.document()
    let notation = try #require(document.section(number: "4"))

    let definitionLists = notation.blocks.compactMap(\.definitionItems)
    #expect(definitionLists.count == 1)
    #expect(definitionLists[0].count == 4)
    #expect(definitionLists[0][0].term.plainText == "x (A):")

    let figures = notation.blocks.compactMap(\.figure)
    #expect(figures.count == 1)
    #expect(figures[0].title == "Example Format")
    #expect(figures[0].number == 1)
    #expect(figures[0].anchor == "fig-ex-format")
    if case .preformatted(let artwork)? = figures[0].blocks.first {
      #expect(artwork.kind == .artwork)
      #expect(artwork.text.hasPrefix("Example Structure {"))
      #expect(artwork.text.hasSuffix("}"))
    } else {
      Issue.record("figure should contain artwork")
    }

    // A paragraph that starts with an xref to the figure.
    let mentionsFigure = notation.blocks.contains { block in
      guard case .paragraph(let paragraph) = block, let first = paragraph.inlines.first else {
        return false
      }
      if case .crossReference(let xref) = first {
        return xref.target == .anchor("fig-ex-format") && xref.text == "Figure 1"
      }
      return false
    }
    #expect(mentionsFigure)
  }

  @Test func `cross references resolve to RFCs`() throws {
    let document = try Self.document()
    let fixed = try #require(document.section(number: "2"))
    let paragraph = try #require(fixed.blocks.first?.paragraph, "expected a paragraph")
    let xrefs = paragraph.inlines.compactMap(\.crossReference)
    let transport = try #require(xrefs.first)
    #expect(transport.target == .document(.rfc(9000), section: nil, entry: "QUIC-TRANSPORT"))
    #expect(transport.text == "[QUIC-TRANSPORT]")
    #expect(document.referencedDocuments.contains(.rfc(9000)))
    #expect(document.referencedDocuments.contains(.rfc(2119)))
  }

  /// A reference tagged with its canonical number reads as "RFC 2119", and the
  /// space never breaks across a line. A reference the author tagged themselves
  /// ("[QUIC-TRANSPORT]") keeps the name the document uses throughout.
  @Test func `canonical document labels use a non breaking space`() throws {
    let document = try Self.document()
    let xrefs = document.allSections.flatMap(\.blocks).flatMap { block -> [CrossReference] in
      guard case .paragraph(let paragraph) = block else { return [] }
      return paragraph.inlines.compactMap(\.crossReference)
    }

    let bcp14 = try #require(
      xrefs.first { $0.target == .document(.rfc(2119), section: nil, entry: "RFC2119") })
    #expect(bcp14.text == nil, "the series' own spelling is a label to compose, not words to keep")
    #expect(bcp14.label == "[RFC\u{00A0}2119]")

    let transport = try #require(
      xrefs.first { $0.target == .document(.rfc(9000), section: nil, entry: "QUIC-TRANSPORT") })
    #expect(transport.text == "[QUIC-TRANSPORT]", "an author's own reference tag is left alone")
  }

  @Test func `canonical labels are flagged for the renderer`() throws {
    let document = try Self.document()
    let xrefs = document.allSections.flatMap(\.blocks).flatMap { block -> [CrossReference] in
      guard case .paragraph(let paragraph) = block else { return [] }
      return paragraph.inlines.compactMap(\.crossReference)
    }

    let bcp14 = try #require(
      xrefs.first { $0.target == .document(.rfc(2119), section: nil, entry: "RFC2119") })
    #expect(bcp14.isCanonicalLabel, "a canonical series id may be restyled as a chip")
    #expect(
      bcp14.displayLabel == "RFC\u{00A0}2119", "the brackets are ours, so the reader drops them")
    #expect(bcp14.display.isChip)

    let transport = try #require(
      xrefs.first { $0.target == .document(.rfc(9000), section: nil, entry: "QUIC-TRANSPORT") })
    #expect(!transport.isCanonicalLabel, "an author's own tag must survive verbatim")
    #expect(!transport.display.isChip)
  }

  /// "Section 4.2 of [RFC 9110]" must not break after "Section" either.
  @Test func `section composite labels use non breaking spaces`() throws {
    let xml = """
      <?xml version="1.0" encoding="UTF-8"?>
      <rfc number="9999" version="3">
        <front><title>Composite</title></front>
        <middle>
          <section anchor="intro"><name>Intro</name>
            <t>See <xref target="RFC9110" section="4.2" sectionFormat="of" derivedContent="RFC9110"/>.</t>
          </section>
        </middle>
        <back>
          <references><name>References</name>
            <reference anchor="RFC9110">
              <front><title>HTTP Semantics</title><author surname="Fielding"/><date year="2022"/></front>
              <seriesInfo name="RFC" value="9110"/>
            </reference>
          </references>
        </back>
      </rfc>
      """
    let document = try RFCXMLParser.parse(Data(xml.utf8))
    let intro = try #require(document.section(anchor: "intro"))
    let paragraph = try #require(intro.blocks.first?.paragraph, "expected a paragraph")
    let xref = try #require(
      paragraph.inlines.compactMap(\.crossReference).first)
    #expect(xref.text == nil, "the whole phrasing is ours to compose")
    #expect(xref.label == "Section\u{00A0}4.2 of [RFC\u{00A0}9110]")
  }

  /// XML collapses #x20, #x9, #xD and #xA. U+00A0 is not one of them, and
  /// collapsing it would undo every non-breaking label on a round trip.
  @Test func `non breaking spaces survive whitespace collapsing`() throws {
    let xml = """
      <?xml version="1.0" encoding="UTF-8"?>
      <rfc number="9999" version="3">
        <front><title>Spacing</title></front>
        <middle>
          <section anchor="intro"><name>Intro</name>
            <t>RFC\u{00A0}9110   wraps     as
            one unit.</t>
          </section>
        </middle>
      </rfc>
      """
    let document = try RFCXMLParser.parse(Data(xml.utf8))
    let intro = try #require(document.section(anchor: "intro"))
    let paragraph = try #require(intro.blocks.first?.paragraph, "expected a paragraph")
    #expect(paragraph.plainText == "RFC\u{00A0}9110 wraps as one unit.")
  }

  /// Authored XML marks its citations with `<xref>`, but says "RFC 3986" in prose
  /// whenever the sentence reads better that way -- 160 times in RFC 9293, 30 in
  /// RFC 9110. Only the legacy parser used to linkify those, so the entire
  /// post-8650 range showed them as plain text.
  @Test func `bare RFC mentions in prose are linked`() throws {
    let xml = """
      <rfc number="9999"><front><title>Bare Mentions</title></front>
      <middle><section anchor="s1"><name>Introduction</name>
      <t>This document obsoletes RFC 7230 and updates <xref target="RFC3986"/>.</t>
      <t>See <eref target="https://example.com/x">RFC 2119 elsewhere</eref>, the
      literal <tt>RFC 5234</tt>, and <sourcecode>call(RFC 8259)</sourcecode>.</t>
      <artwork>drawn RFC 1035</artwork>
      </section></middle>
      <back><references><reference anchor="RFC3986"><front><title>URI</title>
      <seriesInfo name="RFC" value="3986"/></front></reference></references></back>
      </rfc>
      """
    let document = try RFCXMLParser.parse(Data(xml.utf8))
    let section = try #require(document.sections.first)

    func xrefs(_ block: Block?) -> [CrossReference] {
      guard case .paragraph(let paragraph)? = block else { return [] }
      return paragraph.inlines.compactMap(\.crossReference)
    }
    #expect(
      xrefs(section.blocks.first).map(\.target) == [
        .document(.rfc(7230), section: nil),
        .document(.rfc(3986), section: nil, entry: "RFC3986"),
      ], "a bare mention links beside an authored xref")

    // A mention already inside a link is not ours to link again, and preformatted
    // text is set as the author typed it.
    #expect(xrefs(section.blocks.dropFirst().first).isEmpty)
    #expect(document.referencedDocuments.contains(.rfc(7230)))
    #expect(!document.referencedDocuments.contains(.rfc(2119)))
    #expect(!document.referencedDocuments.contains(.rfc(5234)))
    #expect(!document.referencedDocuments.contains(.rfc(8259)))
    #expect(!document.referencedDocuments.contains(.rfc(1035)))
  }

  @Test func `references`() throws {
    let document = try Self.document()
    let references = try #require(document.sections.first { $0.titleText == "References" })
    #expect(references.number == "8")
    #expect(
      references.subsections.map(\.titleText) == ["Normative References", "Informative References"])
    let normative = try #require(
      references.subsections[0].blocks.first?.references, "expected a reference list")
    #expect(normative.entries.map(\.anchor) == ["RFC2119", "RFC8174"])
    let bcp = normative.entries[0]
    #expect(bcp.title == "Key words for use in RFCs to Indicate Requirement Levels")
    #expect(bcp.authors == [Author(name: "S. Bradner")])
    #expect(bcp.date == PublicationDate(year: 1997, month: 3))
    #expect(bcp.documentID == .rfc(2119))
    #expect(bcp.url?.absoluteString == "https://www.rfc-editor.org/info/rfc2119")
  }

  static func entries(in name: String) throws -> [Reference] {
    let document = try RFCXMLParser.parse(try Fixtures.data(name))
    return document.allSections.flatMap { section in
      section.blocks.flatMap { block -> [Reference] in
        if case .references(let list) = block { return list.entries }
        return []
      }
    }
  }

  /// RFC 9220 renames two of its references with `<displayreference>`, and its prose
  /// cites them as `[HTTP/2]` and `[HTTP/3]`. The entry has to read the same, or a
  /// reader cannot find the citation in the bibliography -- while the anchor stays
  /// what `<xref target>` points at.
  @Test func `an entry is labeled the way its citations are`() throws {
    let entries = try Self.entries(in: "rfc9220.xml")
    let http2 = try #require(entries.first { $0.anchor == "HTTP2" })
    #expect(http2.displayAnchor == "HTTP/2")
    #expect(entries.first { $0.anchor == "HTTP3" }?.displayAnchor == "HTTP/3")
    #expect(entries.first { $0.anchor == "RFC2119" }?.displayAnchor == "RFC2119")
  }

  /// Our own older conversions declared a numbered entry under its number, and a number
  /// is a position in the list, not an RFC: RFC 1004's `[2]` is the EGP specification.
  /// Neither an entry's anchor nor a group's names a document unless it says which
  /// series, and a citation of one opens nothing it does not name.
  @Test func `a numbered anchor is not the RFC of its number`() throws {
    let xml = """
      <rfc number="1004"><front><title>Numbered</title></front>
      <middle><section anchor="s1"><name>Introduction</name>
      <t>See <xref target="2"/> and <xref target="3"/>, and <xref target="BCP14"/>.</t>
      </section></middle>
      <back><references>
      <reference anchor="2"><front><title>Exterior Gateway Protocol Formal Specification</title></front></reference>
      <referencegroup anchor="3"><reference anchor="x"><front><title>X</title></front></reference></referencegroup>
      <referencegroup anchor="BCP14"><reference anchor="RFC2119"><front><title>Key words</title>
      <seriesInfo name="RFC" value="2119"/></front></reference></referencegroup>
      </references></back>
      </rfc>
      """
    let document = try RFCXMLParser.parse(Data(xml.utf8))
    let entries = document.allSections.flatMap { section in
      section.blocks.flatMap { block -> [Reference] in
        if case .references(let list) = block { return list.entries }
        return []
      }
    }
    #expect(entries.first { $0.anchor == "2" }?.documentID == nil)
    #expect(entries.first { $0.anchor == "3" }?.documentID == nil)
    #expect(
      entries.first { $0.anchor == "BCP14" }?.documentID == DocumentID(series: .bcp, number: 14))
    #expect(!document.referencedDocuments.contains(.rfc(2)))
    #expect(!document.referencedDocuments.contains(.rfc(3)))
    #expect(document.referencedDocuments.contains(DocumentID(series: .bcp, number: 14)))
  }

  /// RFC 8761 sets `symRefs="false"`: its prose cites `[1]`, `[2]`, and nothing in the
  /// bibliography says `BT2020-2` anywhere a reader can see.
  @Test func `numbered references are labeled by number`() throws {
    let entries = try Self.entries(in: "rfc8761.xml")
    #expect(entries.first?.anchor == "BT2020-2")
    #expect(entries.map(\.displayAnchor) == entries.indices.map { String($0 + 1) })
  }

  /// RFC 8761 cites a draft and a codec specification, neither in a series, by the
  /// number the prep tool gives them; it reads "[14]", as the RFC Editor renders it,
  /// not a bare "14" (#275). A link to one of its own tables stays "Table 7".
  @Test func `a citation of an entry outside the series keeps its brackets`() throws {
    let xrefs = try RFCXMLParser.parse(try Fixtures.data("rfc8761.xml")).everyCrossReference
    let draft = try #require(xrefs.first { $0.target == .anchor("I-D.ietf-netvc-testing") })
    #expect(draft.label == "[14]")
    let codec = try #require(xrefs.first { $0.target == .anchor("HEVC") })
    #expect(codec.label == "[6]")
    let table = try #require(xrefs.first { $0.target == .anchor("codec-levels") })
    #expect(table.label == "Table 7")
  }

  /// A citation of a section of such an entry names the section, worded by its
  /// `sectionFormat` as a citation of a section of an RFC is: RFC 9783's "Section
  /// 2.3.3 of [RATS-AR4SI]", and RFC 9290's `bare` citation of the registry's "CBOR
  /// Tags", which is the section alone (#473). In document order: RFC 9783 cites the
  /// whole entry, then a section of it; RFC 9290 cites the registry's section, then
  /// the whole registry.
  @Test(arguments: [
    (
      "rfc9783.xml", "I-D.ietf-rats-ar4si",
      ["[RATS-AR4SI]", "Section\u{00A0}2.3.3 of [RATS-AR4SI]"]
    ),
    ("rfc9290.xml", "IANA.cbor-tags", ["CBOR Tags", "[IANA.cbor-tags]"]),
  ])
  func `a citation of a section of an entry outside the series names the section`(
    fixture: String, entry: String, labels: [String]
  ) throws {
    let document = try RFCXMLParser.parse(try Fixtures.data(fixture))
    let xrefs = document.everyCrossReference.filter { xref in
      switch xref.target {
      case .anchor(let anchor): anchor == entry
      case .entrySection(let cited, _, _, _): cited == entry
      case .document: false
      }
    }
    #expect(xrefs.map(\.label) == labels)
  }

  /// RFC 9842 cites "Section 4.9 of [FETCH]", and the RFC Editor links it to the
  /// section's own page, its `derivedLink`, rather than to the bibliography entry
  /// (#473).
  @Test func `a citation of a section of an entry outside the series links to the section`()
    throws
  {
    let xrefs = try RFCXMLParser.parse(try Fixtures.data("rfc9842.xml")).everyCrossReference
    let page = try #require(URL(string: "https://fetch.spec.whatwg.org/#cors-check"))
    let cors = try #require(
      xrefs.first {
        $0.target == .entrySection(entry: "FETCH", tag: "FETCH", section: "4.9", url: page)
      })
    #expect(cors.label == "Section\u{00A0}4.9 of [FETCH]")
    #expect(cors.display == CrossReference.Display(text: cors.label, isChip: false))
  }

  /// RFC 9220 cites RFC 8441 with `format="title"`, whose `derivedContent` is the
  /// entry's title. A title is not a tag, so it reads as the title, not in brackets.
  @Test func `a citation by title reads as the title, unbracketed`() throws {
    let xrefs = try RFCXMLParser.parse(try Fixtures.data("rfc9220.xml")).everyCrossReference
    let labels = xrefs.filter { $0.target == .document(.rfc(8441), section: nil, entry: "RFC8441") }
      .map(\.label)
    #expect(labels.contains("Bootstrapping WebSockets with HTTP/2"))
    #expect(!labels.contains("[Bootstrapping WebSockets with HTTP/2]"))
  }

  /// `format="none"` asks for the element's own text and nothing else: a citation of
  /// a tagged entry is not bracketed, and an empty one shows nothing, as xml2rfc
  /// renders it, rather than its anchor. No committed fixture has either outside a
  /// table of contents, so the tree is hand-written, in RFCXML's shape, quoted from none.
  @Test func `a citation formatted as none shows only its own text`() throws {
    let xml = """
      <rfc><middle><section anchor="intro"><name>Introduction</name>
        <t>See <xref target="WIDGETS" format="none" derivedContent="">the widget
        protocol</xref>, <xref target="WIDGETS" format="none" derivedContent=""/>,
        <xref target="RFC9999" format="none" derivedContent="">RFC 9999</xref> and
        <xref target="gadgets" format="none" derivedContent=""/>.</t>
      </section>
      <section anchor="gadgets"><name>Gadgets</name><t>Gadgets.</t></section></middle>
      <back><references><name>References</name>
        <reference anchor="WIDGETS"><front><title>Widgets</title></front>
          <seriesInfo name="RFC" value="9998"/></reference>
        <reference anchor="RFC9999"><front><title>Gadgets</title></front>
          <seriesInfo name="RFC" value="9999"/></reference>
      </references></back></rfc>
      """
    let xrefs = RFCXMLParser.crossReferences(in: try XMLTree.parse(Data(xml.utf8)))
    #expect(xrefs.map(\.label) == ["the widget protocol", "", "RFC 9999", ""])
  }

  /// A `derivedLink` without a scheme leads nowhere a click can follow, so the
  /// citation opens the entry instead (#473). In RFCXML's shape, quoted from none.
  @Test func `a section citation without a followable link targets the entry`() throws {
    let xml = """
      <rfc><middle><section anchor="intro"><name>Introduction</name>
        <t>See <xref target="WIDGETS" section="A.2" sectionFormat="of" format="default"
        derivedLink="#widget-parts" derivedContent="WIDGETS"/>.</t>
      </section></middle>
      <back><references><name>References</name>
        <reference anchor="WIDGETS"><front><title>Widgets</title></front></reference>
      </references></back></rfc>
      """
    let xrefs = RFCXMLParser.crossReferences(in: try XMLTree.parse(Data(xml.utf8)))
    #expect(
      xrefs.map(\.target) == [
        .entrySection(entry: "WIDGETS", tag: "WIDGETS", section: "A.2", url: nil)
      ])
    #expect(xrefs.map(\.label) == ["Appendix\u{00A0}A.2 of [WIDGETS]"])
  }

  /// A `<referencegroup>` is one entry in the bibliography, and its members have none
  /// of their own, so a citation of a member outside the series links to the group's
  /// entry, as a member in the series already does. Hand-written, as no committed
  /// fixture groups an entry outside the series; in RFCXML's shape, quoted from none.
  @Test func `a citation of a group member outside the series links to the group`() throws {
    let xml = """
      <rfc><middle><section anchor="intro"><name>Introduction</name>
        <t>See <xref target="WIDGET-1" format="default" derivedContent="WIDGET-1"/>.</t>
      </section></middle>
      <back><references><name>References</name>
        <referencegroup anchor="WIDGETS">
          <reference anchor="WIDGET-1"><front><title>Widgets, part 1</title></front></reference>
          <reference anchor="WIDGET-2"><front><title>Widgets, part 2</title></front></reference>
        </referencegroup>
      </references></back></rfc>
      """
    let xrefs = RFCXMLParser.crossReferences(in: try XMLTree.parse(Data(xml.utf8)))
    #expect(xrefs.map(\.target) == [.anchor("WIDGETS")])
    #expect(xrefs.map(\.label) == ["[WIDGET-1]"])
  }

  /// RFC 7991 allows more than one `<tbody>`, and RFC 9911 gives each group of
  /// related YANG types its own: six in Table 1, of 6, 2, 5, 11, 2 and 6 rows.
  /// Reading only the first kept the six counters and dropped the rest.
  @Test func `every table body is read`() throws {
    let document = try RFCXMLParser.parse(try Fixtures.data("rfc9911.xml"))
    let tables = document.everyBlock.flattened.compactMap(\.table)
    let table = try #require(tables.first { $0.anchor == "T1" })
    #expect(table.header.count == 1)
    #expect(table.rows.count == 32)
    #expect(table.rows.first?.cells.first?.plainText == "counter32")
    #expect(table.rows[6].cells.first?.plainText == "object-identifier")
    #expect(table.rows.last?.cells.first?.plainText == "yang-identifier")
  }

  /// Every prepped RFC names the draft it was published from as `<link rel="prev">`,
  /// beside the `rel="alternate"` links for its DOI and the series ISSN, which are not
  /// lineage and must not be taken for it.
  @Test func `the draft an RFC came from is read`() throws {
    let document = try RFCXMLParser.parse(try Fixtures.data("rfc9842.xml"))
    #expect(
      document.header.precedingDraft?.absoluteString
        == "https://datatracker.ietf.org/doc/draft-ietf-httpbis-compression-dictionary-19")
  }

  /// RFC 9842 cites two WHATWG living standards and pins each to the commit it was
  /// written against in an `<annotation>`. Without it the entry names only the moving
  /// target.
  @Test func `a reference keeps its annotation`() throws {
    let entries = try Self.entries(in: "rfc9842.xml")
    let fetch = try #require(entries.first { $0.anchor == "FETCH" })
    let snapshot = try #require(
      URL(
        string:
          "https://fetch.spec.whatwg.org/commit-snapshots/5a9680638ebfc2b3b7f4efb2bef0b579a2663951/"
      ))
    #expect(
      fetch.annotation == [
        .text("Commit snapshot: "), .link(snapshot, [.text(snapshot.absoluteString)]),
      ])
    #expect(fetch.rawText == "WHATWG Living Standard", "the annotation is not the refcontent")
    #expect(entries.first { $0.anchor == "RFC8792" }?.annotation == [])
  }

  /// A `<referencegroup>` is one entry, and the schema lets only its members carry an
  /// annotation. No published RFC annotates a grouped member yet -- none from 8650 to
  /// 10050 -- so this is the smallest document that does, rather than a fixture. A
  /// group of one keeps its member's annotation as is; a group of several keeps every
  /// member's, each after the name of the member it belongs to.
  @Test func `a group keeps its members annotations`() throws {
    let xml = """
      <rfc number="9999"><front><title>Grouped</title></front>
      <back><references>
      <referencegroup anchor="BCP14">
      <reference anchor="RFC2119"><front><title>Key words</title>
      <seriesInfo name="RFC" value="2119"/></front><annotation>The original.</annotation></reference>
      <reference anchor="RFC8174"><front><title>Ambiguity</title>
      <seriesInfo name="RFC" value="8174"/></front></reference>
      <reference anchor="LIVING"><front><title>A Living Standard</title></front>
      <annotation>Commit <eref target="https://example.com/abc">abc</eref>.</annotation></reference>
      </referencegroup>
      <referencegroup anchor="STD1"><reference anchor="RFC9999"><front><title>One</title>
      <seriesInfo name="RFC" value="9999"/></front><annotation>Only member.</annotation></reference>
      </referencegroup>
      </references></back>
      </rfc>
      """
    let document = try RFCXMLParser.parse(Data(xml.utf8))
    let entries = document.allSections.flatMap { section in
      section.blocks.flatMap { block -> [Reference] in
        if case .references(let list) = block { return list.entries }
        return []
      }
    }
    let commit = try #require(URL(string: "https://example.com/abc"))
    #expect(
      entries.first { $0.anchor == "BCP14" }?.annotation == [
        .text("RFC 2119: The original."), .lineBreak,
        .text("LIVING: Commit "), .link(commit, [.text("abc")]), .text("."),
      ])
    #expect(entries.first { $0.anchor == "STD1" }?.annotation == [.text("Only member.")])
  }

  /// `rel` is HTML's: space-separated keywords, compared without regard to case.
  @Test func `a link relation is a token list`() {
    #expect(RFCXMLParser.relation("prev", includes: "prev"))
    #expect(RFCXMLParser.relation("Prev", includes: "prev"))
    #expect(RFCXMLParser.relation("alternate  prev", includes: "prev"))
    #expect(RFCXMLParser.relation("\tprev\n", includes: "prev"))
    #expect(!RFCXMLParser.relation("alternate", includes: "prev"))
    #expect(!RFCXMLParser.relation("preview", includes: "prev"))
    #expect(!RFCXMLParser.relation(nil, includes: "prev"))
  }

  /// RFC 9601 sets off the reasoning behind a rule as `<t indent="3">` under the list
  /// that states it. Every other paragraph says `indent="0"`, which is no indent at all.
  @Test func `a paragraph keeps its indent`() throws {
    let document = try RFCXMLParser.parse(try Fixtures.data("rfc9601.xml"))
    let paragraphs = document.nestedParagraphs
    let reasoning = try #require(paragraphs.first { $0.plainText.hasPrefix("Reasoning:") })
    #expect(reasoning.anchor == "section-5-5")
    #expect(reasoning.indent == 3)
    #expect(paragraphs.filter { $0.indent != 0 }.count == 1)
  }

  /// A `<dl>` keeps how RFCXML asks for it to be set (#352): `newline="false"` hangs
  /// each term beside its definition, `spacing="compact"` drops the space between
  /// items. The prepped XML states both on every list, in every combination of the two.
  @Test(arguments: [
    ("rfc8761.xml", "2.1", "normal newline"),
    ("rfc8761.xml", "2.2", "normal hanging"),
    ("rfc9290.xml", "3.1.1", "compact newline"),
    ("rfc9985.xml", "9.1", "compact hanging"),
  ])
  func `a definition list keeps its newline and spacing`(
    fixture: String, section: String, shape: String
  ) throws {
    let document = try RFCXMLParser.parse(try Fixtures.data(fixture))
    let list = try #require(
      document.section(number: section)?.blocks.compactMap(\.definitionList).first)
    #expect(
      "\(list.isCompact ? "compact" : "normal") \(list.hangsTerms ? "hanging" : "newline")" == shape
    )
  }

  /// One that says neither keeps its terms on their own lines, as the converter's
  /// documents from before #352 need: RFCXML's own default would hang them.
  /// RFC 9985 with its `<dl>`s' attributes taken out at run time, as those documents
  /// write them.
  @Test func `a definition list that says nothing sets its terms on their own lines`() throws {
    let xml = String(decoding: try Fixtures.data("rfc9985.xml"), as: UTF8.self)
      .replacing(#" newline="false""#, with: "")
      .replacing(#" spacing="compact""#, with: "")
    let document = try RFCXMLParser.parse(Data(xml.utf8))
    let lists = document.everyBlock.flattened.compactMap(\.definitionList)
    #expect(!lists.isEmpty)
    #expect(lists.allSatisfy { !$0.hangsTerms && !$0.isCompact })
  }

  @Test func `rejects non RFC documents`() {
    #expect(throws: RFCXMLParser.ParseError.self) {
      try RFCXMLParser.parse(Data("<html><body/></html>".utf8))
    }
  }
}
