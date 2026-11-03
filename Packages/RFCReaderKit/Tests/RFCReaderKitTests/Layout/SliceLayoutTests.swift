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
    let first = planner.nextSlice()
    let second = planner.nextSlice()
    let slice = try #require(first)
    let next = try #require(second)
    #expect(SlicePlanner.layOut(slice, in: fixture.layout))
    #expect(try state(at: NSMaxRange(slice) - 1, in: fixture) == .layoutAvailable)
    #expect(try state(at: NSMaxRange(next) - 1, in: fixture) != .layoutAvailable)
    #expect(try state(at: built.text.length - 1, in: fixture) != .layoutAvailable)
  }

  @Test func `slices laid out to the end lay out the whole document`() throws {
    let built = try LayoutFixture.built()
    let fixture = LayoutFixture(text: built.text, width: 712)
    var planner = SlicePlanner(length: built.text.length)
    while let slice = planner.nextSlice() { SlicePlanner.layOut(slice, in: fixture.layout) }
    #expect(try state(at: built.text.length - 1, in: fixture) == .layoutAvailable)
  }

  /// The text view can go while the completion runs; its loop must still end.
  @Test func `without a layout nothing is laid out and the planner still moves on`() {
    let length = SlicePlanner.sliceLength * 3 + 1
    var planner = SlicePlanner(length: length)
    var slices = 0
    while let slice = planner.nextSlice() {
      #expect(!SlicePlanner.layOut(slice, in: nil))
      slices += 1
    }
    #expect(planner.isComplete)
    #expect(slices == (length + SlicePlanner.sliceLength - 1) / SlicePlanner.sliceLength)
  }

  @Test func `a slice outside the text lays out nothing`() {
    let fixture = LayoutFixture(text: NSAttributedString(string: "short"), width: 712)
    #expect(!SlicePlanner.layOut(NSRange(location: 0, length: 6_000), in: fixture.layout))
  }

  private func state(
    at offset: Int, in fixture: LayoutFixture
  ) throws -> NSTextLayoutFragment.State {
    let location = try #require(fixture.layout.location(atOffset: offset))
    return try #require(fixture.layout.textLayoutFragment(for: location)).state
  }
}
