import CoreGraphics
import Testing

@testable import RFCReaderKit

/// Where the header's author chips land (#19): left to right, a new line wherever
/// the next one would not fit.
@Suite("Wrapping row")
struct WrappingRowTests {
  @Test func `chips that fit share a line`() {
    let frames = WrappingRow.frames(
      for: [CGSize(width: 40, height: 20), CGSize(width: 50, height: 20)], width: 100,
      spacing: 6)
    #expect(
      frames == [
        CGRect(x: 0, y: 0, width: 40, height: 20), CGRect(x: 46, y: 0, width: 50, height: 20),
      ])
  }

  @Test func `a chip that would not fit starts a new line`() {
    let frames = WrappingRow.frames(
      for: [CGSize(width: 60, height: 20), CGSize(width: 50, height: 20)], width: 100,
      spacing: 6)
    #expect(
      frames == [
        CGRect(x: 0, y: 0, width: 60, height: 20), CGRect(x: 0, y: 26, width: 50, height: 20),
      ])
  }

  /// The spacing counts: 47 + 6 + 47 is exactly the width, and fits.
  @Test func `a chip that fits exactly stays on the line`() {
    let frames = WrappingRow.frames(
      for: [CGSize(width: 47, height: 20), CGSize(width: 47, height: 20)], width: 100,
      spacing: 6)
    #expect(frames.map(\.minY) == [0, 0])
  }

  /// A shorter chip is centered on its line, and the next line starts below the
  /// tallest.
  @Test func `chips are centered on their line`() {
    let frames = WrappingRow.frames(
      for: [
        CGSize(width: 40, height: 24), CGSize(width: 40, height: 20), CGSize(width: 90, height: 20),
      ], width: 100, spacing: 6)
    #expect(frames.map(\.minY) == [0, 2, 30])
    #expect(WrappingRow.size(of: frames) == CGSize(width: 90, height: 50))
  }

  /// A chip wider than the line still gets one of its own rather than an empty
  /// line before it.
  @Test func `an oversized chip takes a line of its own`() {
    let frames = WrappingRow.frames(
      for: [CGSize(width: 150, height: 20), CGSize(width: 30, height: 20)], width: 100,
      spacing: 6)
    #expect(frames.map(\.minY) == [0, 26])
  }

  @Test func `no chips take no room`() {
    #expect(WrappingRow.frames(for: [], width: 100, spacing: 6).isEmpty)
    #expect(WrappingRow.size(of: []) == .zero)
  }
}
