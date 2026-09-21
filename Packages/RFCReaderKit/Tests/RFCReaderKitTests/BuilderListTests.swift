import Foundation
import RFCKit
import Testing
@testable import RFCReaderKit
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

@Suite("Builder: lists")
@MainActor
struct BuilderListTests {
    private let style = ReadingStyle()

    @Test func bulletMarkers() {
        #expect(DocumentTextBuilder.marker(for: .bullet, at: 0) == "•")
        #expect(DocumentTextBuilder.marker(for: .bare, at: 3) == "")
    }

    @Test func decimalMarkersRespectTheStart() {
        #expect(DocumentTextBuilder.marker(for: .numbered(format: nil, start: 1), at: 0) == "1.")
        #expect(DocumentTextBuilder.marker(for: .numbered(format: "1", start: 5), at: 2) == "7.")
    }

    @Test func letterAndRomanMarkers() {
        #expect(DocumentTextBuilder.marker(for: .numbered(format: "a", start: 1), at: 0) == "a.")
        #expect(DocumentTextBuilder.marker(for: .numbered(format: "A", start: 1), at: 25) == "Z.")
        #expect(DocumentTextBuilder.marker(for: .numbered(format: "i", start: 1), at: 3) == "iv.")
        #expect(DocumentTextBuilder.marker(for: .numbered(format: "I", start: 1), at: 8) == "IX.")
    }

    @Test func templateMarkers() {
        #expect(DocumentTextBuilder.marker(for: .numbered(format: "(%c)", start: 1), at: 1) == "(b)")
        #expect(DocumentTextBuilder.marker(for: .numbered(format: "%d)", start: 1), at: 2) == "3)")
    }

    @Test func listItemsAppearAsTextWithTheirMarkers() {
        let list = ListBlock(style: .bullet, items: [
            ListItem(text: "first"),
            ListItem(text: "second"),
        ])
        let document = RFCDocument(
            header: DocumentHeader(title: "T"),
            sections: [Section(anchor: "section-1", number: "1", title: "S", blocks: [.list(list)])],
            source: .xml
        )
        let built = DocumentTextBuilder.build(document, style: style)
        #expect(built.text.string.contains("•\tfirst"))
        #expect(built.text.string.contains("•\tsecond"))
    }

    @Test func definitionTermsAreBoldAndDefinitionsAreIndented() throws {
        let item = DefinitionItem(term: [.text("MUST")], definition: [.paragraph(Paragraph(text: "absolute requirement"))])
        let document = RFCDocument(
            header: DocumentHeader(title: "T"),
            sections: [Section(anchor: "section-1", number: "1", title: "S", blocks: [.definitionList([item])])],
            source: .xml
        )
        let built = DocumentTextBuilder.build(document, style: style)
        let termOffset = try #require(built.text.string.range(of: "MUST")).lowerBound
        let offset = built.text.string.distance(from: built.text.string.startIndex, to: termOffset)
        let font = built.text.attribute(.font, at: offset, effectiveRange: nil) as? PlatformFont
        #expect(font?.fontDescriptor.symbolicTraits.contains(RFCTraits.bold) == true)

        let definitionOffset = built.text.string.distance(
            from: built.text.string.startIndex,
            to: try #require(built.text.string.range(of: "absolute requirement")).lowerBound
        )
        let paragraph = built.text.attribute(.paragraphStyle, at: definitionOffset, effectiveRange: nil) as? NSParagraphStyle
        #expect((paragraph?.headIndent ?? 0) > 0)
    }
}
