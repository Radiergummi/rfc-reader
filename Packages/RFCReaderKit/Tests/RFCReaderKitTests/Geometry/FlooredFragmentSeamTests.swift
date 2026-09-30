import CoreGraphics
import Foundation
import Testing

@testable import RFCReaderKit

/// A card's joins meet on iOS, where each fragment is drawn a fraction of a pixel
/// from where the layout put it (#273).
///
/// `DecorationSeamTests` covers a text view that draws every fragment exactly where
/// the layout put it, as NSTextView does. UITextView does not. Its fragment view's
/// frame is `UIRectIntegralWithScale` of the fragment's frame, moved by the
/// container's origin and the rendering surface's top, and the fragment is drawn
/// at `.zero` inside it — read from UIKitCore's `_UITextLayoutFragmentViewBase`
/// `_updateGeometry` and `_UITextLayoutFragmentView drawRect:` (iOS 27.0). So a
/// fragment lands on the pixel at or above its own top, each by a different
/// fraction, and two neighbors that tile in points no longer meet: a join is up to
/// a pixel apart, a light hairline where it gaps.
///
/// Modeled here the way UIKit places the views: each fragment's local space starts
/// on the canvas where `UIRectIntegralWithScale` puts it, and each is handed the
/// device transform of that local space. A join is judged on the canvas, which
/// every fragment view shares.
@Suite("Decoration geometry: a card's joins meet where UITextView floors its fragments")
struct FlooredFragmentSeamTests {
  /// Four consecutive fragments of one run, as RFC 9000 §17.2 measured.
  private let fragmentTops: [CGFloat] = [74588.5392, 74617.7892, 74647.0392, 74676.2892]
  private let advance: CGFloat = 29.25

  /// The text container's origin on the canvas: the header's measured height,
  /// which is any fraction.
  private let containerTop: CGFloat = 187.33

  /// `UIRectIntegralWithScale`'s rounding of an origin, as disassembled: the pixel
  /// at or above it, unless it is within 0.0001 of the pixel below.
  private func uiKitFloor(_ y: CGFloat, scale: CGFloat) -> CGFloat {
    let pixels = y * scale
    let up = pixels.rounded(.up)
    return (up - pixels < 0.0001 ? up : pixels.rounded(.down)) / scale
  }

  /// Where UIKit puts a fragment's local origin on the canvas: its view's frame
  /// starts at the floored fragment top plus the container's origin plus the
  /// rendering surface's top, floored again, and its bounds start at the surface's
  /// top.
  private func localOrigin(of top: CGFloat, surfaceTop: CGFloat, scale: CGFloat) -> CGFloat {
    let frame = uiKitFloor(uiKitFloor(top, scale: scale) + containerTop + surfaceTop, scale: scale)
    return frame - surfaceTop
  }

  /// Each fragment's card, as its own draw joins it, back on the canvas.
  private func cards(scale: CGFloat, surfaceTops: [CGFloat]) -> [CGRect] {
    // The canvas sits on the device grid, flipped as a layer's context is.
    let canvas = CGAffineTransform(a: scale, b: 0, c: 0, d: -scale, tx: 0, ty: 200_000 * scale)
    return fragmentTops.enumerated().map { index, y in
      let origin = localOrigin(of: y, surfaceTop: surfaceTops[index], scale: scale)
      let placement = FragmentGeometry.Placement(
        origin: .zero,
        frame: CGRect(x: 0, y: y, width: 600, height: advance),
        containerWidth: 600,
        indent: 0
      )
      return placement.snappingJoins(
        of: CGRect(x: 0, y: 0, width: 600, height: advance),
        top: index != 0,
        bottom: index != fragmentTops.count - 1,
        toDevice: CGAffineTransform(translationX: 0, y: origin).concatenating(canvas)
      )
      .offsetBy(dx: 0, dy: origin)
    }
  }

  /// A card fragment's surface starts `cardPadding / 2` and a point of slack above
  /// it; one whose glyphs reach higher starts higher still.
  private let surfaceTops: [CGFloat] = [-6, -6, -7, -6]

  @Test(arguments: [2, 3] as [CGFloat])
  func `consecutive fragments meet with no gap and no overlap`(scale: CGFloat) {
    let drawn = cards(scale: scale, surfaceTops: surfaceTops)
    for (upper, lower) in zip(drawn, drawn.dropFirst()) {
      #expect(abs(upper.maxY - lower.minY) < 1e-6, "a join apart at \(scale)x: \(upper.maxY) against \(lower.minY)")
    }
  }

  @Test(arguments: [2, 3] as [CGFloat])
  func `every join lands on a whole device pixel`(scale: CGFloat) {
    for card in cards(scale: scale, surfaceTops: surfaceTops).dropLast() {
      let pixel = card.maxY * scale
      #expect(abs(pixel - pixel.rounded()) < 1e-6, "a join inside a pixel at \(scale)x")
    }
  }
}
