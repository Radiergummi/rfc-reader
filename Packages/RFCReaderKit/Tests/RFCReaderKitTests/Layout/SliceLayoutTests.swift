import Foundation
import Testing

@testable import RFCReaderKit

#if canImport(UIKit)
  import UIKit
#else
  import AppKit
#endif

/// Background completion's slice, laid out: from the document's start through the
/// slice's end, which the reader's engine and the layout benchmarks both run.
@Suite("Slice layout")
@MainActor
struct SliceLayoutTests {
  @Test func `a slice is laid out through its end and no further`() throws {
    let built = try LayoutFixture.built()
    let fixture = LayoutFixture(text: built.text, width: 712)
    var planner = SlicePlanner(length: built.text.length)
    let laidOut = planner.layOutNextSlice(in: fixture.layout)
    let slice = try #require(laidOut)
    #expect(try state(at: NSMaxRange(slice) - 1, in: fixture) == .layoutAvailable)
    #expect(try state(at: built.text.length - 1, in: fixture) != .layoutAvailable)
  }

  @Test func `slices laid out to the end lay out the whole document`() throws {
    let built = try LayoutFixture.built()
    let fixture = LayoutFixture(text: built.text, width: 712)
    var planner = SlicePlanner(length: built.text.length)
    while planner.layOutNextSlice(in: fixture.layout) != nil {}
    #expect(planner.isComplete)
    #expect(try state(at: built.text.length - 1, in: fixture) == .layoutAvailable)
  }

  /// The text view can go while the completion runs; its loop must still end.
  @Test func `without a layout the planner still moves on`() {
    var planner = SlicePlanner(length: 20_000)
    var slices = 0
    while planner.layOutNextSlice(in: nil) != nil { slices += 1 }
    #expect(planner.isComplete)
    #expect(slices == 4)
  }

  private func state(
    at offset: Int, in fixture: LayoutFixture
  ) throws -> NSTextLayoutFragment.State {
    let location = try #require(fixture.layout.location(atOffset: offset))
    return try #require(fixture.layout.textLayoutFragment(for: location)).state
  }
}
