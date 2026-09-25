import Foundation
import RFCKit
import Testing
@testable import RFCReaderKit

/// What the hover and long-press previews look up under the pointer: the reference,
/// and the whole of its extent, which the macOS popover is anchored to.
@Suite("Reference hit testing")
@MainActor
struct ReferenceHitTests {
    private let chipped = CrossReference(target: .document(.rfc(9110), section: "4.2"))

    /// A chip is three storage runs — the symbol's attachment, the joiner, the
    /// label — so the storage run under the pointer is a third of the reference at
    /// best. The extent is the reference's, from wherever in it the pointer lands.
    @Test func everyCharacterOfAReferenceNamesTheWholeReference() throws {
        let text = Fixtures.inlineRun([.text("See "), .crossReference(chipped), .text(" for more.")])
        let start = try Fixtures.offset(of: "\u{FFFC}", in: text)
        let whole = NSRange(location: start, length: (Self.chipPrefix + chipped.displayLabel).utf16.count)
        for offset in whole.location..<NSMaxRange(whole) {
            let hit = try #require(text.reference(at: offset), "no reference at \(offset)")
            #expect(hit.range == whole, "at \(offset)")
            #expect(hit.box.reference == chipped)
        }
    }

    @Test func twoAdjacentReferencesAreTwoHits() throws {
        let second = CrossReference(target: .document(.rfc(9111), section: nil))
        let text = Fixtures.inlineRun([.crossReference(chipped), .crossReference(second)])
        let boundary = (Self.chipPrefix + chipped.displayLabel).utf16.count
        let first = try #require(text.reference(at: boundary - 1))
        let next = try #require(text.reference(at: boundary))
        #expect(first.range == NSRange(location: 0, length: boundary))
        #expect(next.range == NSRange(location: boundary, length: text.length - boundary))
        #expect(next.box.reference == second)
    }

    @Test func proseAndTheEndOfTheTextAreNoHit() {
        let text = Fixtures.inlineRun([.text("See "), .crossReference(chipped)])
        #expect(text.reference(at: 0) == nil)
        #expect(text.reference(at: text.length) == nil)
        #expect(text.reference(at: -1) == nil)
    }

    private static let chipPrefix = "\u{FFFC}\u{2060}"
}
