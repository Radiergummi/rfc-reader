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
/// Not main-actor bound: TextKit enumerates the content as it lays out, which it does
/// off the main thread too, so the hidden text is behind a lock.
nonisolated final class FoldingDelegate: NSObject, NSTextContentStorageDelegate {
  private let state = OSAllocatedUnfairLock(initialState: HiddenText())

  var hidden: HiddenText {
    get { state.withLock { $0 } }
    set { state.withLock { $0 = newValue } }
  }

  func textContentManager(
    _ textContentManager: NSTextContentManager, shouldEnumerate textElement: NSTextElement,
    options: NSTextContentManager.EnumerationOptions
  ) -> Bool {
    guard let start = textElement.elementRange?.location else { return true }
    let offset = textContentManager.offset(
      from: textContentManager.documentRange.location, to: start)
    return state.withLock { !$0.contains(offset) }
  }
}
