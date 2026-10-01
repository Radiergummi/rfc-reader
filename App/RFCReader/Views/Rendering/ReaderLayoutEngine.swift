import RFCReaderKit

#if canImport(UIKit)
  import UIKit
#else
  import AppKit
#endif

/// The reader's geometry under viewport layout: the text view is a `PinSurface`,
/// the reader's place is an `AnchorKeeper`, and every change of geometry ends in
/// one `PinRecipe.pin`. Only calls into the text view live here; the arithmetic is
/// RFCReaderKit's. See `docs/superpowers/specs/2026-09-30-reader-layout-engine-design.md`.
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

  /// A new storage is in: carries the place across and pins it.
  func installed(_ built: BuiltDocument) {
    let carried = self.built.map { keeper.carried(in: $0.anchors) }
    self.built = built
    if let carried { keeper.restore(carried, in: built.anchors, length: built.text.length) }
    pin()
    startCompletion()
  }

  func columnChanged() {
    pin()
    startCompletion()
  }

  /// Puts the place back at the top of the viewport. The engine's own move: the
  /// scrolls it causes record nothing.
  func pin() {
    guard let layout = textView?.textLayoutManager else { return }
    keeper.beginEngineMove()
    defer { keeper.endEngineMove(top: containerTop) }
    switch keeper.place {
    case .top:
      textView?.scroll(toY: 0)
      layOutViewport()
    case .line(let anchor):
      PinRecipe.pin(anchor, in: layout, on: self)
    }
  }

  func jump(toOffset offset: Int) {
    keeper.jumped(to: ReaderAnchor(characterOffset: offset))
    pin()
  }

  /// A scroll happened; if the reader made it, it moves their place. Answers the
  /// place's character, which is what section tracking reads (see the spec), or nil
  /// above the text.
  @discardableResult
  func userScrolled() -> Int? {
    guard let textView, let layout = textView.textLayoutManager else { return nil }
    if !keeper.isEngineMoving { lastUserScroll = .now }
    noticeDroppedLayout(in: layout)
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
  /// When the reader last scrolled, for pausing completion while they do.
  private var lastUserScroll = ContinuousClock.now - .seconds(1)
  /// TextKit's height once completion laid the document out; nil until it has.
  private var laidOutHeight: CGFloat?

  /// Lays the document out from its start in the background, a slice per idle turn.
  private func startCompletion() {
    completion?.cancel()
    laidOutHeight = nil
    planner = SlicePlanner(length: built?.text.length ?? 0)
    completion = Task { [weak self] in
      while let self, !self.planner.isComplete {
        try? await Task.sleep(for: .milliseconds(self.isInteracting ? 50 : 4))
        guard !Task.isCancelled else { return }
        guard !self.isInteracting else { continue }
        self.layOutSlice()
      }
      self?.laidOutHeight = self?.textView?.textLayoutManager?.usageBoundsForTextContainer.height
    }
  }

  /// TextKit drops the layout of the whole document on its own now and then (see
  /// `SlicePlanner.layoutWasDropped`), on the old path as well; laid out again, its
  /// positions and the scroller's height are exact again.
  private func noticeDroppedLayout(in layout: NSTextLayoutManager) {
    guard let laidOutHeight,
      SlicePlanner.layoutWasDropped(
        laidOut: laidOutHeight, now: layout.usageBoundsForTextContainer.height)
    else { return }
    startCompletion()
  }

  func stop() {
    completion?.cancel()
    completion = nil
  }

  private var isInteracting: Bool {
    guard let textView else { return false }
    #if canImport(UIKit)
      return textView.isTracking || textView.isDecelerating
    #else
      return textView.inLiveResize || ContinuousClock.now - lastUserScroll < .milliseconds(150)
    #endif
  }

  private func layOutSlice() {
    guard let layout = textView?.textLayoutManager, let slice = planner.nextSlice(),
      let range = layout.textRange(for: NSRange(location: 0, length: NSMaxRange(slice)))
    else { return }
    layout.ensureLayout(for: range)
    pin()
  }
}
