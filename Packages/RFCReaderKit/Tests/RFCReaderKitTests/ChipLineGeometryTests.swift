import Foundation
import Testing
@testable import RFCReaderKit
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

/// Guards Critical Finding 1 from the final whole-branch review:
/// `NSTextLineFragment.locationForCharacter(at:)` takes an index relative to
/// `line.attributedString` — the whole paragraph a layout fragment lays out — not
/// the line. `RFCTextLayoutFragment.chipRects(at:)` (the app-target consumer of
/// this) used to subtract the *line's* own start instead of the *fragment's*,
/// which only gives the right answer on a fragment's first line, where the two
/// bases coincide. Every chip on a later line of a wrapped paragraph drew at the
/// line's left edge instead of behind its reference.
///
/// `RFCTextLayoutFragment` itself lives in the App target, which has no test
/// target of its own (there is no Xcode test bundle in `project.yml`, and adding
/// one is out of scope for this fix). This test cannot call it directly. Instead
/// it reconstructs the identical TextKit 2 object graph headlessly — the same one
/// `chipRects(at:)` walks — and exercises both the wrong (line-relative) and the
/// right (element/fragment-relative) index base against it, the same way the
/// probe behind the whole-branch review's Critical 1/2 findings did.
@Suite("Chip geometry: element-relative line indexing")
@MainActor
struct ChipLineGeometryTests {
    /// A `.rfcChip`-tagged piece that lands in the middle (not the start) of a
    /// line after the first, in a fragment with several wrapped lines — so a
    /// line-relative and a fragment-relative index base disagree.
    private struct ChipOnLaterLine {
        let line: NSTextLineFragment
        let fragmentStart: Int
        let lineStart: Int
        let piece: NSRange
    }

    /// Builds the fixture and returns the first `.rfcChip` piece found starting
    /// strictly inside a line after that line's own start, on a line after the
    /// fragment's first (`characterRange.location > 0`).
    private func chipOnLaterLine() -> ChipOnLaterLine? {
        let font = PlatformFont.systemFont(ofSize: 17)
        var words: [String] = []
        for index in 0..<80 {
            words.append("word\(index)")
            if index % 7 == 3 { words.append("RFC9110") }
        }
        let text = words.joined(separator: " ")
        let attributed = NSMutableAttributedString(string: text, attributes: [.font: font])
        var searchRange = NSRange(location: 0, length: (text as NSString).length)
        while true {
            let found = (text as NSString).range(of: "RFC9110", range: searchRange)
            guard found.location != NSNotFound else { break }
            attributed.addAttribute(.rfcChip, value: true, range: found)
            searchRange = NSRange(location: NSMaxRange(found), length: (text as NSString).length - NSMaxRange(found))
        }

        let storage = NSTextContentStorage()
        storage.attributedString = attributed
        let layout = NSTextLayoutManager()
        storage.addTextLayoutManager(layout)
        let container = NSTextContainer(size: CGSize(width: 300, height: 100_000))
        container.lineFragmentPadding = 0
        layout.textContainer = container
        layout.ensureLayout(for: layout.documentRange)

        var result: ChipOnLaterLine?
        layout.enumerateTextLayoutFragments(from: layout.documentRange.location, options: [.ensuresLayout]) { fragment in
            let fragmentStart = layout.offset(from: layout.documentRange.location, to: fragment.rangeInElement.location)
            for line in fragment.textLineFragments where line.characterRange.location > 0 {
                let lineStart = fragmentStart + line.characterRange.location
                let lineRange = NSRange(location: lineStart, length: line.characterRange.length)
                guard NSMaxRange(lineRange) <= attributed.length else { continue }
                attributed.enumerateAttribute(.rfcChip, in: lineRange) { value, piece, stop in
                    guard value != nil, piece.location > lineStart, result == nil else { return }
                    result = ChipOnLaterLine(line: line, fragmentStart: fragmentStart, lineStart: lineStart, piece: piece)
                    stop.pointee = true
                }
                if result != nil { break }
            }
            return result == nil
        }
        return result
    }

    @Test func chipOnALaterLineIsNotClampedToTheLeftEdge() throws {
        let found = try #require(chipOnLaterLine(), "fixture must wrap a chip onto a line after its fragment's first")

        // The bug: an index relative to the *line's* own start clamps to the left
        // edge for any piece that does not start at that line's first character.
        let buggyIndex = found.piece.location - found.lineStart
        let buggyX = found.line.locationForCharacter(at: buggyIndex).x
        #expect(buggyX == 0, "documents the bug this test guards against — line-relative indexing clamps left")

        // The fix: an index relative to the *fragment's* start (element-relative,
        // which is what `locationForCharacter(at:)` actually expects).
        let fixedIndex = found.piece.location - found.fragmentStart
        let fixedX = found.line.locationForCharacter(at: fixedIndex).x
        #expect(fixedX > 0, "a chip on a later line must not draw at the line's left edge")
    }

    /// Guards Critical Finding 2: `RFCTextViewCoordinator`'s macOS hover hit test
    /// computed `fragmentStart + line.characterRange.location + line.characterIndex(for:)`,
    /// but `characterIndex(for:)` already returns an index relative to the whole
    /// paragraph (the same element-relative convention as `locationForCharacter(at:)`
    /// above), so it already includes `characterRange.location` — adding it again
    /// double-counts and overshoots past the clicked character on any line after
    /// the fragment's first, the same "line vs. element" confusion as Critical 1.
    @Test func characterIndexForPointIsAlreadyElementRelativeNotLineRelative() throws {
        let found = try #require(chipOnLaterLine(), "fixture must wrap a chip onto a line after its fragment's first")

        // A point over the middle of the chip piece, in line-local coordinates.
        let midX = (found.line.locationForCharacter(at: found.piece.location - found.fragmentStart).x
            + found.line.locationForCharacter(at: NSMaxRange(found.piece) - found.fragmentStart).x) / 2
        let point = CGPoint(x: midX, y: found.line.typographicBounds.height / 2)
        let reported = found.line.characterIndex(for: point)

        // The bug: adding `characterRange.location` again overshoots past the end
        // of the line's own text, landing on the wrong (or no) character.
        let doubleCounted = found.line.characterRange.location + reported
        #expect(doubleCounted > NSMaxRange(found.line.characterRange), "documents the bug: double-counting overshoots the line")

        // The fix: `reported` is already element-relative and needs no further
        // offset beyond the fragment's own start in the document.
        let resolved = found.fragmentStart + reported
        #expect(resolved >= found.piece.location && resolved < NSMaxRange(found.piece), "must resolve inside the clicked chip, not past it")
    }
}
