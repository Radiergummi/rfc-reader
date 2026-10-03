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
/// It also holds the headings' disclosures, which their fragments draw: a fragment
/// finds it as its layout manager's content manager's delegate.
///
/// Not main-actor bound: TextKit enumerates the content and draws as it lays out,
/// which it does off the main thread too, so what it holds is behind a lock.
nonisolated final class FoldingDelegate: NSObject, NSTextContentStorageDelegate, Sendable {
  private struct State {
    var hidden = HiddenText()
    var disclosures: [Int: Bool] = [:]
  }

  private let state = OSAllocatedUnfairLock(initialState: State())

  var hidden: HiddenText {
    state.withLock { $0.hidden }
  }

  /// What `folding` hides and discloses in the build `index` was made of.
  func fold(_ index: FoldingIndex, by folding: Folding) {
    let hidden = folding.hidden(in: index)
    let disclosures = folding.disclosures(in: index)
    state.withLock { state in
      state.hidden = hidden
      state.disclosures = disclosures
    }
  }

  /// Whether the heading whose paragraph starts at `offset` has a disclosure, and if
  /// so whether it is open.
  func disclosure(at offset: Int) -> Bool? {
    state.withLock { $0.disclosures[offset] }
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
