import CoreGraphics
import Testing

@testable import RFCReaderKit

/// Which corners of a decoration round, and the path that rounds only those.
@Suite("Decoration corners")
struct DecorationCornerTests {
  typealias Corners = FragmentGeometry.Corners

  @Test func `a band rounds where its run starts and ends`() {
    #expect(Corners(first: true, last: true) == [.top, .bottom])
    #expect(Corners(first: true, last: false) == .top)
    #expect(Corners(first: false, last: true) == .bottom)
    #expect(Corners(first: false, last: false) == [])
  }

  @Test func `a chip rounds at the ends of its run along the line`() {
    #expect(Corners(leading: true, trailing: true) == [.left, .right])
    #expect(Corners(leading: true, trailing: false) == .left)
    #expect(Corners(leading: false, trailing: true) == .right)
  }

  private let rect = CGRect(x: 0, y: 0, width: 40, height: 20)

  /// Just inside each corner: outside a rounded corner, inside a square one.
  private func corner(_ corner: Corners) -> CGPoint {
    switch corner {
    case .topLeft: CGPoint(x: 0.5, y: 0.5)
    case .topRight: CGPoint(x: 39.5, y: 0.5)
    case .bottomLeft: CGPoint(x: 0.5, y: 19.5)
    default: CGPoint(x: 39.5, y: 19.5)
    }
  }

  @Test(arguments: [
    Corners.topLeft, Corners.topRight, Corners.bottomLeft, Corners.bottomRight,
  ])
  func `only the corners named are rounded`(rounded: Corners) {
    let path = FragmentGeometry.roundedPath(in: rect, cornerRadius: 6, corners: rounded)
    for other in [Corners.topLeft, .topRight, .bottomLeft, .bottomRight] {
      #expect(path.contains(corner(other)) == (other != rounded), "\(other.rawValue)")
    }
    #expect(path.boundingBox == rect)
  }

  /// A radius larger than half the shorter side is cut to it, so the ends of a thin
  /// band are half circles rather than a path that crosses itself.
  @Test func `a radius is no more than half the shorter side`() {
    let thin = CGRect(x: 0, y: 0, width: 40, height: 4)
    let path = FragmentGeometry.roundedPath(in: thin, cornerRadius: 8, corners: [.left, .right])
    #expect(path.contains(CGPoint(x: 0.2, y: 2)))
    #expect(path.contains(CGPoint(x: 20, y: 2)))
    #expect(!path.contains(CGPoint(x: 0.5, y: 0.2)))
    #expect(path.boundingBox == thin)
  }
}
