import Foundation
import Testing
@testable import RFCKit

@Suite("RFCXML serializer")
struct RFCXMLSerializerTests {
    /// A structural fingerprint: section tree, block kinds and paragraph text.
    static func signature(_ document: RFCDocument) -> [String] {
        var lines: [String] = []
        func blockKind(_ block: Block) -> String {
            switch block {
            case .paragraph(let p): "P:" + p.plainText
            case .list(let l): "L\(l.items.count):" + l.items.map { $0.blocks.map(blockKind).joined(separator: "|") }.joined(separator: "||")
            case .definitionList(let d): "D\(d.count):" + d.map { $0.term.plainText }.joined(separator: "|")
            case .preformatted(let a): "A:" + a.text
            case .figure(let f): "F:\(f.title ?? "")" + f.blocks.map(blockKind).joined(separator: "|")
            case .table(let t): "T:\(t.header.count)x\(t.rows.count)"
            case .blockQuote(let b): "Q:" + b.map(blockKind).joined(separator: "|")
            case .aside(let b): "S:" + b.map(blockKind).joined(separator: "|")
            case .references(let r): "R:" + r.entries.map { "\($0.anchor)=\($0.documentID?.description ?? "-")" }.joined(separator: ",")
            }
        }
        func visit(_ section: Section, depth: Int) {
            lines.append("\(depth) \(section.anchor) [\(section.number ?? "-")] \(section.isAppendix ? "appendix " : "")\(section.title)")
            for block in section.blocks { lines.append("  " + blockKind(block)) }
            for sub in section.subsections { visit(sub, depth: depth + 1) }
        }
        lines.append("title=\(document.header.title) id=\(document.header.id?.description ?? "-") authors=\(document.header.authors.map(\.name))")
        for block in document.header.abstract { lines.append("abstract " + blockKind(block)) }
        for section in document.sections { visit(section, depth: 1) }
        return lines
    }

    @Test func roundTripsRFCXML() throws {
        let original = try RFCXMLParser.parse(try Fixtures.data("rfc8999.xml"))
        let xml = RFCXMLSerializer().serialize(original)
        let reparsed = try RFCXMLParser.parse(Data(xml.utf8))
        #expect(Self.signature(reparsed) == Self.signature(original))
        #expect(reparsed.referencedDocuments == original.referencedDocuments)
        #expect(reparsed.header.date == original.header.date)
        #expect(reparsed.header.keywords == original.header.keywords)
    }

    @Test func roundTripsLegacyText() throws {
        let parsed = LegacyTextParser.parse(try Fixtures.string("rfc5234.txt"))
        let xml = RFCXMLSerializer(options: .init(
            generatorComment: "test",
            sourceURL: RFCEditorEndpoints.document(.rfc(5234), format: .text)
        )).serialize(parsed)
        let reparsed = try RFCXMLParser.parse(Data(xml.utf8))
        #expect(reparsed.source == .xml)
        #expect(Self.signature(reparsed) == Self.signature(parsed))
        #expect(reparsed.referencedDocuments == parsed.referencedDocuments)
        #expect(reparsed.header.obsoletes == [.rfc(4234)])
        #expect(reparsed.header.category == "Standards Track")
        #expect(xml.contains("<!-- test -->"))
        #expect(xml.contains("rel=\"alternate\""))
    }

    @Test func unresolvedDocumentReferencesSurviveAsLinks() throws {
        // RFC 1149 mentions no other RFC in a references section, so a synthetic one is used.
        let document = RFCDocument(
            header: DocumentHeader(id: .rfc(99999), title: "Test", date: PublicationDate(year: 2030, month: 1)),
            sections: [Section(anchor: "section-1", number: "1", title: "Intro", blocks: [
                .paragraph(Paragraph([
                    .text("See "),
                    .crossReference(CrossReference(target: .document(.rfc(9110), section: "4.2"), text: "Section 4.2 of RFC 9110")),
                    .text(" and "),
                    .link(URL(string: "https://example.com/")!, [.text("example")]),
                    .text(" & <tags>."),
                ])),
            ])],
            source: .text
        )
        let xml = RFCXMLSerializer().serialize(document)
        #expect(xml.contains("&amp; &lt;tags&gt;."))
        let reparsed = try RFCXMLParser.parse(Data(xml.utf8))
        guard case .paragraph(let paragraph)? = reparsed.sections.first?.blocks.first else {
            Issue.record("expected paragraph")
            return
        }
        #expect(paragraph.inlines.contains(.crossReference(CrossReference(target: .document(.rfc(9110), section: "4.2"), text: "Section 4.2 of RFC 9110"))))
        #expect(paragraph.plainText == "See Section 4.2 of RFC 9110 and example & <tags>.")
    }

    @Test func artworkIsPreservedByteForByte() throws {
        let art = "  +---+\n  | a |  <-- & <\n  +---+"
        let document = RFCDocument(
            header: DocumentHeader(title: "Art"),
            sections: [Section(anchor: "s", number: "1", title: "S", blocks: [.preformatted(Preformatted(kind: .artwork, text: art))])],
            source: .text
        )
        let reparsed = try RFCXMLParser.parse(Data(RFCXMLSerializer().serialize(document).utf8))
        guard case .preformatted(let back)? = reparsed.sections.first?.blocks.first else {
            Issue.record("expected artwork")
            return
        }
        #expect(back.text == art)
    }
}
