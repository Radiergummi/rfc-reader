import Foundation
import RFCKit
import Testing
@testable import RFCReaderKit
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

/// Two cards with nothing between them must not overlap.
///
/// A card caps its run's own first and last fragment with half the padding beyond
/// the fragment's frame. Two blocks that follow each other directly have frames that
/// touch, so the first card's bottom cap and the second's top cap cover the same
/// strip, and two translucent fills stack there with rounded corners cutting in.
///
/// Laid out for real rather than with hand-made frames: whether the frames touch is
/// TextKit's answer, not this suite's.
@Suite("Decoration geometry: adjacent cards do not overlap")
@MainActor
struct AdjacentCardTests {
    private let style = ReadingStyle()

    /// Each decoration run's card, as the fragments that draw it would fill it, in
    /// document coordinates — in document order.
    private func cards(_ document: RFCDocument) -> [(run: NSRange, rect: CGRect)] {
        let text = DocumentTextBuilder.build(document, style: style).text
        let storage = NSTextContentStorage()
        storage.textStorage?.setAttributedString(text)
        let layout = NSTextLayoutManager()
        storage.addTextLayoutManager(layout)
        let container = NSTextContainer(size: CGSize(width: style.measure, height: 0))
        container.lineFragmentPadding = 0
        layout.textContainer = container

        var cards: [(run: NSRange, rect: CGRect)] = []
        layout.enumerateTextLayoutFragments(from: layout.documentRange.location, options: [.ensuresLayout]) { fragment in
            let start = layout.offset(from: layout.documentRange.location, to: fragment.rangeInElement.location)
            let end = layout.offset(from: layout.documentRange.location, to: fragment.rangeInElement.endLocation)
            guard let span = FragmentGeometry.decorationSpan(in: text, fragment: NSRange(location: start, length: end - start)) else {
                return true
            }
            let frame = fragment.layoutFragmentFrame
            let placement = FragmentGeometry.Placement(origin: frame.origin, frame: frame, containerWidth: style.measure, indent: span.indent)
            let rect = placement.cardRect(padding: FragmentGeometry.cardPadding, span: span)
            if let last = cards.last, last.run == span.runRange {
                cards[cards.count - 1].rect = last.rect.union(rect)
            } else {
                cards.append((span.runRange, rect))
            }
            return true
        }
        return cards
    }

    @Test(arguments: [
        // One verbatim block after another: one decoration value, cut by `VerbatimBox`.
        [Block.preformatted(Preformatted(kind: .artwork, text: "AAAA\nAAAA")), .preformatted(Preformatted(kind: .artwork, text: "BBBB"))],
        [Block.preformatted(Preformatted(kind: .artwork, text: "AAAA")), .preformatted(Preformatted(kind: .sourceCode, text: "BBBB", type: "abnf"))],
        // Two different decorations, which were two runs before verbatim blocks were.
        [Block.table(RFCKit.Table(title: nil, number: nil, header: [[[.text("H")]]], rows: [[[.text("r")]]])),
         .preformatted(Preformatted(kind: .artwork, text: "BBBB"))],
    ])
    func adjacentCardsMeetWithAGap(blocks: [Block]) throws {
        let drawn = cards(Fixtures.document(blocks[0], blocks[1]))
        try #require(drawn.count == 2, "two blocks, two cards")
        let upper = drawn[0], lower = drawn[1]
        #expect(NSMaxRange(upper.run) == lower.run.location, "the blocks must be adjacent for this to test anything")
        #expect(upper.rect.maxY < lower.rect.minY, "the cards overlap: \(upper.rect.maxY) past \(lower.rect.minY)")
    }

    /// The gap is taken from the two cards' own frames, not by moving their text:
    /// a card's outer ends still reach past it as before.
    @Test func aCutLeavesTheOuterEndsCapped() throws {
        let drawn = cards(Fixtures.document(
            .preformatted(Preformatted(kind: .artwork, text: "AAAA")),
            .preformatted(Preformatted(kind: .artwork, text: "BBBB"))
        ))
        try #require(drawn.count == 2)
        let alone = cards(Fixtures.document(.preformatted(Preformatted(kind: .artwork, text: "AAAA"))))
        try #require(alone.count == 1)
        #expect(drawn[0].rect.minY == alone[0].rect.minY, "the top of the first card has no neighbour and keeps its cap")
    }

    /// A quote draws a rule, not a card, so artwork inside one is not cut against
    /// it: its card keeps its cap, as it would anywhere else.
    @Test func aQuoteIsNotACardToMeet() throws {
        let built = DocumentTextBuilder.build(Fixtures.document(.blockQuote([
            .paragraph(Paragraph(text: "quoted")),
            .preformatted(Preformatted(kind: .artwork, text: "AAAA")),
        ])), style: style)
        let offset = try Fixtures.offset(of: "AAAA", in: built.text)
        let span = try #require(FragmentGeometry.decorationSpan(in: built.text, fragment: NSRange(location: offset, length: 1)))
        #expect(span.decoration == .artwork)
        #expect(!span.meetsCardAbove)
    }
}
