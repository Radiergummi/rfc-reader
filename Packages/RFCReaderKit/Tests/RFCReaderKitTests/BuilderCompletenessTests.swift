import Foundation
import RFCKit
import Testing
@testable import RFCReaderKit
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

@Suite("Builder: completeness")
@MainActor
struct BuilderCompletenessTests {
    private let style = ReadingStyle()

    /// The guard on the central decision. An attachment character outside a chip's
    /// own run means a block kind quietly became a hosted view, which is the hole
    /// in the storage this design exists to avoid; the chip's leading doc.text
    /// symbol is the one sanctioned exception, and only inside its own `.rfcChip` run.
    @Test(arguments: ["rfc8999.xml", "rfc2119.txt"])
    func nothingBecomesAnAttachment(fixture: String) throws {
        let document = fixture.hasSuffix(".xml") ? try Fixtures.rfc8999() : try Fixtures.rfc2119()
        let built = DocumentTextBuilder.build(document, style: style)
        let text = built.text.string
        var searchStart = text.startIndex
        while let found = text.range(of: "\u{FFFC}", range: searchStart..<text.endIndex) {
            let offset = text.distance(from: text.startIndex, to: found.lowerBound)
            #expect(
                built.text.attribute(.rfcChip, at: offset, effectiveRange: nil) != nil,
                "\(fixture) has an attachment character outside a chip run at offset \(offset)"
            )
            searchStart = found.upperBound
        }
    }

    @Test func aFigureContributesArtworkAndACaptionAsText() {
        let figure = Figure(
            title: "Packet layout",
            number: 3,
            blocks: [.preformatted(Preformatted(kind: .artwork, text: "+--+"))],
            anchor: "figure-3"
        )
        let document = RFCDocument(
            header: DocumentHeader(title: "T"),
            sections: [Section(anchor: "section-1", number: "1", title: "S", blocks: [.figure(figure)])],
            source: .xml
        )
        let built = DocumentTextBuilder.build(document, style: style)
        #expect(built.text.string.contains("+--+"))
        #expect(built.text.string.contains("Figure 3: Packet layout"))
        #expect(built.anchors.offset(of: "figure-3") != nil)
    }

    @Test func blockQuotesAndAsidesAreIndentedTextWithADecoration() throws {
        let document = RFCDocument(
            header: DocumentHeader(title: "T"),
            sections: [Section(anchor: "section-1", number: "1", title: "S", blocks: [
                .blockQuote([.paragraph(Paragraph(text: "quoted"))]),
                .aside([.paragraph(Paragraph(text: "noted"))]),
            ])],
            source: .xml
        )
        let built = DocumentTextBuilder.build(document, style: style)

        for (needle, expected) in [("quoted", RFCDecoration.blockQuote), ("noted", RFCDecoration.aside)] {
            let offset = built.text.string.distance(
                from: built.text.string.startIndex,
                to: try #require(built.text.string.range(of: needle)).lowerBound
            )
            #expect(built.text.attribute(.rfcDecoration, at: offset, effectiveRange: nil) as? RFCDecoration == expected)
            let paragraph = built.text.attribute(.paragraphStyle, at: offset, effectiveRange: nil) as? NSParagraphStyle
            #expect((paragraph?.headIndent ?? 0) > 0)
        }
    }

    /// `RFCXMLParser` wraps any unrecognised child element as `.aside(blocks)`, so an
    /// unrecognised element inside a `<blockquote>` nests an aside inside a quote for
    /// real documents, not just hypothetically. The more specific, inner decoration
    /// must survive; the outer one only fills what the inner call left unset.
    @Test func aNestedAsideInsideABlockQuoteKeepsItsOwnDecoration() throws {
        let document = RFCDocument(
            header: DocumentHeader(title: "T"),
            sections: [Section(anchor: "section-1", number: "1", title: "S", blocks: [
                .blockQuote([
                    .paragraph(Paragraph(text: "quoted")),
                    .aside([.paragraph(Paragraph(text: "noted"))]),
                ]),
            ])],
            source: .xml
        )
        let built = DocumentTextBuilder.build(document, style: style)

        for (needle, expected) in [("quoted", RFCDecoration.blockQuote), ("noted", RFCDecoration.aside)] {
            let offset = built.text.string.distance(
                from: built.text.string.startIndex,
                to: try #require(built.text.string.range(of: needle)).lowerBound
            )
            #expect(built.text.attribute(.rfcDecoration, at: offset, effectiveRange: nil) as? RFCDecoration == expected)
        }
    }

    @Test func referenceRowsAreTextWithAnOpenLink() throws {
        let reference = Reference(
            anchor: "RFC9110",
            title: "HTTP Semantics",
            authors: ["R. Fielding", "M. Nottingham", "J. Reschke"],
            date: PublicationDate(year: 2022, month: 6),
            seriesInfo: [(name: "RFC", value: "9110")]
        )
        let document = RFCDocument(
            header: DocumentHeader(title: "T"),
            sections: [Section(anchor: "section-1", number: "1", title: "References", blocks: [
                .references(ReferenceList(title: "Normative References", entries: [reference])),
            ])],
            source: .xml
        )
        let built = DocumentTextBuilder.build(document, style: style)
        #expect(built.text.string.contains("[RFC9110]"))
        #expect(built.text.string.contains("HTTP Semantics"))
        #expect(built.anchors.offset(of: "ref-RFC9110") != nil)

        // The old ReferenceRow reached for @Environment(LibraryModel.self) to open
        // the document; as text it is an rfc:// link the coordinator handles.
        let offset = built.text.string.distance(
            from: built.text.string.startIndex,
            to: try #require(built.text.string.range(of: "[RFC9110]")).lowerBound
        )
        let url = try #require(built.text.attribute(.link, at: offset, effectiveRange: nil) as? URL)
        #expect(url.scheme == "rfc")
    }

    @Test func aReferenceWithOnlyRawTextStillRenders() {
        let reference = Reference(anchor: "OLD", title: "", rawText: "Postel, J., \"TCP\", 1981.")
        let document = RFCDocument(
            header: DocumentHeader(title: "T"),
            sections: [Section(anchor: "section-1", number: "1", title: "References", blocks: [
                .references(ReferenceList(title: "References", entries: [reference])),
            ])],
            source: .text
        )
        let built = DocumentTextBuilder.build(document, style: style)
        #expect(built.text.string.contains("Postel, J., \"TCP\", 1981."))
    }

    @Test func everyAnchorInTheDocumentIsIndexed() throws {
        let document = try Fixtures.rfc8999()
        let built = DocumentTextBuilder.build(document, style: style)

        var expected: Set<String> = []
        func visit(_ blocks: [Block]) {
            for block in blocks {
                switch block {
                case .preformatted(let content): if let anchor = content.anchor { expected.insert(anchor) }
                case .figure(let figure):
                    if let anchor = figure.anchor { expected.insert(anchor) }
                    visit(figure.blocks)
                case .table(let table): if let anchor = table.anchor { expected.insert(anchor) }
                case .list(let list): list.items.forEach { visit($0.blocks) }
                case .definitionList(let items): items.forEach { visit($0.definition) }
                case .blockQuote(let inner), .aside(let inner): visit(inner)
                case .references(let list): list.entries.forEach { expected.insert("ref-\($0.anchor)") }
                case .paragraph(let paragraph): if let anchor = paragraph.anchor { expected.insert(anchor) }
                }
            }
        }
        document.allSections.forEach { expected.insert($0.anchor); visit($0.blocks) }

        for anchor in expected {
            #expect(built.anchors.offset(of: anchor) != nil, "missing anchor \(anchor)")
        }
    }
}
