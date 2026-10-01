import Foundation

/// Which slice of the document background completion lays out next. Slices run
/// from the document's start, because TextKit's positions are exact only once
/// everything above them is laid out, and are small enough to fit in a frame: the
/// probe measured 10–16 ms for 20,000 characters, so 6,000 is about 3–5 ms.
public struct SlicePlanner: Sendable, Equatable {
  public static let sliceLength = 6_000

  public let length: Int
  public private(set) var completedThrough = 0

  public init(length: Int) {
    self.length = length
  }

  public var isComplete: Bool { completedThrough >= length }

  /// After a change of geometry every fragment is at a new column.
  public mutating func restart() {
    completedThrough = 0
  }

  /// The next slice, or nil once the document is laid out. The caller lays out from
  /// the document's start through the slice's end.
  public mutating func nextSlice() -> NSRange? {
    guard !isComplete else { return nil }
    let start = completedThrough
    completedThrough = min(length, start + Self.sliceLength)
    return NSRange(location: start, length: completedThrough - start)
  }
}
