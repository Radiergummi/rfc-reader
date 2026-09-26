import CoreGraphics
import Foundation
import Testing

@testable import RFCReaderKit

/// A card's joins land on the device grid, so two translucent fills never share a
/// pixel (#31; the why is on `Placement.snappingJoins`).
///
/// Each case is built the way TextKit draws: absolute fragment frames 29.25pt apart
/// (RFC 9000's line advance), each drawn in its own local space. Two things are
/// varied independently, because the old rounding got one of them right only by
/// assuming the other: where the backing store's pixels fall against the document
/// (`LayerGrid` — on whole points, or off them by a scroll offset or a header inset
/// with a fraction in it), and where each fragment's local origin sits on those
/// pixels (`LayerOrigin`). A join is judged in device space, through the same
/// transform the fragment is handed, so the test does not take the grid on trust.
@Suite("Decoration geometry: a card's joins land on the device grid")
struct DecorationSeamTests {
  /// Where the backing store's pixels fall, as the transform from document
  /// coordinates to them: flipped, scaled, and translated by some fraction of a
  /// pixel or none.
  enum LayerGrid: CaseIterable {
    /// Document points land on whole device pixels.
    case onWholePoints
    /// The document is shifted by a fraction of a pixel — a scroll offset or a
    /// header inset like 187.33 — so whole points are not whole pixels.
    case offWholePoints

    func documentToDevice(scale: CGFloat) -> CGAffineTransform {
      let fraction: CGFloat = self == .onWholePoints ? 0 : 0.37
      return CGAffineTransform(
        a: scale, b: 0, c: 0, d: -scale, tx: 0, ty: 200_000 * scale + fraction)
    }
  }

  /// Where a fragment's local space starts, in document coordinates.
  enum LayerOrigin: CaseIterable {
    /// On a device pixel, as measured on NSTextView.
    case onThePixelGrid
    /// A different fraction of a pixel off the grid for every fragment.
    case offTheGrid

    func of(_ y: CGFloat, index: Int, toDevice transform: CGAffineTransform) -> CGFloat {
      let pixel = (y * transform.d + transform.ty).rounded(.down)
      let device = self == .onThePixelGrid ? pixel : pixel + CGFloat(index + 1) * 0.137
      return (device - transform.ty) / transform.d
    }
  }

  /// Four consecutive fragments of one run, as RFC 9000 §17.2 measured.
  private let fragmentTops: [CGFloat] = [74588.5392, 74617.7892, 74647.0392, 74676.2892]
  private let advance: CGFloat = 29.25

  /// Each fragment's card snapped the way its own draw would — handed the device
  /// transform of its own local space — back in document coordinates.
  private func cards(scale: CGFloat, grid: LayerGrid, origins: LayerOrigin) -> [CGRect] {
    let document = grid.documentToDevice(scale: scale)
    return fragmentTops.enumerated().map { index, y in
      let origin = origins.of(y, index: index, toDevice: document)
      let frame = CGRect(x: 0, y: y, width: 600, height: advance)
      let placement = FragmentGeometry.Placement(
        origin: CGPoint(x: 0, y: y - origin),
        frame: frame,
        containerWidth: 600,
        indent: 0
      )
      let local = frame.offsetBy(dx: 0, dy: -origin)
      return placement.snappingJoins(
        of: local,
        top: index != 0,
        bottom: index != fragmentTops.count - 1,
        toDevice: CGAffineTransform(translationX: 0, y: origin).concatenating(document)
      )
      .offsetBy(dx: 0, dy: origin)
    }
  }

  @Test(arguments: [1, 2, 3] as [CGFloat], LayerGrid.allCases)
  func consecutiveFragmentsStillTileWithNoGapAndNoOverlap(scale: CGFloat, grid: LayerGrid) {
    for origins in LayerOrigin.allCases {
      let drawn = cards(scale: scale, grid: grid, origins: origins)
      for (upper, lower) in zip(drawn, drawn.dropFirst()) {
        #expect(
          abs(upper.maxY - lower.minY) < 1e-6,
          "a gap or an overlap at the join, at \(scale)x, \(grid), \(origins)")
      }
    }
  }

  @Test(arguments: [1, 2, 3] as [CGFloat], LayerGrid.allCases)
  func everyJoinLandsOnAWholeDevicePixel(scale: CGFloat, grid: LayerGrid) {
    let document = grid.documentToDevice(scale: scale)
    for origins in LayerOrigin.allCases {
      for card in cards(scale: scale, grid: grid, origins: origins).dropLast() {
        let pixel = CGPoint(x: 0, y: card.maxY).applying(document).y
        #expect(
          abs(pixel - pixel.rounded()) < 1e-6,
          "a join inside a pixel is a seam, at \(scale)x, \(grid), \(origins)")
      }
    }
  }

  /// The run's own top and bottom are rounded, antialiased and shared with
  /// nothing, so they are left exactly where the layout put them.
  @Test(arguments: LayerGrid.allCases, LayerOrigin.allCases)
  func theRunsOwnEndsAreLeftAlone(grid: LayerGrid, origins: LayerOrigin) {
    let drawn = cards(scale: 2, grid: grid, origins: origins)
    #expect(abs((drawn.first?.minY ?? 0) - fragmentTops[0]) < 1e-6)
    #expect(abs((drawn.last?.maxY ?? 0) - (fragmentTops[3] + advance)) < 1e-6)
  }

  @Test(arguments: [1, 2] as [CGFloat], LayerGrid.allCases)
  func aJoinMovesByAtMostHalfADevicePixel(scale: CGFloat, grid: LayerGrid) {
    for origins in LayerOrigin.allCases {
      let drawn = cards(scale: scale, grid: grid, origins: origins)
      for (index, card) in drawn.enumerated().dropLast() {
        let exact = fragmentTops[index] + advance
        #expect(abs(card.maxY - exact) <= 0.5 / scale + 1e-6)
      }
    }
  }

  /// An edge exactly half a pixel off the grid is where two roundings can
  /// disagree. Seen from above (at a positive local offset) and from below (at a
  /// negative one), it must land on the same pixel.
  @Test func aTieRoundsTheSameWayFromBothSides() {
    let document = CGAffineTransform(a: 2, b: 0, c: 0, d: -2, tx: 0, ty: 1000)
    // One absolute edge at 100.25, exactly between the pixels at 100.0 and 100.5.
    let upper = FragmentGeometry.Placement(
      origin: CGPoint(x: 0, y: 0.3), frame: CGRect(x: 0, y: 71, width: 10, height: 29.25),
      containerWidth: 10, indent: 0
    )
    let lower = FragmentGeometry.Placement(
      origin: CGPoint(x: 0, y: -0.2), frame: CGRect(x: 0, y: 100.25, width: 10, height: 29.25),
      containerWidth: 10, indent: 0
    )
    // Each local space starts at frame.minY - origin.y in the document.
    let fromAbove = upper.snappingJoins(
      of: CGRect(x: 0, y: 0.3, width: 10, height: 29.25), top: false, bottom: true,
      toDevice: CGAffineTransform(translationX: 0, y: 71 - 0.3).concatenating(document)
    )
    let fromBelow = lower.snappingJoins(
      of: CGRect(x: 0, y: -0.2, width: 10, height: 29.25), top: true, bottom: false,
      toDevice: CGAffineTransform(translationX: 0, y: 100.25 + 0.2).concatenating(document)
    )
    #expect(abs((fromAbove.maxY + 71 - 0.3) - (fromBelow.minY + 100.25 + 0.2)) < 1e-9)
  }

  @Test func nothingMovesSideways() {
    let placement = FragmentGeometry.Placement(
      origin: CGPoint(x: 13.3, y: 0.2892),
      frame: CGRect(x: 0, y: 74617.7892, width: 600, height: 29.25), containerWidth: 600, indent: 0
    )
    let rect = CGRect(x: 13.3, y: 0.2892, width: 600.7, height: 29.25)
    let result = placement.snappingJoins(
      of: rect, top: true, bottom: true, toDevice: CGAffineTransform(scaleX: 2, y: -2))
    #expect(result.minX == rect.minX)
    #expect(result.width == rect.width)
  }
}
