import Testing

@testable import RFCReaderKit

/// A References panel row's force click on the Mac (#580): once per click, and only
/// for a click that began on the row; its release opens nothing.
@Suite("Force click tracker")
struct ForceClickTrackerTests {
  @Test func `a click on the row that presses through is one force click`() {
    let tracker = ForceClickTracker()
    #expect(!tracker.handle(.mouseDown(inside: true)))
    #expect(!tracker.handle(.pressure(stage: 1, inside: true)))
    #expect(tracker.handle(.pressure(stage: 2, inside: true)))
    // Stage 2 comes again with every change of pressure past it.
    #expect(!tracker.handle(.pressure(stage: 2, inside: true)))
    #expect(!tracker.handle(.mouseUp))
  }

  /// A press dragged in from elsewhere is not a click on this row.
  @Test func `a click that began elsewhere is not the row's`() {
    let tracker = ForceClickTracker()
    #expect(!tracker.handle(.mouseDown(inside: false)))
    #expect(!tracker.handle(.pressure(stage: 2, inside: true)))
  }

  /// Nor is a press that left the row before it pressed through.
  @Test func `pressing through outside the row is not a force click on it`() {
    let tracker = ForceClickTracker()
    _ = tracker.handle(.mouseDown(inside: true))
    #expect(!tracker.handle(.pressure(stage: 2, inside: false)))
  }

  @Test func `the next click can force click again`() {
    let tracker = ForceClickTracker()
    _ = tracker.handle(.mouseDown(inside: true))
    _ = tracker.handle(.pressure(stage: 2, inside: true))
    _ = tracker.handle(.mouseUp)
    #expect(!tracker.handle(.pressure(stage: 2, inside: true)))
    _ = tracker.handle(.mouseDown(inside: true))
    #expect(tracker.handle(.pressure(stage: 2, inside: true)))
  }

  @Test func `a plain click opens on its release`() {
    let tracker = ForceClickTracker()
    _ = tracker.handle(.mouseDown(inside: true))
    _ = tracker.handle(.pressure(stage: 1, inside: true))
    _ = tracker.handle(.mouseUp)
    #expect(tracker.opensOnRelease())
  }

  /// The monitor sees the release before the button does.
  @Test func `the release of a force click opens nothing, and the next click does`() {
    let tracker = ForceClickTracker()
    _ = tracker.handle(.mouseDown(inside: true))
    _ = tracker.handle(.pressure(stage: 2, inside: true))
    _ = tracker.handle(.mouseUp)
    #expect(!tracker.opensOnRelease())
    _ = tracker.handle(.mouseDown(inside: true))
    _ = tracker.handle(.mouseUp)
    #expect(tracker.opensOnRelease())
  }

  /// Its popover is open, and the click that presses through again closes it as it
  /// opens it anew: its release still opens nothing.
  @Test func `force clicking the row again while its preview is open opens nothing`() {
    let tracker = ForceClickTracker()
    _ = tracker.handle(.mouseDown(inside: true))
    #expect(tracker.handle(.pressure(stage: 2, inside: true)))
    _ = tracker.handle(.mouseUp)
    #expect(!tracker.opensOnRelease())
    _ = tracker.handle(.mouseDown(inside: true))
    #expect(tracker.handle(.pressure(stage: 2, inside: true)))
    _ = tracker.handle(.mouseUp)
    #expect(!tracker.opensOnRelease())
  }

  /// A force click whose release never reached the button, as when the popover took
  /// it, leaves the next press of the button its own.
  @Test func `a release the button never saw swallows one press at most`() {
    let tracker = ForceClickTracker()
    _ = tracker.handle(.mouseDown(inside: true))
    _ = tracker.handle(.pressure(stage: 2, inside: true))
    _ = tracker.handle(.mouseUp)
    _ = tracker.handle(.mouseDown(inside: true))
    _ = tracker.handle(.mouseUp)
    #expect(tracker.opensOnRelease())
  }
}
