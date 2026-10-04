import RFCReaderKit
import os

#if canImport(UIKit)
  import UIKit
#else
  import AppKit
#endif

/// Skips the paragraphs a reading mode folds (#698): TextKit 2 asks its content
/// manager's delegate whether to lay out each paragraph, and a paragraph it is told
/// not to enumerate makes no layout fragment. The text storage is untouched, so every
/// offset, anchor and reading position holds across a mode switch.
///
/// It also holds what the fragments draw for the reading mode: the headings'
/// disclosures, and Implementer's requirement bands (#700). A fragment finds it as
/// its layout manager's content manager's delegate.
///
/// Not main-actor bound: TextKit enumerates the content and draws as it lays out,
/// which it does off the main thread too, so what it holds is behind a lock.
nonisolated final class FoldingDelegate: NSObject, NSTextContentStorageDelegate, Sendable {
  private struct State {
    var hidden = HiddenText()
    var disclosures: [Int: Bool] = [:]
    var bands = RequirementBands()
  }

  private let state = OSAllocatedUnfairLock(initialState: State())

  var hidden: HiddenText {
    state.withLock { $0.hidden }
  }

  /// What `folding` hides and discloses in the build `index` was made of, and the
  /// requirement bands it draws: `bands` where its mode bands them, none otherwise.
  func fold(_ index: FoldingIndex, by folding: Folding, bands: RequirementBands) {
    let hidden = folding.hidden(in: index)
    let disclosures = folding.disclosures(in: index)
    let drawn = folding.mode.bandsRequirements ? bands : RequirementBands()
    state.withLock { state in
      state.hidden = hidden
      state.disclosures = disclosures
      state.bands = drawn
    }
  }

  /// Whether the heading whose paragraph starts at `offset` has a disclosure, and if
  /// so whether it is open.
  func disclosure(at offset: Int) -> Bool? {
    state.withLock { $0.disclosures[offset] }
  }

  /// The requirement bands that meet the document range `range`, whole.
  func bands(meeting range: NSRange) -> [NSRange] {
    state.withLock { $0.bands.ranges(meeting: range) }
  }

  func textContentManager(
    _ textContentManager: NSTextContentManager, shouldEnumerate textElement: NSTextElement,
    options: NSTextContentManager.EnumerationOptions
  ) -> Bool {
    guard let start = textElement.elementRange?.location else { return true }
    let offset = textContentManager.offset(
      from: textContentManager.documentRange.location, to: start)
    return state.withLock { !$0.hidden.contains(offset) }
  }
}
