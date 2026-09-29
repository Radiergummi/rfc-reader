import CoreGraphics
import Testing

@testable import RFCReaderKit

/// Where the Go to RFC palette's panel goes: centred on its window, hanging below
/// the toolbar, and never off the screen.
@Suite("Quick open placement")
struct QuickOpenPlacementTests {
  private let screen = CGRect(x: 0, y: 0, width: 1500, height: 900)
  private let size = CGSize(width: 600, height: 400)

  @Test func `the panel is centred on the window and hangs from the content's top`() {
    let origin = QuickOpenPlacement.origin(
      of: size,
      over: CGRect(x: 100, y: 100, width: 1000, height: 700),
      below: 748,
      screen: screen
    )
    #expect(origin == CGPoint(x: 300, y: 348))
  }

  @Test func `a window hanging off the right edge keeps the panel on screen`() {
    let origin = QuickOpenPlacement.origin(
      of: size,
      over: CGRect(x: 1200, y: 100, width: 1000, height: 700),
      below: 748,
      screen: screen
    )
    #expect(origin.x == 900)
  }

  @Test func `a window hanging off the left edge keeps the panel on screen`() {
    let origin = QuickOpenPlacement.origin(
      of: size,
      over: CGRect(x: -900, y: 100, width: 1000, height: 700),
      below: 748,
      screen: screen
    )
    #expect(origin.x == 0)
  }

  @Test func `a window low on the screen keeps the panel above its bottom`() {
    let origin = QuickOpenPlacement.origin(
      of: size,
      over: CGRect(x: 100, y: -500, width: 1000, height: 700),
      below: 150,
      screen: screen
    )
    #expect(origin.y == 0)
  }

  @Test func `without a screen the panel only follows the window`() {
    let origin = QuickOpenPlacement.origin(
      of: size,
      over: CGRect(x: 1200, y: 100, width: 1000, height: 700),
      below: 748,
      screen: nil
    )
    #expect(origin == CGPoint(x: 1400, y: 348))
  }
}
