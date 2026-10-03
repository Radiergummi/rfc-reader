import CoreGraphics
import Testing

@testable import RFCReaderKit

/// Where a heading's disclosure chevron is drawn in the outline (#698): in the gutter,
/// left of the column, centered on the heading's first line.
@Suite("Disclosure geometry")
struct DisclosureGeometryTests {
  private let line = CGRect(x: 0, y: 40, width: 300, height: 24)

  @Test func `the chevron hangs in the gutter, centered on the first line`() {
    for open in [false, true] {
      let points = FragmentGeometry.disclosureChevron(open: open, firstLine: line)
      #expect(points.count == 3)
      #expect(points.allSatisfy { $0.x < line.minX }, "left of the column")
      let heights = points.map(\.y)
      #expect(abs((heights.min()! + heights.max()!) / 2 - line.midY) < 0.5)
    }
  }

  /// Closed, it points right, at the text; open, it points down, at what it shows.
  @Test func `closed points right and open points down`() {
    let closed = FragmentGeometry.disclosureChevron(open: false, firstLine: line)
    #expect(closed[1].x > closed[0].x && closed[1].x > closed[2].x)
    let open = FragmentGeometry.disclosureChevron(open: true, firstLine: line)
    #expect(open[1].y > open[0].y && open[1].y > open[2].y)
  }

  /// It scales with the heading: a bigger line, a bigger chevron.
  @Test func `the chevron scales with the line`() {
    let small = FragmentGeometry.disclosureChevron(open: false, firstLine: line)
    let big = FragmentGeometry.disclosureChevron(
      open: false, firstLine: CGRect(x: 0, y: 40, width: 300, height: 48))
    #expect(big[2].y - big[0].y > small[2].y - small[0].y)
  }
}
