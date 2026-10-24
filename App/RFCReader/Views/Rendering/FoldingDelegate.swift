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
/// disclosures, and Implementer's requirement bands (#700); and this text view's
/// highlights (#522), and the link the keyboard's focus is on (#711), which are never
/// in the storage, since a build is shared. A
/// fragment finds it as its layout manager's content manager's delegate.
///
/// Highlights are held here rather than as rendering attributes on the layout
/// manager, which the design first chose: `invalidateRenderingAttributes(for:)`,
/// which the reader's redraw calls over the whole document, drops every rendering
/// attribute added to it, as a probe of `NSTextView` showed
/// (`docs/decisions/2026-10-18-highlights-are-drawn-from-the-position-map.md`).
///
/// Not main-actor bound: TextKit enumerates the content and draws as it lays out,
/// which it does off the main thread too, so what it holds is behind a lock.
/// Written from outside layout as well — the coordinator folds and bands while the
/// text is laid out — which is what a fragment's own caches never are
/// (`RFCTextLayoutFragment`), and why they need no lock of their own.
nonisolated final class FoldingDelegate: NSObject, NSTextContentStorageDelegate, Sendable {
  private struct State {
    var hidden = HiddenText()
    var disclosures: [Int: Bool] = [:]
    var bands = RequirementBands()
    var highlights = HighlightMarks([])
    var focusedLink: NSRange?
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

  /// The requirement bands found after the folding: what is hidden and disclosed
  /// stays as it is, as it does not depend on them.
  func band(_ bands: RequirementBands) {
    state.withLock { $0.bands = bands }
  }

  /// The highlights this text view draws, in place of those it drew.
  func highlight(_ marks: HighlightMarks) {
    state.withLock { $0.highlights = marks }
  }

  /// The highlight marks that meet the document range `range`, whole.
  func highlights(meeting range: NSRange) -> [HighlightMark] {
    state.withLock { $0.highlights.marks(meeting: range) }
  }

  /// The link the keyboard's focus is on, which the fragments ring (#711), in place of
  /// the one they ringed; nil for none.
  func focus(link: NSRange?) {
    state.withLock { $0.focusedLink = link }
  }

  /// The link the keyboard's focus is on.
  var focusedLink: NSRange? {
    state.withLock { $0.focusedLink }
  }

  /// The focused link, where it meets the document range `range`.
  func focusedLink(meeting range: NSRange) -> NSRange? {
    state.withLock { state in
      state.focusedLink.flatMap { $0.intersection(range) == nil ? nil : $0 }
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
