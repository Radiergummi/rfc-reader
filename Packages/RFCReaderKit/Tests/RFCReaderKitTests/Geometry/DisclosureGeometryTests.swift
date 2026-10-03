import CoreGraphics
import Testing

@testable import RFCReaderKit

/// Where a heading's disclosure chevron is drawn in the outline (#698): in the gutter,
/// left of the column, centered on the heading's first line.
@Suite("Disclosure geometry")
struct DisclosureGeometryTests {
  private let line = CGRect(x: 0, y: 40, width: 300, height: 24)
  /// The heading's text on that line: its baseline, and how tall its capitals are.
  private let text = FragmentGeometry.HeadingText(baseline: 60, capHeight: 12)

  private func chevron(open: Bool, line: CGRect? = nil, text: FragmentGeometry.HeadingText? = nil)
    -> [CGPoint]
  {
    FragmentGeometry.disclosureChevron(
      open: open, firstLine: line ?? self.line, text: text ?? self.text)
  }

  /// Centered on the middle of the heading's capitals, not on the line box, whose
  /// leading puts its middle lower than the text's.
  @Test func `the chevron hangs in the gutter, centered on the heading's capitals`() {
    for open in [false, true] {
      let points = chevron(open: open)
      #expect(points.count == 3)
      #expect(points.allSatisfy { $0.x < line.minX }, "left of the column")
      let heights = points.map(\.y)
      let middle = text.baseline - text.capHeight / 2
      #expect(abs((heights.min()! + heights.max()!) / 2 - middle) < 0.01)
    }
  }

  /// Clear of the text: at least half a capital's height between its tip and the
  /// column, open or closed.
  @Test func `the chevron keeps its distance from the heading`() {
    for open in [false, true] {
      let rightmost = chevron(open: open).map(\.x).max()!
      #expect(line.minX - rightmost >= text.capHeight / 2)
    }
  }

  /// Closed, it points right, at the text; open, it points down, at what it shows.
  @Test func `closed points right and open points down`() {
    let closed = chevron(open: false)
    #expect(closed[1].x > closed[0].x && closed[1].x > closed[2].x)
    let open = chevron(open: true)
    #expect(open[1].y > open[0].y && open[1].y > open[2].y)
  }

  /// It scales with the heading: bigger capitals, a bigger chevron.
  @Test func `the chevron scales with the heading`() {
    let small = chevron(open: false)
    let big = chevron(open: false, text: FragmentGeometry.HeadingText(baseline: 60, capHeight: 24))
    #expect(big[2].y - big[0].y > small[2].y - small[0].y)
  }

  /// The surface the fragment draws in holds the chevron, stroke and all.
  @Test func `the chevron's bounds hold its points`() {
    for open in [false, true] {
      let bounds = FragmentGeometry.disclosureBounds(open: open, firstLine: line, text: text)
      for point in chevron(open: open) {
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

  /// The chevron is smaller than the heading's capitals.
  @Test func `the chevron is small beside its heading`() {
    for open in [false, true] {
      let points = chevron(open: open)
      let across = points.map(\.x).max()! - points.map(\.x).min()!
      let down = points.map(\.y).max()! - points.map(\.y).min()!
      #expect(max(across, down) < text.capHeight)
    }
  }
}
