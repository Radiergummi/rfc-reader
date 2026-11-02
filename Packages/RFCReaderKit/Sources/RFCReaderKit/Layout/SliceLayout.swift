import Foundation

#if canImport(UIKit)
  import UIKit
#else
  import AppKit
#endif

extension SlicePlanner {
  /// Lays out `slice` of background completion, as `nextSlice()` hands it out: from
  /// the document's start through the slice's end, since TextKit's positions are
  /// exact only once everything above them is laid out. What the reader's engine and
  /// the layout benchmarks both run, so the benchmarks measure the engine's own slice.
  ///
  /// A function of the slice, not of the planner, so the caller takes the slice first
  /// and the planner moves on even when there is no layout to lay it out in. Answers
  /// whether anything was laid out: false without a layout, or when the slice is
  /// outside its text.
  @MainActor
  @discardableResult
  public static func layOut(_ slice: NSRange, in layout: NSTextLayoutManager?) -> Bool {
    guard let layout,
      let range = layout.textRange(for: NSRange(location: 0, length: NSMaxRange(slice)))
    else { return false }
    layout.ensureLayout(for: range)
    return true
  }
}
