import Foundation
import Testing

@testable import RFCReaderKit

#if canImport(UIKit)
  import UIKit
#else
  import AppKit
#endif

/// Where a requirement band is drawn (#700): behind its sentence's own text, line by
/// line, the lines joined into one shape that rounds only where the sentence starts
/// and ends.
@Suite("Band geometry")
struct BandGeometryTests {
  private struct Laid {
    let text: NSAttributedString
    let lines: [NSTextLineFragment]
    let fragment: NSRange
  }

  /// Hand-made words, not an RFC's: one paragraph laid out at `width`, as one
  /// fragment. Written through `textStorage`, never `attributedString`.
  private func layOut(width: CGFloat) throws -> Laid {
    let words = (0..<60).map { "word\($0)" }.joined(separator: " ")
    let text = NSAttributedString(
      string: words, attributes: [.font: PlatformFont.systemFont(ofSize: 17)])
    let storage = NSTextContentStorage()
    storage.textStorage?.setAttributedString(text)
    let layout = NSTextLayoutManager()
    storage.addTextLayoutManager(layout)
    let container = NSTextContainer(size: CGSize(width: width, height: 100_000))
    container.lineFragmentPadding = 0
    layout.textContainer = container
    layout.ensureLayout(for: layout.documentRange)
    var lines: [NSTextLineFragment] = []
    layout.enumerateTextLayoutFragments(from: layout.documentRange.location, options: []) {
      lines += $0.textLineFragments
      return false
    }
    withExtendedLifetime(storage) {}
    try #require(lines.count >= 4)
    return Laid(text: text, lines: lines, fragment: NSRange(location: 0, length: text.length))
  }

  @Test func `a band over three lines is a row on each, joined, rounded at its outer corners`()
    throws
  {
    let laid = try layOut(width: 260)
    let first = laid.lines[0].characterRange
    let third = laid.lines[2].characterRange
    // From inside the first line to inside the third.
    let band = NSRange(
      location: first.location + 6, length: third.location + 6 - (first.location + 6))
    let rows = FragmentGeometry.bandRects(
      [band], in: laid.text, lines: laid.lines, fragment: laid.fragment, origin: .zero)
    try #require(rows.count == 3)
    // Only the shape's outer corners: the first row's bottom-left sits on the row
    // under it, and the last row's top-right under the row over it.
    #expect(rows[0].corners == .top)
    #expect(rows[1].corners == [])
    #expect(rows[2].corners == .bottom)
    // Joined: each row's bottom is the next one's top.
    #expect(rows[0].rect.maxY == rows[1].rect.minY)
    #expect(rows[1].rect.maxY == rows[2].rect.minY)
    // The first row starts at the band's first character, not the line's.
    let start =
      laid.lines[0].typographicBounds.minX + laid.lines[0].locationForCharacter(at: band.location).x
    #expect(rows[0].rect.minX == start - FragmentGeometry.chipPadding)
    // The last ends at the band's last, and the middle spans its whole line.
    let end =
      laid.lines[2].typographicBounds.minX
      + laid.lines[2].locationForCharacter(at: NSMaxRange(band)).x
    #expect(rows[2].rect.maxX == end + FragmentGeometry.chipPadding)
    let middle = laid.lines[1]
    #expect(
      rows[1].rect.minX
        == middle.typographicBounds.minX
        + middle.locationForCharacter(at: middle.characterRange.location).x)
  }

  /// A band on one line is a pill, centered on the glyphs as a chip is rather than
  /// on the line box, whose leading is all above.
  @Test func `a band on one line is rounded at both ends and centered on its glyphs`() throws {
    let laid = try layOut(width: 260)
    let line = laid.lines[1]
    let band = NSRange(location: line.characterRange.location + 2, length: 8)
    let rows = FragmentGeometry.bandRects(
      [band], in: laid.text, lines: laid.lines, fragment: laid.fragment, origin: .zero)
    try #require(rows.count == 1)
    #expect(rows[0].corners == [.left, .right])
    let font = PlatformFont.systemFont(ofSize: 17)
    let baseline = line.typographicBounds.minY + line.glyphOrigin.y
    #expect(rows[0].rect.minY == baseline - font.ascender - FragmentGeometry.chipVerticalPadding)
    #expect(rows[0].rect.maxY == baseline - font.descender + FragmentGeometry.chipVerticalPadding)
  }

  @Test func `a band outside the fragment draws nothing`() throws {
    let laid = try layOut(width: 260)
    let band = NSRange(location: laid.text.length + 10, length: 5)
    #expect(
      FragmentGeometry.bandRects(
        [band], in: laid.text, lines: laid.lines, fragment: laid.fragment, origin: .zero
      ).isEmpty)
  }

  @Test func `the rows move with the fragment's origin`() throws {
    let laid = try layOut(width: 260)
    let band = NSRange(location: 3, length: 40)
    let atZero = FragmentGeometry.bandRects(
      [band], in: laid.text, lines: laid.lines, fragment: laid.fragment, origin: .zero)
    let moved = FragmentGeometry.bandRects(
      [band], in: laid.text, lines: laid.lines, fragment: laid.fragment,
      origin: CGPoint(x: 10, y: 20))
    #expect(moved.map(\.rect) == atZero.map { $0.rect.offsetBy(dx: 10, dy: 20) })
  }
}
