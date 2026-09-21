import Foundation
import RFCKit
import Testing
@testable import RFCReaderKit
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

@Suite("Builder: artwork")
@MainActor
struct BuilderVerbatimTests {
    private let style = ReadingStyle()

    private func document(_ content: Preformatted) -> RFCDocument {
        Fixtures.document(.preformatted(content))
    }

    @Test func artworkSurvivesLineForLine() {
        let art = "+---+\n| A |\n+---+"
        let built = DocumentTextBuilder.build(document(Preformatted(kind: .artwork, text: art)), style: style)
        for line in art.split(separator: "\n") {
            #expect(built.text.string.contains(line), "lost artwork line: \(line)")
        }
        #expect(built.text.string.contains(art), "artwork must survive as one contiguous block, newlines included")
    }

    @Test func artworkIsMonospacedAndNeverWraps() throws {
        let art = "GET / HTTP/1.1"
        let built = DocumentTextBuilder.build(document(Preformatted(kind: .artwork, text: art)), style: style)
        let offset = try Fixtures.offset(of: art, in: built.text)
        let font = try #require(built.text.attribute(.font, at: offset, effectiveRange: nil) as? PlatformFont)
        let builder = DocumentTextBuilder(style: style)
        let narrow = builder.lineWidth("i", font: font)
        let wide = builder.lineWidth("W", font: font)
        #expect(abs(narrow - wide) < 0.01)

        let paragraph = try #require(built.text.attribute(.paragraphStyle, at: offset, effectiveRange: nil) as? NSParagraphStyle)
        #expect(paragraph.lineBreakMode == .byClipping)
    }

    @Test func artworkCarriesItsDecorationAndItsSource() throws {
        let content = Preformatted(kind: .artwork, text: "x", anchor: "figure-1")
        let built = DocumentTextBuilder.build(document(content), style: style)
        let offset = try #require(built.anchors.offset(of: "figure-1"))
        #expect(RFCDecoration(attributeValue: built.text.attribute(.rfcDecoration, at: offset, effectiveRange: nil)) == .artwork)
        let box = try #require(built.text.attribute(.rfcVerbatim, at: offset, effectiveRange: nil) as? VerbatimBox)
        #expect(box.content.text == "x")
    }

    @Test func narrowArtworkIsNotScaledDown() {
        let builder = DocumentTextBuilder(style: style)
        #expect(builder.monospaceScale(for: "short") == 1)
    }

    @Test func wideArtworkScalesToFitTheMeasure() {
        let builder = DocumentTextBuilder(style: style)
        let wide = String(repeating: "#", count: 129)
        let scale = builder.monospaceScale(for: wide)
        #expect(scale < 1)

        let font = style.monospacedFont(scale: scale)
        let width = builder.lineWidth(wide, font: font)
        #expect(width <= style.measure + 1, "129 columns must fit the measure after scaling")
    }

    @Test func theWidestLineDrivesTheScale() {
        let builder = DocumentTextBuilder(style: style)
        let mixed = "short\n" + String(repeating: "#", count: 120) + "\nshort"
        #expect(builder.monospaceScale(for: mixed) == builder.monospaceScale(for: String(repeating: "#", count: 120)))
    }

    @Test func sourceCodeShowsItsLanguage() {
        let content = Preformatted(kind: .sourceCode, text: "rule = 1*DIGIT", type: "abnf")
        let built = DocumentTextBuilder.build(document(content), style: style)
        #expect(built.text.string.contains("ABNF"))
    }

    /// Artwork is scaled so its widest line fills the measure. Inside the abstract —
    /// which is set smaller than the body — that scaling has to be worked out in the
    /// abstract's own style, not applied on top of a full-size answer.
    ///
    /// Quietening the abstract as a second pass over finished attributes got this
    /// wrong: the block was measured at body size, then shrunk again, so its widest
    /// line came out short of the measure by exactly the abstract's scale.
    @Test func artworkInTheAbstractIsScaledOnceInItsOwnStyle() throws {
        let wide = String(repeating: "#", count: 200)
        let document = RFCDocument(
            header: DocumentHeader(title: "T", abstract: [.preformatted(Preformatted(kind: .artwork, text: wide, anchor: "art"))]),
            sections: [Section(anchor: "section-1", number: "1", title: "S", blocks: [.paragraph(Paragraph(text: "body"))])],
            source: .xml
        )
        let built = DocumentTextBuilder.build(document, style: style)
        let offset = try #require(built.anchors.offset(of: "art"))
        let font = try #require(built.text.attribute(.font, at: offset, effectiveRange: nil) as? PlatformFont)

        let ruler = DocumentTextBuilder(style: style)
        let rendered = ruler.lineWidth(wide, font: font)
        #expect(abs(rendered - style.measure) < 1, "the widest line fills the measure: \(rendered) vs \(style.measure)")
    }
}
