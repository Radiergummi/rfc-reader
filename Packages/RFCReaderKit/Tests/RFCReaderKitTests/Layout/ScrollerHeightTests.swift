import Foundation
import Testing

@testable import RFCReaderKit

/// The height the knob is drawn against: never moved under the reader while they
/// scroll or drag, eased to a new total once they stop, and moved at once when the
/// column changes, when everything is moving anyway.
@Suite("Scroller height")
struct ScrollerHeightTests {
  @Test func `a change while the reader scrolls waits until they stop`() {
    var height = ScrollerHeight(total: 1000)
    height.interactionBegan()
    height.modelChanged(to: 1200, now: 0)
    height.advance(to: 1)
    #expect(height.shown == 1000)
    height.interactionEnded(now: 2)
    height.advance(to: 2 + ScrollerHeight.easeDuration)
    #expect(height.shown == 1200)
  }

  @Test func `a change at rest eases over the ease duration`() {
    var height = ScrollerHeight(total: 1000)
    height.modelChanged(to: 2000, now: 10)
    height.advance(to: 10 + ScrollerHeight.easeDuration / 2)
    #expect(height.shown > 1000 && height.shown < 2000)
    #expect(height.isEasing)
    height.advance(to: 10 + ScrollerHeight.easeDuration)
    #expect(height.shown == 2000)
    #expect(!height.isEasing)
  }

  @Test func `a change of column is shown at once`() {
    var height = ScrollerHeight(total: 1000)
    height.interactionBegan()
    height.columnChanged(to: 3000)
    #expect(height.shown == 3000)
    #expect(!height.isEasing)
  }

  /// The engine says so on every idle turn; restarting the ease each time would
  /// never let it reach the model's total.
  @Test func `ending an interaction that is not in progress does not restart an ease`() {
    var height = ScrollerHeight(total: 1000)
    height.modelChanged(to: 2000, now: 0)
    height.advance(to: ScrollerHeight.easeDuration / 2)
    height.interactionEnded(now: ScrollerHeight.easeDuration / 2)
    height.advance(to: ScrollerHeight.easeDuration)
    #expect(height.shown == 2000)
    #expect(!height.isEasing)
  }

  @Test func `an interaction that ends with nothing changed starts no ease`() {
    var height = ScrollerHeight(total: 1000)
    height.interactionBegan()
    height.interactionEnded(now: 5)
    #expect(!height.isEasing)
  }
}
