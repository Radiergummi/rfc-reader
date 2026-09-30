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
  private(set) var model: HeightModel?
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

  /// A new storage is in, built for `column`: carries the place across and pins it.
  func installed(_ built: BuiltDocument, column: CGFloat?) {
    let carried = self.built.map { keeper.carried(in: $0.anchors) }
    self.built = built
    model = column.map { HeightModel(paragraphs: built.paragraphs, column: $0) }
    scrollerHeight.columnChanged(to: model?.total ?? 0)
    if let carried { keeper.restore(carried, in: built.anchors, length: built.text.length) }
    pin()
    startCompletion()
  }

  func columnChanged(to column: CGFloat) {
    // A storage installed before the first column has no model yet.
    if model == nil, let built {
      model = HeightModel(paragraphs: built.paragraphs, column: column)
    }
    model?.setColumn(column)
    scrollerHeight.columnChanged(to: model?.total ?? 0)
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
    if !keeper.isEngineMoving {
      lastUserScroll = .now
      scrollerHeight.interactionBegan()
    }
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

  // MARK: - Background completion

  private var planner = SlicePlanner(length: 0)
  private var completion: Task<Void, Never>?
  /// When the reader last scrolled, for pausing completion while they do.
  private var lastUserScroll = ContinuousClock.now - .seconds(1)
  private(set) var scrollerHeight = ScrollerHeight(total: 0)
  /// Told whenever `scrollerHeight.shown` moved, so the scroller is redrawn.
  var onHeightChange: () -> Void = {}

  /// Lays the document out from its start in the background, a slice per idle turn.
  private func startCompletion() {
    completion?.cancel()
    planner = SlicePlanner(length: built?.text.length ?? 0)
    completion = Task { [weak self] in
      while let self, !self.planner.isComplete || self.scrollerHeight.isEasing {
        try? await Task.sleep(for: .milliseconds(self.isInteracting ? 50 : 4))
        guard !Task.isCancelled else { return }
        self.advanceScroller()
        guard !self.isInteracting, !self.planner.isComplete else { continue }
        self.layOutSlice()
      }
    }
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
    recordHeights(of: slice, in: layout)
    pin()
  }

  private func recordHeights(of slice: NSRange, in layout: NSTextLayoutManager) {
    guard var model, let location = layout.location(atOffset: slice.location) else { return }
    var measured: [(paragraph: Int, height: CGFloat)] = []
    layout.enumerateTextLayoutFragments(from: location, options: []) { fragment in
      let offset = layout.offset(of: fragment.rangeInElement.location)
      guard offset < NSMaxRange(slice) else { return false }
      measured.append((model.paragraph(containing: offset), fragment.layoutFragmentFrame.height))
      return true
    }
    model.measure(measured)
    self.model = model
    scrollerHeight.modelChanged(to: model.total, now: Date.timeIntervalSinceReferenceDate)
  }

  private func advanceScroller() {
    let before = scrollerHeight.shown
    if !isInteracting { scrollerHeight.interactionEnded(now: Date.timeIntervalSinceReferenceDate) }
    scrollerHeight.advance(to: Date.timeIntervalSinceReferenceDate)
    if scrollerHeight.shown != before { onHeightChange() }
  }
}
