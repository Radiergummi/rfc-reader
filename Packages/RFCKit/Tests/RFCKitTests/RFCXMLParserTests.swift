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
        #expect(top.first?.title == "An Extremely Abstract Description of QUIC")
        #expect(top.first?.anchor == "an-extremely-abstract-description-of-quic")

        let packets = try #require(document.section(number: "5"))
        #expect(packets.title == "QUIC Packets")
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

    @Test func references() throws {
        let document = try Self.document()
        let references = try #require(document.sections.first { $0.title == "References" })
        #expect(references.number == "8")
        #expect(references.subsections.map(\.title) == ["Normative References", "Informative References"])
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

    @Test func rejectsNonRFCDocuments() {
        #expect(throws: RFCXMLParser.ParseError.self) {
            try RFCXMLParser.parse(Data("<html><body/></html>".utf8))
        }
    }
}

import Foundation
