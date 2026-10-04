import RFCKit
import RFCReaderKit
import os

#if canImport(UIKit)
  import UIKit
#else
  import AppKit
#endif

/// The reader's geometry under viewport layout: the text view is a `PinSurface`,
/// the reader's place is an `AnchorKeeper`, and every change of geometry settles the
/// place (`PinRecipe.settle`). Everything above it is then laid out, so it is where
/// the layout of the whole document puts it, and the platform's own scroll view
/// keeps it there while the rest is laid out. Only a live resize on the Mac, which
/// cannot afford that on every step, pins on estimates instead; the rebuild for the
/// new column that follows it settles. Only calls into the text view live here; the
/// arithmetic is RFCReaderKit's. See `docs/superpowers/specs/2026-09-30-reader-layout-engine-design.md`.
final class ReaderLayoutEngine: PinSurface {
  weak var textView: PlatformTextView?
  private(set) var keeper = AnchorKeeper()
  private(set) var built: BuiltDocument?
  /// What the signposts name; see `Signposts`.
  private var documentName = "untitled"

  // MARK: - PinSurface

  var containerTop: CGFloat { textView?.viewportTop ?? 0 }

  func scroll(toContainerY target: CGFloat) {
    guard let textView else { return }
    textView.scroll(toY: target + textView.containerTop, knowsEnd: knowsDocumentEnd)
  }

  /// Whether the text view's height is the laid-out document's, so a scroll can be
  /// held to its end: once the completion has laid all of it out, or a refold has laid
  /// out what the folding shows. Until then the end is an estimate.
  private var knowsDocumentEnd = false

  /// Not during a live resize: there AppKit's own display pass lays the viewport out.
  /// Forced on every step, it made `NSTextView` lay out a large range of the document
  /// itself (`textViewportLayoutControllerDidLayout:` → `ensureLayoutForRange:`):
  /// 500–630 ms per step on RFC 5661, against under 1 ms without, and the reader's
  /// line held all the same.
  func layOutViewport() {
    guard !isInLiveResize, let textView else { return }
    textView.syncLayout()
    textView.textLayoutManager?.textViewportLayoutController.layoutViewport()
  }

  // MARK: - Changes of geometry

  /// A new storage is in: carries the place across and puts it back.
  func installed(_ built: BuiltDocument, document: DocumentID?) {
    documentName = document?.displayName ?? "untitled"
    let carried = self.built.map { keeper.carried(in: $0.anchors) }
    self.built = built
    if let carried { keeper.restore(carried, in: built.anchors, length: built.text.length) }
    putBack()
    startCompletion()
  }

  func columnChanged() {
    putBack()
    startCompletion()
  }

  /// Settles the place, or pins it on estimates during a live resize.
  private func putBack() {
    if isInLiveResize { pin() } else { settle() }
  }

  /// Puts the place back at the top of the viewport, everything above it laid out
  /// first (`PinRecipe.settle`).
  func settle() {
    move { anchor, layout in
      signposter.withIntervalSignpost(
        "Settle", id: signposter.makeSignpostID(), "\(self.documentName, privacy: .public)"
      ) {
        _ = PinRecipe.settle(anchor, in: layout, on: self)
      }
    }
  }

  /// Puts the place back at the top of the viewport where it is laid out now: after
  /// a change that moved the container but re-wrapped nothing, or on estimates.
  func pin() {
    move { anchor, layout in PinRecipe.pin(anchor, in: layout, on: self) }
  }

  /// The engine's own move: the scrolls it causes record nothing.
  private func move(_ line: (ReaderAnchor, NSTextLayoutManager) -> Void) {
    guard let layout = textView?.textLayoutManager else { return }
    keeper.beginEngineMove()
    defer { keeper.endEngineMove(top: containerTop) }
    switch keeper.place {
    case .top:
      textView?.scroll(toY: 0)
      layOutViewport()
    case .line(let anchor):
      line(anchor, layout)
    }
  }

  /// The reading mode folded or unfolded paragraphs (#698): the layout is made again,
  /// and the reader's line kept, at the shown paragraph nearest it where it was
  /// folded, or put at `place`, a jump's target the folding has just shown.
  func refold(_ hidden: HiddenText, placeAt place: Int? = nil) {
    guard let layout = textView?.textLayoutManager else { return }
    if let place {
      keeper.jumped(to: ReaderAnchor(characterOffset: place))
    } else if case .line(let anchor) = keeper.place, hidden.contains(anchor.characterOffset) {
      if let shown = hidden.shownOffset(near: anchor.characterOffset) {
        keeper.jumped(to: ReaderAnchor(characterOffset: shown))
      } else {
        // Nothing is shown at all: the top is all there is.
        keeper.userScrolledAboveText()
      }
    }
    layout.invalidateLayout(for: layout.documentRange)
    // With paragraphs skipped, TextKit's usage bounds stay at height 0 until the whole
    // document is laid out, and the text view sizes itself from them: a probe run
    // showed the view 943 pt tall over a viewport laid out to 1,219 pt, and what fell
    // below its bottom stayed blank. Laid out first, so the view is its full height
    // before the place is settled. Only what the folding shows is laid out, which in
    // a mode that folds is a part of the document; with nothing folded, the background
    // completion does it as after any change.
    let laidOut = !hidden.isEmpty
    if laidOut, let textView {
      layout.ensureLayout(for: layout.documentRange)
      #if !canImport(UIKit)
        textView.sizeToFit()
      #endif
    }
    knowsDocumentEnd = laidOut
    putBack()
    startCompletion(knowingEnd: laidOut)
  }

  /// The character the reader's line is on; nil at the top, above the text.
  var placeOffset: Int? {
    guard case .line(let anchor) = keeper.place else { return nil }
    return anchor.characterOffset
  }

  func jump(toOffset offset: Int) {
    keeper.jumped(to: ReaderAnchor(characterOffset: offset))
    settle()
  }

  /// Puts the top of the document, above its text, at the top of the viewport.
  func jumpToTop() {
    keeper.userScrolledAboveText()
    settle()
  }

  /// A scroll happened; if the reader made it, it moves their place. Answers the
  /// place's character, which is what section tracking reads (see the spec), or nil
  /// above the text.
  @discardableResult
  func userScrolled() -> Int? {
    guard let textView, let layout = textView.textLayoutManager else { return nil }
    let top = textView.viewportTop
    guard top >= 0 else {
      keeper.userScrolledAboveText()
      return nil
    }
    guard let start = layout.textViewportLayoutController.viewportRange?.location,
      let found = PinRecipe.anchor(atContainerTop: top, in: layout, from: start)
    else { return nil }
    keeper.userScrolled(to: found.anchor, line: found.line, top: top)
    guard case .line(let anchor) = keeper.place else { return nil }
    return anchor.characterOffset
  }

  // MARK: - Find and VoiceOver

  /// Puts `range` a third of the way down the viewport when it is outside what is
  /// laid out around it; answers false when it is near enough for the text view's own
  /// scroll, whose geometry there is laid out.
  func reveal(_ range: NSRange) -> Bool {
    guard let textView, let layout = textView.textLayoutManager,
      let viewport = layout.textViewportLayoutController.viewportRange,
      let near = layout.range(of: viewport)
    else { return false }
    if NSLocationInRange(range.location, near) { return false }
    jump(toOffset: range.location)
    keeper.beginEngineMove()
    scroll(toContainerY: containerTop - textView.viewportHeight / 3)
    layOutViewport()
    keeper.endEngineMove(top: containerTop)
    userScrolledAfterReveal()
    return true
  }

  /// A reveal is the reader's move: record where it left the top.
  private func userScrolledAfterReveal() {
    guard let layout = textView?.textLayoutManager,
      let start = layout.textViewportLayoutController.viewportRange?.location,
      let found = PinRecipe.anchor(atContainerTop: max(0, containerTop), in: layout, from: start)
    else { return }
    keeper.jumped(to: found.anchor)
  }

  // MARK: - Background completion

  private var planner = SlicePlanner(length: 0)
  private var completion: Task<Void, Never>?
  /// The signpost interval of the completion running now; see `Signposts`.
  private var completionInterval: OSSignpostIntervalState?

  /// How long this engine's completion lays out before it yields to let the run loop
  /// draw and take input: a slice is 3–5 ms and the budget is checked before each,
  /// so a turn is one or two slices. Each text view's engine has a budget of its own.
  private static let turnBudget = Duration.milliseconds(4)

  /// Lays the document out from its start in the background, a turn's budget at a
  /// time, so the scroller's height is exact. It moves nothing on screen: what is
  /// above the place is laid out already, and the scroll view keeps the place where
  /// it is as the rest arrives. Paused through a live resize, whose every step
  /// re-wraps it, until the text view says the resize ended.
  private func startCompletion(knowingEnd: Bool = false) {
    stop()
    knowsDocumentEnd = knowingEnd
    planner = SlicePlanner(length: built?.text.length ?? 0)
    // An ID of its own, because several text views lay out at once: every window
    // and tab, and a force-click preview.
    completionInterval = signposter.beginInterval(
      "Lay out document", id: signposter.makeSignpostID(), "\(self.documentName, privacy: .public)")
    completion = Task { [weak self] in
      // Ends with the text view, too: there is nothing left to lay out in.
      while let self, self.textView != nil, !self.planner.isComplete {
        await Task.yield()
        guard !Task.isCancelled else { return }
        if self.isInLiveResize {
          await self.liveResizeEnded()
          continue
        }
        let clock = ContinuousClock()
        let turnStart = clock.now
        while !self.planner.isComplete, clock.now - turnStart < Self.turnBudget {
          self.layOutSlice()
        }
      }
      if self?.planner.isComplete == true { self?.knowsDocumentEnd = true }
      self?.endCompletionInterval()
    }
  }

  func stop() {
    completion?.cancel()
    completion = nil
    endCompletionInterval()
  }

  /// Ends the interval `startCompletion()` began: when the last slice lands, or when
  /// a newer completion or the text view going replaces it, so a trace shows a
  /// completion that stopped ending where it stopped. `deinit` covers the last way.
  private func endCompletionInterval() {
    guard let completionInterval else { return }
    signposter.endInterval("Lay out document", completionInterval)
    self.completionInterval = nil
  }

  deinit {
    if let completionInterval { signposter.endInterval("Lay out document", completionInterval) }
  }

  private var isInLiveResize: Bool {
    #if canImport(UIKit)
      return false
    #else
      return textView?.inLiveResize ?? false
    #endif
  }

  /// Returns when the text view's live resize ends, or the completion is canceled.
  /// The view's rather than the window's: dragging a split view's divider is a live
  /// resize of the views beside it, and the window posts nothing at its end. Called
  /// only while one is under way, with no suspension since the check, so the end
  /// cannot have been posted already.
  private func liveResizeEnded() async {
    #if !canImport(UIKit)
      guard let textView else { return }
      let ends = NotificationCenter.default.notifications(
        named: ReaderTextView.didEndLiveResizeNotification, object: textView)
      for await _ in ends { break }
    #endif
  }

  /// Takes the slice first, so the planner moves on even when there is nothing to
  /// lay it out in, and the completion's loop cannot spin in place.
  private func layOutSlice() {
    guard let slice = planner.nextSlice(), let layout = textView?.textLayoutManager,
      let range = layout.textRange(for: NSRange(location: 0, length: NSMaxRange(slice)))
    else { return }
    layout.ensureLayout(for: range)
  }
}
