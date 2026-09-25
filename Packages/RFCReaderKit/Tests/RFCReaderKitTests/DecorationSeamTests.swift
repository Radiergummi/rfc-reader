import CoreGraphics
import Foundation
import Testing
@testable import RFCReaderKit

/// A multi-line card is one fill per fragment, and the edge two fragments share
/// used to land inside a device pixel: each filled it with partial coverage, and
/// two translucent partial fills compose to less than one whole one, so the card
/// showed a darker 1px band at every line (#31). These pin the join to the device
/// grid.
///
/// Each fragment draws in its own local space, whose origin TextKit puts on a
/// device pixel — measured in RFC 9000 §17.2 at 2x: a fragment at y 74617.7892 draws
/// at local 0.2892, the next at 74647.0392 at local 0.0392, and the context's
/// user-to-device transform is `(2, -2)` with no translation. The helpers here
/// reproduce exactly that: absolute rects, a pixel-aligned local origin per
/// fragment, the flipped device transform.
@Suite("Decoration geometry: a card's joins land on the device grid")
struct DecorationSeamTests {
    private func device(scale: CGFloat) -> CGAffineTransform {
        CGAffineTransform(scaleX: scale, y: -scale)
    }

    /// Where a fragment at `y` gets its local origin: floored onto the device grid.
    private func layerOrigin(of y: CGFloat, scale: CGFloat) -> CGFloat {
        (y * scale).rounded(.down) / scale
    }

    /// Snaps `absolute` the way the fragment drawing at `y` would, and returns the
    /// result in absolute coordinates again.
    private func snapped(_ absolute: CGRect, fragmentAt y: CGFloat, scale: CGFloat, top: Bool, bottom: Bool) -> CGRect {
        let origin = layerOrigin(of: y, scale: scale)
        let local = absolute.offsetBy(dx: 0, dy: -origin)
        return FragmentGeometry.snappingJoins(of: local, top: top, bottom: bottom, toDevice: device(scale: scale))
            .offsetBy(dx: 0, dy: origin)
    }

    /// Four consecutive fragments of one run, 29.25pt apart, as RFC 9000 measured.
    private let fragmentTops: [CGFloat] = [74588.5392, 74617.7892, 74647.0392, 74676.2892]
    private let advance: CGFloat = 29.25

    private func cards(scale: CGFloat) -> [CGRect] {
        fragmentTops.enumerated().map { index, y in
            let isFirst = index == 0
            let isLast = index == fragmentTops.count - 1
            let absolute = CGRect(x: 0, y: y, width: 600, height: advance)
            return snapped(absolute, fragmentAt: y, scale: scale, top: !isFirst, bottom: !isLast)
        }
    }

    @Test(arguments: [1, 2, 3] as [CGFloat])
    func consecutiveFragmentsStillTileWithNoGapAndNoOverlap(scale: CGFloat) {
        let drawn = cards(scale: scale)
        for (upper, lower) in zip(drawn, drawn.dropFirst()) {
            #expect(abs(upper.maxY - lower.minY) < 1e-6, "a gap or an overlap at the join, at \(scale)x")
        }
    }

    @Test(arguments: [1, 2, 3] as [CGFloat])
    func everyJoinLandsOnAWholeDevicePixel(scale: CGFloat) {
        for card in cards(scale: scale).dropLast() {
            let pixels = card.maxY * scale
            #expect(abs(pixels - pixels.rounded()) < 1e-6, "a join inside a pixel is a seam, at \(scale)x")
        }
    }

    /// The run's own top and bottom are rounded, antialiased and shared with
    /// nothing, so they are left exactly where the layout put them.
    @Test func theRunsOwnEndsAreLeftAlone() {
        let drawn = cards(scale: 2)
        #expect(drawn.first?.minY == fragmentTops.first)
        #expect(drawn.last?.maxY == (fragmentTops.last ?? 0) + advance)
    }

    @Test(arguments: [1, 2] as [CGFloat])
    func aJoinMovesByAtMostHalfADevicePixel(scale: CGFloat) {
        for (index, card) in cards(scale: scale).enumerated().dropLast() {
            let exact = fragmentTops[index] + advance
            #expect(abs(card.maxY - exact) <= 0.5 / scale + 1e-6)
        }
    }

    /// An edge exactly half a pixel off the grid is the tie where two ways of
    /// rounding can disagree — and they must not, even when one fragment sees the
    /// edge at a negative local offset and its neighbour at a positive one.
    @Test func aTieRoundsTheSameWayFromBothSides() {
        let transform = device(scale: 2)
        // One absolute edge, seen from two local spaces a whole number of pixels apart.
        let fromAbove = FragmentGeometry.snappingJoins(
            of: CGRect(x: 0, y: 0, width: 10, height: 29.25), top: false, bottom: true, toDevice: transform
        )
        let fromBelow = FragmentGeometry.snappingJoins(
            of: CGRect(x: 0, y: -0.25, width: 10, height: 29.25), top: true, bottom: false, toDevice: transform
        )
        // The upper local space sits 29.5pt (59 pixels) above the lower one.
        #expect(fromAbove.maxY == fromBelow.minY + 29.5)
    }

    @Test func nothingMovesSideways() {
        let rect = CGRect(x: 13.3, y: 0.2892, width: 600.7, height: 29.25)
        let result = FragmentGeometry.snappingJoins(of: rect, top: true, bottom: true, toDevice: device(scale: 2))
        #expect(result.minX == rect.minX)
        #expect(result.width == rect.width)
    }
}
