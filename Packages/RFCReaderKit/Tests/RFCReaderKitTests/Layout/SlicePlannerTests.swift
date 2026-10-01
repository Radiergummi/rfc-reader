import Foundation
import Testing

@testable import RFCReaderKit

/// Background completion's schedule: small slices from the document's start, each
/// one frame's worth of layout, restarted by every change of geometry.
@Suite("Slice planner")
struct SlicePlannerTests {
  @Test func `slices cover the document once, in order`() {
    var planner = SlicePlanner(length: 20_000)
    var covered: [NSRange] = []
    while let slice = planner.nextSlice() { covered.append(slice) }
    #expect(covered.first?.location == 0)
    #expect(covered.map(\.length).reduce(0, +) == 20_000)
    #expect(zip(covered, covered.dropFirst()).allSatisfy { NSMaxRange($0) == $1.location })
    #expect(planner.isComplete)
  }

  @Test func `a slice is never longer than a slice`() {
    var planner = SlicePlanner(length: 50_000)
    while let slice = planner.nextSlice() { #expect(slice.length <= SlicePlanner.sliceLength) }
  }

  @Test func `a restart lays the document out again from its start`() {
    var planner = SlicePlanner(length: 20_000)
    _ = planner.nextSlice()
    _ = planner.nextSlice()
    planner.restart()
    #expect(planner.nextSlice()?.location == 0)
  }

  @Test func `an empty document is complete from the start`() {
    var planner = SlicePlanner(length: 0)
    #expect(planner.isComplete)
    #expect(planner.nextSlice() == nil)
  }

  // MARK: - A dropped layout

  /// Measured on an iPhone, RFC 5661: the document laid out at 836,956 pt, then
  /// TextKit dropped the layout on its own and estimated 739,555 pt.
  @Test func `the estimate after TextKit drops the layout is a drop`() {
    #expect(SlicePlanner.layoutWasDropped(laidOut: 836_956, now: 739_555))
  }

  /// A fragment laid out again a little taller is layout, not a loss of it.
  @Test func `a small change after completion is not a drop`() {
    #expect(!SlicePlanner.layoutWasDropped(laidOut: 836_956, now: 837_056))
  }

  @Test func `an empty document never drops its layout`() {
    #expect(!SlicePlanner.layoutWasDropped(laidOut: 0, now: 0))
  }
}
