import CoreGraphics
import Testing

@testable import RFCReaderKit

/// Where the pointer is the arrow over a code block's copy button on the Mac (#724).
@Suite("Copy button geometry")
struct CopyButtonGeometryTests {
  /// The button's own box, moved from the text container into the text view, where
  /// cursor rects are: a click there lands on the button's character.
  @Test func `the arrow's rect is the button's box in the text view`() {
    let button = CGRect(x: 280, y: 200, width: 14, height: 16)
    let origin = CGPoint(x: 120, y: 64)
    #expect(
      FragmentGeometry.copyButtonCursorRect(buttonFrame: button, containerOrigin: origin)
        == CGRect(x: 400, y: 264, width: 14, height: 16))
  }
}
