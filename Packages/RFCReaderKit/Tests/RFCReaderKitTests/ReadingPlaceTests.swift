import Foundation
import Testing
@testable import RFCReaderKit
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

@Suite("Reading place")
struct ReadingPlaceTests {
    private let index = AnchorIndex([
        .init(anchor: "section-1", offset: 100, isSection: true),
        .init(anchor: "section-1-1", offset: 130),
        .init(anchor: "section-2", offset: 400, isSection: true),
    ])

    @Test func recordsTheNearestAnchorOfAnyKindAndTheDistanceIntoIt() {
        // A paragraph anchor, not the section: restoring to the section would put
        // the reader back at its heading, a screenful or more from where they were.
        #expect(ReadingPlace(at: 250, in: index) == ReadingPlace(anchor: "section-1-1", offset: 120))
        #expect(ReadingPlace(at: 400, in: index) == ReadingPlace(anchor: "section-2", offset: 0))
    }

    @Test func roundTripsThroughTheSameIndex() {
        for offset in [0, 99, 100, 129, 130, 250, 399, 400, 480] {
            let place = ReadingPlace(at: offset, in: index)
            #expect(place.documentOffset(in: index, length: 500) == offset)
        }
    }

    @Test func aPlaceAheadOfTheFirstAnchorIsTheDistanceFromTheDocumentStart() {
        #expect(ReadingPlace(at: 40, in: index) == ReadingPlace(anchor: nil, offset: 40))
    }

    @Test func followsItsAnchorToWhereverTheRebuildPutIt() {
        let rebuilt = AnchorIndex([
            .init(anchor: "section-1", offset: 100, isSection: true),
            .init(anchor: "section-1-1", offset: 180),
            .init(anchor: "section-2", offset: 460, isSection: true),
        ])
        #expect(ReadingPlace(anchor: "section-1-1", offset: 120).documentOffset(in: rebuilt, length: 600) == 300)
    }

    @Test func staysInsideItsBlockWhenTheBlockCameBackShorter() {
        // A table re-shaped for a narrower column can hold fewer characters; the
        // place must not spill into whatever follows it.
        let rebuilt = AnchorIndex([
            .init(anchor: "section-1-1", offset: 130),
            .init(anchor: "section-2", offset: 200, isSection: true),
        ])
        #expect(ReadingPlace(anchor: "section-1-1", offset: 120).documentOffset(in: rebuilt, length: 600) == 199)
        #expect(ReadingPlace(anchor: "section-2", offset: 900).documentOffset(in: rebuilt, length: 600) == 599)
    }

    @Test func anAnchorTheRebuildNoLongerHasResolvesToNothing() {
        #expect(ReadingPlace(anchor: "gone", offset: 3).documentOffset(in: index, length: 500) == nil)
    }

    @Test func keepsThePlaceWhileItsLineIsStillAtTheTop() {
        let previous = ReadingPlace(anchor: "section-1-1", offset: 120)
        // The line holding offset 250 after a restore at another column, starting
        // earlier than the place does.
        let line = NSRange(location: 230, length: 60)
        #expect(ReadingPlace.tracking(previous, topLine: line, in: index, length: 500) == previous)
    }

    @Test func movesToTheLinesStartOnceTheReaderReachesAnotherLine() {
        let previous = ReadingPlace(anchor: "section-1-1", offset: 120)
        let next = NSRange(location: 290, length: 60)
        #expect(ReadingPlace.tracking(previous, topLine: next, in: index, length: 500) == ReadingPlace(anchor: "section-1-1", offset: 160))
        #expect(ReadingPlace.tracking(nil, topLine: next, in: index, length: 500) == ReadingPlace(anchor: "section-1-1", offset: 160))
    }

    /// Resizing back and forth — a live resize, rebuilding each time it pauses —
    /// comes back to the line it started on, however the two columns wrap.
    @Test func doesNotWalkBackAcrossRebuildsAtAlternatingColumns() {
        var place = ReadingPlace(anchor: "section-1-1", offset: 120)
        // At the narrow column the line holding 250 starts at 232; at the wide one,
        // at 241 — both earlier than the place itself.
        for line in [NSRange(location: 232, length: 50), NSRange(location: 241, length: 70), NSRange(location: 232, length: 50)] {
            place = ReadingPlace.tracking(place, topLine: line, in: index, length: 500)
        }
        #expect(place == ReadingPlace(anchor: "section-1-1", offset: 120))
    }

    /// The property the reader relies on: the same text is at the top before and
    /// after a resize rebuilds the document at another measure.
    @Test @MainActor
    func findsTheSameTextInADocumentBuiltAtAnotherMeasure() throws {
        let document = try Fixtures.rfc8999()
        let wide = DocumentTextBuilder.build(document, style: ReadingStyle(measure: 712))
        let narrow = DocumentTextBuilder.build(document, style: ReadingStyle(measure: 400))
        let needle = "Only the most significant bit of the first byte"
        let original = try Fixtures.offset(of: needle, in: wide.text) + 7
        let place = ReadingPlace(at: original, in: wide.anchors)
        let restored = try #require(place.documentOffset(in: narrow.anchors, length: narrow.text.length))
        let expected = (wide.text.string as NSString).substring(with: NSRange(location: original, length: 20))
        #expect((narrow.text.string as NSString).substring(with: NSRange(location: restored, length: 20)) == expected)
    }
}

@Suite("Reading place: line geometry")
@MainActor
struct ReadingPlaceLineGeometryTests {
    private struct Paragraph {
        let lines: [NSTextLineFragment]
        let fragmentStart: Int
    }

    /// One paragraph wrapped over many lines, laid out by TextKit 2, starting past
    /// the document's first character so a fragment-relative slip shows.
    private func paragraph() throws -> Paragraph {
        let font = PlatformFont.systemFont(ofSize: 17)
        let prose = (0..<80).map { "word\($0)" }.joined(separator: " ")
        let storage = NSTextContentStorage()
        storage.attributedString = NSAttributedString(string: "Heading\n" + prose, attributes: [.font: font])
        let layout = NSTextLayoutManager()
        storage.addTextLayoutManager(layout)
        let container = NSTextContainer(size: CGSize(width: 300, height: 100_000))
        container.lineFragmentPadding = 0
        layout.textContainer = container
        layout.ensureLayout(for: layout.documentRange)
        var found: Paragraph?
        layout.enumerateTextLayoutFragments(from: layout.documentRange.location, options: [.ensuresLayout]) { fragment in
            let start = layout.offset(of: fragment.rangeInElement.location)
            if start > 0 { found = Paragraph(lines: fragment.textLineFragments, fragmentStart: start) }
            return found == nil
        }
        let paragraph = try #require(found)
        try #require(paragraph.lines.count > 3, "the fixture must wrap")
        return paragraph
    }

    @Test func aPointInsideALineNamesThatLinesCharacters() throws {
        let paragraph = try paragraph()
        for line in paragraph.lines {
            let range = FragmentGeometry.lineRange(at: line.typographicBounds.midY, in: paragraph.lines, fragmentStart: paragraph.fragmentStart)
            #expect(range == NSRange(location: paragraph.fragmentStart + line.characterRange.location, length: line.characterRange.length))
        }
    }

    @Test func aPointAboveTheFirstLineNamesTheFirstLine() throws {
        let paragraph = try paragraph()
        #expect(FragmentGeometry.lineRange(at: -5, in: paragraph.lines, fragmentStart: paragraph.fragmentStart)?.location == paragraph.fragmentStart)
    }

    @Test func anOffsetAnywhereInALineFindsThatLinesTop() throws {
        let paragraph = try paragraph()
        for line in paragraph.lines {
            let middle = paragraph.fragmentStart + line.characterRange.location + line.characterRange.length / 2
            #expect(FragmentGeometry.lineTop(of: middle, in: paragraph.lines, fragmentStart: paragraph.fragmentStart) == line.typographicBounds.minY)
        }
    }

    @Test func theTwoAreInverses() throws {
        let paragraph = try paragraph()
        for line in paragraph.lines {
            let range = try #require(FragmentGeometry.lineRange(at: line.typographicBounds.minY, in: paragraph.lines, fragmentStart: paragraph.fragmentStart))
            #expect(FragmentGeometry.lineTop(of: range.location, in: paragraph.lines, fragmentStart: paragraph.fragmentStart) == line.typographicBounds.minY)
        }
    }
}
