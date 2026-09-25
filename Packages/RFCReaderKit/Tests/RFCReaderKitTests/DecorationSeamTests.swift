import CoreGraphics
import Foundation
import Testing
@testable import RFCReaderKit

/// A card's joins land on the device grid, so two translucent fills never share a
/// pixel (#31; the why is on `Placement.snappingJoins`).
///
/// Each case is built the way TextKit draws: absolute fragment frames 29.25pt apart
/// (RFC 9000's line advance), each drawn in its own local space whose origin sits
/// wherever the platform put it — on a device pixel, as NSTextView was measured to,
/// or at a fractional device offset, as nothing promises UITextView will not.
@Suite("Decoration geometry: a card's joins land on the device grid")
struct DecorationSeamTests {
    private func device(scale: CGFloat) -> CGAffineTransform {
        CGAffineTransform(scaleX: scale, y: -scale)
    }

    /// Where a fragment's local space starts, in document coordinates.
    enum LayerOrigin: CaseIterable {
        /// Floored onto the device grid, as measured on NSTextView.
        case onThePixelGrid
        /// A different fraction of a pixel off the grid for every fragment.
        case offTheGrid

        func of(_ y: CGFloat, index: Int, scale: CGFloat) -> CGFloat {
            let aligned = (y * scale).rounded(.down) / scale
            switch self {
            case .onThePixelGrid: return aligned
            case .offTheGrid: return aligned - CGFloat(index + 1) * 0.137 / scale
            }
        }
    }

    /// Four consecutive fragments of one run, as RFC 9000 §17.2 measured.
    private let fragmentTops: [CGFloat] = [74588.5392, 74617.7892, 74647.0392, 74676.2892]
    private let advance: CGFloat = 29.25

    /// Each fragment's card snapped the way its own draw would, back in document
    /// coordinates.
    private func cards(scale: CGFloat, origins: LayerOrigin) -> [CGRect] {
        fragmentTops.enumerated().map { index, y in
            let origin = origins.of(y, index: index, scale: scale)
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
                toDevice: device(scale: scale)
            )
            .offsetBy(dx: 0, dy: origin)
        }
    }

    @Test(arguments: [1, 2, 3] as [CGFloat], LayerOrigin.allCases)
    func consecutiveFragmentsStillTileWithNoGapAndNoOverlap(scale: CGFloat, origins: LayerOrigin) {
        let drawn = cards(scale: scale, origins: origins)
        for (upper, lower) in zip(drawn, drawn.dropFirst()) {
            #expect(abs(upper.maxY - lower.minY) < 1e-6, "a gap or an overlap at the join, at \(scale)x")
        }
    }

    @Test(arguments: [1, 2, 3] as [CGFloat], LayerOrigin.allCases)
    func everyJoinLandsOnAWholeDevicePixel(scale: CGFloat, origins: LayerOrigin) {
        for card in cards(scale: scale, origins: origins).dropLast() {
            let pixels = card.maxY * scale
            #expect(abs(pixels - pixels.rounded()) < 1e-6, "a join inside a pixel is a seam, at \(scale)x")
        }
    }

    /// The run's own top and bottom are rounded, antialiased and shared with
    /// nothing, so they are left exactly where the layout put them.
    @Test(arguments: LayerOrigin.allCases)
    func theRunsOwnEndsAreLeftAlone(origins: LayerOrigin) {
        let drawn = cards(scale: 2, origins: origins)
        #expect(abs((drawn.first?.minY ?? 0) - fragmentTops[0]) < 1e-6)
        #expect(abs((drawn.last?.maxY ?? 0) - (fragmentTops[3] + advance)) < 1e-6)
    }

    @Test(arguments: [1, 2] as [CGFloat], LayerOrigin.allCases)
    func aJoinMovesByAtMostHalfADevicePixel(scale: CGFloat, origins: LayerOrigin) {
        for (index, card) in cards(scale: scale, origins: origins).enumerated().dropLast() {
            let exact = fragmentTops[index] + advance
            #expect(abs(card.maxY - exact) <= 0.5 / scale + 1e-6)
        }
    }

    /// An edge exactly half a pixel off the grid is where two roundings can
    /// disagree. Seen from above (at a positive local offset) and from below (at a
    /// negative one), it must land on the same pixel.
    @Test func aTieRoundsTheSameWayFromBothSides() {
        let transform = device(scale: 2)
        // One absolute edge at 100.25, exactly between the pixels at 100.0 and 100.5.
        let upper = FragmentGeometry.Placement(
            origin: CGPoint(x: 0, y: 0.3), frame: CGRect(x: 0, y: 71, width: 10, height: 29.25), containerWidth: 10, indent: 0
        )
        let lower = FragmentGeometry.Placement(
            origin: CGPoint(x: 0, y: -0.2), frame: CGRect(x: 0, y: 100.25, width: 10, height: 29.25), containerWidth: 10, indent: 0
        )
        let fromAbove = upper.snappingJoins(of: CGRect(x: 0, y: 0.3, width: 10, height: 29.25), top: false, bottom: true, toDevice: transform)
        let fromBelow = lower.snappingJoins(of: CGRect(x: 0, y: -0.2, width: 10, height: 29.25), top: true, bottom: false, toDevice: transform)
        // Back to document coordinates: local + frame.minY - origin.y.
        #expect(abs((fromAbove.maxY + 71 - 0.3) - (fromBelow.minY + 100.25 + 0.2)) < 1e-9)
    }

    @Test func nothingMovesSideways() {
        let placement = FragmentGeometry.Placement(
            origin: CGPoint(x: 13.3, y: 0.2892), frame: CGRect(x: 0, y: 74617.7892, width: 600, height: 29.25), containerWidth: 600, indent: 0
        )
        let rect = CGRect(x: 13.3, y: 0.2892, width: 600.7, height: 29.25)
        let result = placement.snappingJoins(of: rect, top: true, bottom: true, toDevice: device(scale: 2))
        #expect(result.minX == rect.minX)
        #expect(result.width == rect.width)
    }
}
