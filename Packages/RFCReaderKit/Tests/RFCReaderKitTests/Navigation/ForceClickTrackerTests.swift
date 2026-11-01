import Testing

@testable import RFCReaderKit

/// A References panel row's force click on the Mac (#580): once per click, and only
/// for a click that began on the row.
@Suite("Force click tracker")
struct ForceClickTrackerTests {
  @Test func `a click on the row that presses through is one force click`() {
    var tracker = ForceClickTracker()
    #expect(tracker.handle(.mouseDown(inside: true)) == .pressBegan)
    #expect(tracker.handle(.pressure(stage: 1, inside: true)) == nil)
    #expect(tracker.handle(.pressure(stage: 2, inside: true)) == .forceClick)
    // Stage 2 comes again with every change of pressure past it.
    #expect(tracker.handle(.pressure(stage: 2, inside: true)) == nil)
    #expect(tracker.handle(.mouseUp) == nil)
  }

  /// A press dragged in from elsewhere is not a click on this row.
  @Test func `a click that began elsewhere is not the row's`() {
    var tracker = ForceClickTracker()
    #expect(tracker.handle(.mouseDown(inside: false)) == nil)
    #expect(tracker.handle(.pressure(stage: 2, inside: true)) == nil)
  }

  /// Nor is a press that left the row before it pressed through.
  @Test func `pressing through outside the row is not a force click on it`() {
    var tracker = ForceClickTracker()
    _ = tracker.handle(.mouseDown(inside: true))
    #expect(tracker.handle(.pressure(stage: 2, inside: false)) == nil)
  }

  @Test func `the next click can force click again`() {
    var tracker = ForceClickTracker()
    _ = tracker.handle(.mouseDown(inside: true))
    _ = tracker.handle(.pressure(stage: 2, inside: true))
    _ = tracker.handle(.mouseUp)
    #expect(tracker.handle(.pressure(stage: 2, inside: true)) == nil)
    #expect(tracker.handle(.mouseDown(inside: true)) == .pressBegan)
    #expect(tracker.handle(.pressure(stage: 2, inside: true)) == .forceClick)
  }
}
