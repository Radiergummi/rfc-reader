import RFCReaderKit

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
/// cannot afford that on every step, pins on estimates instead, and settles once it
/// ends. Only calls into the text view live here; the arithmetic is RFCReaderKit's.
/// See `docs/superpowers/specs/2026-09-30-reader-layout-engine-design.md`.
final class ReaderLayoutEngine: PinSurface {
  /// On with the launch argument `-ReaderViewportLayout YES`, until the old path
  /// is removed.
  static var isEnabled: Bool { UserDefaults.standard.bool(forKey: "ReaderViewportLayout") }

  weak var textView: PlatformTextView?
  private(set) var keeper = AnchorKeeper()
  private(set) var built: BuiltDocument?

  // MARK: - PinSurface

  var containerTop: CGFloat { textView?.viewportTop ?? 0 }

  func scroll(toContainerY target: CGFloat) {
    guard let textView else { return }
    textView.scroll(toY: target + textView.containerTop)
  }

  func layOutViewport() {
    guard let textView else { return }
    textView.syncLayout()
    textView.textLayoutManager?.textViewportLayoutController.layoutViewport()
  }

  // MARK: - Changes of geometry

  /// A new storage is in: carries the place across and puts it back.
  func installed(_ built: BuiltDocument) {
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

  /// A live resize ended: the place it pinned on estimates is settled.
  func liveResizeEnded() {
    settle()
  }

  /// Settles the place, or pins it on estimates during a live resize.
  private func putBack() {
    if isInLiveResize { pin() } else { settle() }
  }

  /// Puts the place back at the top of the viewport, everything above it laid out
  /// first (`PinRecipe.settle`).
  func settle() {
    move { anchor, layout in PinRecipe.settle(anchor, in: layout, on: self) }
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

  func jump(toOffset offset: Int) {
    keeper.jumped(to: ReaderAnchor(characterOffset: offset))
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

  /// Lays the document out from its start in the background, a slice per idle turn,
  /// so the scroller's height is exact. It moves nothing on screen: what is above the
  /// place is laid out already, and the scroll view keeps the place where it is as
  /// the rest arrives. Paused through a live resize, whose every step re-wraps it.
  private func startCompletion() {
    completion?.cancel()
    planner = SlicePlanner(length: built?.text.length ?? 0)
    completion = Task { [weak self] in
      while let self, !self.planner.isComplete {
        try? await Task.sleep(for: .milliseconds(self.isInLiveResize ? 50 : 4))
        guard !Task.isCancelled else { return }
        guard !self.isInLiveResize else { continue }
        self.layOutSlice()
      }
    }
  }

  func stop() {
    completion?.cancel()
    completion = nil
  }

  private var isInLiveResize: Bool {
    #if canImport(UIKit)
      return false
    #else
      return textView?.inLiveResize ?? false
    #endif
  }

  private func layOutSlice() {
    guard let layout = textView?.textLayoutManager, let slice = planner.nextSlice(),
      let range = layout.textRange(for: NSRange(location: 0, length: NSMaxRange(slice)))
    else { return }
    layout.ensureLayout(for: range)
  }
}
