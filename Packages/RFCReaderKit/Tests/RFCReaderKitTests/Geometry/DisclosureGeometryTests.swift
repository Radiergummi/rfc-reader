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

  /// The surface the fragment draws in holds the chevron, stroke and all.
  @Test func `the chevron's bounds hold its points`() {
    for open in [false, true] {
      let bounds = FragmentGeometry.disclosureBounds(open: open, firstLine: line)
      for point in FragmentGeometry.disclosureChevron(open: open, firstLine: line) {
        #expect(bounds.insetBy(dx: 1, dy: 1).contains(point))
      }
    }
  }

  /// A click in the gutter finds the heading beside it, on the column's edge; a click
  /// in the column is the text's.
  @Test func `a click in the gutter finds the heading beside it`() {
    #expect(
      FragmentGeometry.disclosureHit(atContainerPoint: CGPoint(x: -12, y: 50))
        == CGPoint(x: 0, y: 50))
    #expect(FragmentGeometry.disclosureHit(atContainerPoint: CGPoint(x: 4, y: 50)) == nil)
  }

  /// The arrow covers exactly what a click toggles: the gutter beside the heading's
  /// fragment, every point of which `disclosureHit` takes to the heading's own height
  /// on the column's edge; nothing of the column.
  @Test func `the arrow's rect is the gutter beside the heading`() {
    let fragment = CGRect(x: 0, y: 200, width: 300, height: 30)
    let origin = CGPoint(x: 120, y: 64)
    let rect = FragmentGeometry.disclosureCursorRect(
      fragmentFrame: fragment, containerOrigin: origin)
    #expect(rect == CGRect(x: 0, y: 264, width: 120, height: 30))
    for point in [
      CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX - 0.5, y: rect.maxY - 0.5),
    ] {
      let container = CGPoint(x: point.x - origin.x, y: point.y - origin.y)
      let hit = FragmentGeometry.disclosureHit(atContainerPoint: container)
      #expect(hit.map { fragment.minY...fragment.maxY ~= $0.y } == true)
    }
    let inColumn = CGPoint(x: origin.x + 1 - origin.x, y: 210)
    #expect(FragmentGeometry.disclosureHit(atContainerPoint: inColumn) == nil)
  }

  /// The chevron fits well inside the gutter's share of the line: smaller than a
  /// third of the line's height across.
  @Test func `the chevron is small beside its heading`() {
    for open in [false, true] {
      let points = FragmentGeometry.disclosureChevron(open: open, firstLine: line)
      let across = points.map(\.x).max()! - points.map(\.x).min()!
      let down = points.map(\.y).max()! - points.map(\.y).min()!
      #expect(max(across, down) < line.height / 3)
    }
  }
}
