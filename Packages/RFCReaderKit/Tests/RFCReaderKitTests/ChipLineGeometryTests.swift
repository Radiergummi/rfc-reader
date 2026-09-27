import Foundation
import RFCKit
import Testing

@testable import RFCReaderKit

#if canImport(UIKit)
  import UIKit
#else
  import AppKit
#endif

/// `NSTextLineFragment.locationForCharacter(at:)` and `characterIndex(for:)` are both
/// indexed against `line.attributedString` — the whole paragraph a layout fragment
/// lays out — not the line. Taking those indices relative to the *line* is right only
/// on a fragment's first line, where the two bases coincide, so every hand-trace and
/// every single-line fixture looked correct while wrapped paragraphs drew chips at the
/// left margin and resolved hover to the wrong character.
///
/// These call `FragmentGeometry` directly, which is the code the reader draws and hit
/// tests with. Reinstating either bug fails them.
@Suite("Chip geometry: element-relative line indexing")
@MainActor
struct ChipLineGeometryTests {
  /// A laid-out paragraph wide enough to wrap, with chips scattered through it.
  private struct Fixture {
    let text: NSAttributedString
    let lines: [NSTextLineFragment]
    let fragmentStart: Int
    let fragmentRange: NSRange
    /// A chip piece that starts strictly inside a line *after* the fragment's
    /// first — the only shape where the two index bases disagree.
    let laterLine: NSTextLineFragment
    let laterPiece: NSRange
  }

  /// Lays text out in a container of this width. The storage is returned because
  /// the layout manager holds it weakly. Written through `textStorage`, never
  /// `attributedString`, which discards the backing storage: see CLAUDE.md.
  private func layOut(_ text: NSAttributedString, width: CGFloat) -> (
    NSTextContentStorage, NSTextLayoutManager
  ) {
    let storage = NSTextContentStorage()
    storage.textStorage?.setAttributedString(text)
    let layout = NSTextLayoutManager()
    storage.addTextLayoutManager(layout)
    let container = NSTextContainer(size: CGSize(width: width, height: 100_000))
    container.lineFragmentPadding = 0
    layout.textContainer = container
    layout.ensureLayout(for: layout.documentRange)
    return (storage, layout)
  }

  private func fixture() throws -> Fixture {
    let font = PlatformFont.systemFont(ofSize: 17)
    var words: [String] = []
    for index in 0..<80 {
      words.append("word\(index)")
      if index % 7 == 3 { words.append("RFC9110") }
    }
    let string = words.joined(separator: " ")
    let attributed = NSMutableAttributedString(string: string, attributes: [.font: font])
    var chipID = 0
    var searchRange = NSRange(location: 0, length: (string as NSString).length)
    while true {
      let found = (string as NSString).range(of: "RFC9110", range: searchRange)
      guard found.location != NSNotFound else { break }
      chipID += 1
      attributed.addAttribute(.rfcChip, value: chipID, range: found)
      searchRange = NSRange(
        location: NSMaxRange(found), length: (string as NSString).length - NSMaxRange(found))
    }

    let (storage, layout) = layOut(attributed, width: 300)
    defer { withExtendedLifetime(storage) {} }

    var fixture: Fixture?
    layout.enumerateTextLayoutFragments(
      from: layout.documentRange.location, options: [.ensuresLayout]
    ) { fragment in
      let fragmentStart = layout.offset(of: fragment.rangeInElement.location)
      let fragmentEnd = layout.offset(of: fragment.rangeInElement.endLocation)
      for line in fragment.textLineFragments where line.characterRange.location > 0 {
        let lineStart = fragmentStart + line.characterRange.location
        let lineRange = NSRange(location: lineStart, length: line.characterRange.length)
        guard NSMaxRange(lineRange) <= attributed.length else { continue }
        attributed.enumerateAttribute(.rfcChip, in: lineRange) { value, piece, stop in
          guard value != nil, piece.location > lineStart, fixture == nil else { return }
          fixture = Fixture(
            text: attributed,
            lines: fragment.textLineFragments,
            fragmentStart: fragmentStart,
            fragmentRange: NSRange(location: fragmentStart, length: fragmentEnd - fragmentStart),
            laterLine: line,
            laterPiece: piece
          )
          stop.pointee = true
        }
        if fixture != nil { break }
      }
      return fixture == nil
    }
    return try #require(fixture, "fixture must wrap a chip onto a line after its fragment's first")
  }

  @Test func `a chip on a later line draws behind its own text`() throws {
    let fixture = try fixture()
    let chips = FragmentGeometry.chipRects(
      in: fixture.text,
      lines: fixture.lines,
      fragment: fixture.fragmentRange,
      origin: .zero
    )

    // The chip on the later line, found by the y its own line was laid out at.
    let expectedY = fixture.laterLine.typographicBounds.minY
    let onLaterLine = chips.filter { abs($0.rect.minY - (expectedY + 1)) < 0.5 }
    #expect(!onLaterLine.isEmpty, "the wrapped line's chips must be among the rects")

    // A line-relative index base clamps `locationForCharacter` to 0 for any piece
    // that does not start the line, putting the chip at the left margin.
    for chip in onLaterLine {
      #expect(
        chip.rect.minX > FragmentGeometry.chipPadding,
        "a chip on a later line must not draw at the line's left edge")
    }
  }

  /// A chip is its symbol's attachment, a word joiner and its label, and the
  /// attachment is a storage run of its own. Asked for with `effectiveRange`, the
  /// chip's extent on its first line was that one character, so the first line
  /// rounded its trailing end as if the chip ended there, and a wrapped chip drew
  /// as a whole pill followed by a half one (#122).
  ///
  /// The chip comes from the builder, not a hand-made copy of its recipe: its label
  /// is bound with no-break spaces, so it wraps only where a column is too narrow
  /// to hold it at all, and that is the width it is laid out at here: narrow enough
  /// for three lines, so there is a middle one that rounds neither end.
  @Test func `a wrapped chip rounds only its outer ends`() throws {
    let xref = CrossReference(target: .document(.rfc(9110), section: "4.2"))
    let text = Fixtures.inlineRun([
      .text("As described in "), .crossReference(xref), .text(" and elsewhere."),
    ])

    let (storage, layout) = layOut(text, width: 60)
    defer { withExtendedLifetime(storage) {} }
    var fragment: NSTextLayoutFragment?
    layout.enumerateTextLayoutFragments(
      from: layout.documentRange.location, options: [.ensuresLayout]
    ) {
      fragment = $0
      return false
    }
    let paragraph = try #require(fragment)
    let chips = FragmentGeometry.chipRects(
      in: text,
      lines: paragraph.textLineFragments,
      fragment: NSRange(location: 0, length: text.length),
      origin: .zero
    )
    try #require(chips.count >= 3, "the chip must wrap across three lines to have a middle one")
    #expect(chips.first?.roundsLeading == true)
    #expect(chips.first?.roundsTrailing == false, "the chip goes on past its first line")
    #expect(chips.last?.roundsLeading == false, "the chip began on an earlier line")
    #expect(chips.last?.roundsTrailing == true)
    for middle in chips.dropFirst().dropLast() {
      #expect(!middle.roundsLeading && !middle.roundsTrailing, "a middle line rounds neither end")
    }
  }

  @Test func `every chip rect sits over its own glyphs`() throws {
    let fixture = try fixture()
    let chips = FragmentGeometry.chipRects(
      in: fixture.text,
      lines: fixture.lines,
      fragment: fixture.fragmentRange,
      origin: .zero
    )
    #expect(!chips.isEmpty)
    for chip in chips {
      #expect(chip.rect.width > 0, "a zero-width chip means both ends resolved to the same index")
    }
  }

  @Test func `hit testing resolves inside the chip it points at`() throws {
    let fixture = try fixture()
    let line = fixture.laterLine
    let piece = fixture.laterPiece

    // A point over the middle of the chip, in fragment coordinates.
    let startX = line.locationForCharacter(at: piece.location - fixture.fragmentStart).x
    let endX = line.locationForCharacter(at: NSMaxRange(piece) - fixture.fragmentStart).x
    let point = CGPoint(
      x: line.typographicBounds.minX + (startX + endX) / 2,
      y: line.typographicBounds.midY
    )

    let resolved = try #require(
      FragmentGeometry.characterOffset(
        in: fixture.lines,
        fragmentStart: fixture.fragmentStart,
        at: point
      ))
    #expect(
      resolved >= piece.location && resolved < NSMaxRange(piece),
      "must resolve inside the chip under the pointer, not past it")
  }

  @Test func `a point outside every line resolves to nothing`() throws {
    let fixture = try fixture()
    let below = CGPoint(
      x: 10, y: fixture.lines.map(\.typographicBounds.maxY).max().map { $0 + 100 } ?? 1000)
    #expect(
      FragmentGeometry.characterOffset(
        in: fixture.lines, fragmentStart: fixture.fragmentStart, at: below) == nil)
  }

  /// The empty space right of a heading or a one-line paragraph, and the gutter to
  /// the left of any line, are not over a character. `characterIndex(for:)` answers
  /// `NSNotFound` past a single line's end, and adding a nonzero fragment start to
  /// that trapped: hovering beside any heading below the first line crashed.
  @Test func `a point beside a lines text resolves to nothing`() throws {
    let (storage, layout) = layOut(
      NSAttributedString(
        string: "A first paragraph.\nA heading\n",
        attributes: [.font: PlatformFont.systemFont(ofSize: 17)]),
      width: 600
    )
    defer { withExtendedLifetime(storage) {} }

    var fragments: [NSTextLayoutFragment] = []
    layout.enumerateTextLayoutFragments(
      from: layout.documentRange.location, options: [.ensuresLayout]
    ) { fragment in
      fragments.append(fragment)
      return true
    }
    let heading = try #require(fragments.dropFirst().first)
    let fragmentStart = layout.offset(of: heading.rangeInElement.location)
    #expect(fragmentStart > 0)
    let line = try #require(heading.textLineFragments.first)
    let y = line.typographicBounds.midY
    let right = CGPoint(x: line.typographicBounds.maxX + 50, y: y)
    let left = CGPoint(x: line.typographicBounds.minX - 5, y: y)
    #expect(
      FragmentGeometry.characterOffset(
        in: heading.textLineFragments, fragmentStart: fragmentStart, at: right) == nil)
    #expect(
      FragmentGeometry.characterOffset(
        in: heading.textLineFragments, fragmentStart: fragmentStart, at: left) == nil)
  }
}
