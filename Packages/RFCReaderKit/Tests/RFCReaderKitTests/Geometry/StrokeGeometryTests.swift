import Foundation
import RFCKit
import Testing

@testable import RFCReaderKit

#if canImport(UIKit)
  import UIKit
#else
  import AppKit
#endif

@Suite("Stroke geometry")
struct StrokeGeometryTests {
  /// `PacketSamples.hyphenated`'s strokes, from `PacketPresentationTests`.
  private let box: [Stroke] = [
    Stroke(start: GridPoint(x: 7, y: 5), end: GridPoint(x: 71, y: 5), style: .solid),
    Stroke(start: GridPoint(x: 7, y: 13), end: GridPoint(x: 71, y: 13), style: .solid),
    Stroke(start: GridPoint(x: 7, y: 5), end: GridPoint(x: 7, y: 13), style: .solid),
    Stroke(start: GridPoint(x: 71, y: 5), end: GridPoint(x: 71, y: 13), style: .solid),
  ]

  private func segments(line: Int) -> [StrokeGeometry.Segment] {
    StrokeGeometry.segments(
      box, line: line, in: .init(top: 100, height: 20, columnZero: 10, advance: 8))
  }

  private func segment(_ start: (CGFloat, CGFloat), _ end: (CGFloat, CGFloat))
    -> StrokeGeometry.Segment
  {
    StrokeGeometry.Segment(
      start: CGPoint(x: start.0, y: start.1), end: CGPoint(x: end.0, y: end.1), style: .solid)
  }

  @Test func `a field line draws only the verticals the whole height of the line`() {
    #expect(segments(line: 3) == [segment((38, 100), (38, 120)), segment((294, 100), (294, 120))])
  }

  @Test func `a border line draws its rule through the middle and the verticals below it`() {
    #expect(
      segments(line: 2) == [
        segment((38, 110), (294, 110)), segment((38, 110), (38, 120)),
        segment((294, 110), (294, 120)),
      ])
  }

  @Test func `a line outside the grid draws nothing`() {
    #expect(segments(line: 0).isEmpty)
    #expect(segments(line: 7).isEmpty)
  }

  /// Built, laid out and measured as the reader does: in a block quote, so the
  /// block is indented, and at a column narrow enough that it is scaled down.
  @Test func `strokes land on the centers of the characters they hide`() throws {
    let style = ReadingStyle(measure: 220)
    let document = Fixtures.document(
      .blockQuote([.preformatted(Preformatted(kind: .artwork, text: PacketSamples.variable))]))
    let built = DocumentTextBuilder.build(document, style: style)

    let storage = NSTextContentStorage()
    storage.textStorage?.setAttributedString(built.text)
    let layout = NSTextLayoutManager()
    storage.addTextLayoutManager(layout)
    let container = NSTextContainer(size: CGSize(width: style.measure, height: 100_000))
    container.lineFragmentPadding = 0
    layout.textContainer = container
    layout.ensureLayout(for: layout.documentRange)
    defer { withExtendedLifetime(storage) {} }

    var checked = 0
    layout.enumerateTextLayoutFragments(
      from: layout.documentRange.location, options: [.ensuresLayout]
    ) { fragment in
      guard let range = layout.range(of: fragment.rangeInElement),
        let (strokes, line) = StrokeGeometry.line(of: range, in: built.text), line == 3,
        let lineFragment = fragment.textLineFragments.first,
        let font = built.text.attribute(.font, at: range.location, effectiveRange: nil)
          as? PlatformFont
      else { return true }
      let verticals = StrokeGeometry.segments(
        strokes, line: line, in: lineFragment, font: font, origin: .zero
      ).filter { $0.start.x == $0.end.x }
      // Line 3 of the sample holds its delimiters at columns 3, 19 and 35.
      let centers = [3, 19, 35].map { column in
        lineFragment.typographicBounds.minX
          + (lineFragment.locationForCharacter(at: column).x
            + lineFragment.locationForCharacter(at: column + 1).x) / 2
      }
      #expect(verticals.count == 3)
      for (segment, center) in zip(verticals.sorted { $0.start.x < $1.start.x }, centers) {
        #expect(
          abs(segment.start.x - center) < 0.5, "stroke at \(segment.start.x), glyph at \(center)")
      }
      checked += 1
      return true
    }
    #expect(checked == 1)
  }
}
