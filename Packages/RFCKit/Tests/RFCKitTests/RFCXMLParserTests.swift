import Testing
@testable import RFCKit

@Suite("RFCXML v3 parser")
struct RFCXMLParserTests {
    static func document() throws -> RFCDocument {
        try RFCXMLParser.parse(try Fixtures.data("rfc8999.xml"))
    }

    @Test func header() throws {
        let document = try Self.document()
        #expect(document.source == .xml)
        #expect(document.header.id == .rfc(8999))
        #expect(document.header.title == "Version-Independent Properties of QUIC")
        #expect(document.header.abbreviatedTitle == "QUIC Invariants")
        #expect(document.header.authors == [Author(name: "Martin Thomson")])
        #expect(document.header.date == PublicationDate(year: 2021, month: 5))
        #expect(document.header.workingGroup == "QUIC")
        #expect(document.header.keywords.count == 7)
        #expect(document.header.category == "Standards Track")
        #expect(document.header.draftName == "draft-ietf-quic-invariants-13")
        #expect(document.header.abstract.count == 1)
        if case .paragraph(let paragraph) = document.header.abstract[0] {
            #expect(paragraph.plainText.hasPrefix("This document defines the properties"))
            #expect(!paragraph.plainText.contains("\n"), "whitespace inside <t> is collapsed")
        } else {
            Issue.record("abstract should be a paragraph")
        }
    }

    @Test func sectionTree() throws {
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

    @Test func blocksAndInlines() throws {
        let document = try Self.document()
        let notation = try #require(document.section(number: "4"))

        let definitionLists = notation.blocks.compactMap { block -> [DefinitionItem]? in
            if case .definitionList(let items) = block { return items }
            return nil
        }
        #expect(definitionLists.count == 1)
        #expect(definitionLists[0].count == 4)
        #expect(definitionLists[0][0].term.plainText == "x (A):")

        let figures = notation.blocks.compactMap { block -> Figure? in
            if case .figure(let figure) = block { return figure }
            return nil
        }
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
            guard case .paragraph(let paragraph) = block, let first = paragraph.inlines.first else { return false }
            if case .crossReference(let xref) = first {
                return xref.target == .anchor("fig-ex-format") && xref.text == "Figure 1"
            }
            return false
        }
        #expect(mentionsFigure)
    }

    @Test func crossReferencesResolveToRFCs() throws {
        let document = try Self.document()
        let fixed = try #require(document.section(number: "2"))
        guard case .paragraph(let paragraph)? = fixed.blocks.first else {
            Issue.record("expected a paragraph")
            return
        }
        let xrefs = paragraph.inlines.compactMap { inline -> CrossReference? in
            if case .crossReference(let xref) = inline { return xref }
            return nil
        }
        let transport = try #require(xrefs.first)
        #expect(transport.target == .document(.rfc(9000), section: nil))
        #expect(transport.text == "[QUIC-TRANSPORT]")
        #expect(document.referencedDocuments.contains(.rfc(9000)))
        #expect(document.referencedDocuments.contains(.rfc(2119)))
    }

    /// A reference tagged with its canonical number reads as "RFC 2119", and the
    /// space never breaks across a line. A reference the author tagged themselves
    /// ("[QUIC-TRANSPORT]") keeps the name the document uses throughout.
    @Test func canonicalDocumentLabelsUseANonBreakingSpace() throws {
        let document = try Self.document()
        let xrefs = document.allSections.flatMap(\.blocks).flatMap { block -> [CrossReference] in
            guard case .paragraph(let paragraph) = block else { return [] }
            return paragraph.inlines.compactMap { inline in
                if case .crossReference(let xref) = inline { return xref }
                return nil
            }
        }

        let bcp14 = try #require(xrefs.first { $0.target == .document(.rfc(2119), section: nil) })
        #expect(bcp14.text == nil, "the series' own spelling is a label to compose, not words to keep")
        #expect(bcp14.label == "[RFC\u{00A0}2119]")

        let transport = try #require(xrefs.first { $0.target == .document(.rfc(9000), section: nil) })
        #expect(transport.text == "[QUIC-TRANSPORT]", "an author's own reference tag is left alone")
    }

    @Test func canonicalLabelsAreFlaggedForTheRenderer() throws {
        let document = try Self.document()
        let xrefs = document.allSections.flatMap(\.blocks).flatMap { block -> [CrossReference] in
            guard case .paragraph(let paragraph) = block else { return [] }
            return paragraph.inlines.compactMap { inline in
                if case .crossReference(let xref) = inline { return xref }
                return nil
            }
        }

        let bcp14 = try #require(xrefs.first { $0.target == .document(.rfc(2119), section: nil) })
        #expect(bcp14.isCanonicalLabel, "a canonical series id may be restyled as a chip")
        #expect(bcp14.displayLabel == "RFC\u{00A0}2119", "the brackets are ours, so the reader drops them")
        #expect(bcp14.display.chip != nil)

        let transport = try #require(xrefs.first { $0.target == .document(.rfc(9000), section: nil) })
        #expect(!transport.isCanonicalLabel, "an author's own tag must survive verbatim")
    }

    /// "Section 4.2 of [RFC 9110]" must not break after "Section" either.
    @Test func sectionCompositeLabelsUseNonBreakingSpaces() throws {
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
        guard case .paragraph(let paragraph)? = intro.blocks.first else {
            Issue.record("expected a paragraph")
            return
        }
        let xref = try #require(paragraph.inlines.compactMap { inline -> CrossReference? in
            if case .crossReference(let value) = inline { return value }
            return nil
        }.first)
        #expect(xref.text == nil, "the whole phrasing is ours to compose")
        #expect(xref.label == "Section\u{00A0}4.2 of [RFC\u{00A0}9110]")
    }

    /// XML collapses #x20, #x9, #xD and #xA. U+00A0 is not one of them, and
    /// collapsing it would undo every non-breaking label on a round trip.
    @Test func nonBreakingSpacesSurviveWhitespaceCollapsing() throws {
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
        guard case .paragraph(let paragraph)? = intro.blocks.first else {
            Issue.record("expected a paragraph")
            return
        }
        #expect(paragraph.plainText == "RFC\u{00A0}9110 wraps as one unit.")
    }

    /// Authored XML marks its citations with `<xref>`, but says "RFC 3986" in prose
    /// whenever the sentence reads better that way -- 160 times in RFC 9293, 30 in
    /// RFC 9110. Only the legacy parser used to linkify those, so the entire
    /// post-8650 range showed them as plain text.
    @Test func bareRFCMentionsInProseAreLinked() throws {
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
            return paragraph.inlines.compactMap { inline in
                if case .crossReference(let xref) = inline { return xref }
                return nil
            }
        }
        #expect(xrefs(section.blocks.first).map(\.target) == [
            .document(.rfc(7230), section: nil),
            .document(.rfc(3986), section: nil),
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

    @Test func references() throws {
        let document = try Self.document()
        let references = try #require(document.sections.first { $0.titleText == "References" })
        #expect(references.number == "8")
        #expect(references.subsections.map(\.titleText) == ["Normative References", "Informative References"])
        guard case .references(let normative)? = references.subsections[0].blocks.first else {
            Issue.record("expected a reference list")
            return
        }
        #expect(normative.entries.map(\.anchor) == ["RFC2119", "RFC8174"])
        let bcp = normative.entries[0]
        #expect(bcp.title == "Key words for use in RFCs to Indicate Requirement Levels")
        #expect(bcp.authors == ["S. Bradner"])
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
    @Test func anEntryIsLabelledTheWayItsCitationsAre() throws {
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
    @Test func aNumberedAnchorIsNotTheRFCOfItsNumber() throws {
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
        #expect(entries.first { $0.anchor == "BCP14" }?.documentID == DocumentID(series: .bcp, number: 14))
        #expect(!document.referencedDocuments.contains(.rfc(2)))
        #expect(!document.referencedDocuments.contains(.rfc(3)))
        #expect(document.referencedDocuments.contains(DocumentID(series: .bcp, number: 14)))
    }

    /// RFC 8761 sets `symRefs="false"`: its prose cites `[1]`, `[2]`, and nothing in the
    /// bibliography says `BT2020-2` anywhere a reader can see.
    @Test func numberedReferencesAreLabelledByNumber() throws {
        let entries = try Self.entries(in: "rfc8761.xml")
        #expect(entries.first?.anchor == "BT2020-2")
        #expect(entries.map(\.displayAnchor) == entries.indices.map { String($0 + 1) })
    }

    @Test func rejectsNonRFCDocuments() {
        #expect(throws: RFCXMLParser.ParseError.self) {
            try RFCXMLParser.parse(Data("<html><body/></html>".utf8))
        }
    }
}

import Foundation
