import Foundation

#if canImport(UIKit)
  import UIKit
#else
  import AppKit
#endif

extension SlicePlanner {
  /// Lays out the next slice of background completion: from the document's start
  /// through the slice's end, since TextKit's positions are exact only once
  /// everything above them is laid out. What the reader's engine and the layout
  /// benchmarks both run, so the benchmarks measure the engine's own slice.
  ///
  /// Takes the slice first, so the planner moves on even when there is no layout to
  /// lay it out in, and a completion's loop cannot spin in place. Answers the slice,
  /// or nil once the document is laid out.
  @MainActor
  @discardableResult
  public mutating func layOutNextSlice(in layout: NSTextLayoutManager?) -> NSRange? {
    guard let slice = nextSlice() else { return nil }
    guard let layout,
      let range = layout.textRange(for: NSRange(location: 0, length: NSMaxRange(slice)))
    else { return slice }
    layout.ensureLayout(for: range)
    return slice
  }
}
