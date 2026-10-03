#if os(macOS)
  import AppKit
  import RFCReaderKit

  /// The macOS reader's hover and force-click previews: the AppKit half of
  /// `ReferenceHover`, which decides. This owns what that value cannot — the
  /// tracking area, the dwell, the popover — and does the effects it asks for.
  ///
  /// What a reference previews as, and where the pointer is over one, stays the
  /// coordinator's, which knows the document; it answers through the closures set
  /// in `attach(to:)`.
  final class ReferenceHoverController: NSObject, NSPopoverDelegate {
    private var state = ReferenceHover()
    /// See `RFCTextView.commitsOnClick`: a preview's reader previews nothing.
    var isPreviewReader: Bool {
      get { state.isPreviewReader }
      set { state.isPreviewReader = newValue }
    }

    private weak var textView: NSTextView?
    /// `.inVisibleRect` keeps this correct across resizes and scrolling without an
    /// `updateTrackingAreas` override.
    private var trackingArea: NSTrackingArea?
    /// The 0.5 s dwell. A task on the main actor rather than a `Timer`: canceling
    /// it is all it takes, and a click or a drag in progress when it ends is told
    /// apart by the button still held, which `ReferenceHover` checks.
    private var dwellTask: Task<Void, Never>?
    private var popover: NSPopover?

    /// The reference under a point in window coordinates.
    var target: (NSPoint) -> HoverTarget? = { _ in nil }
    /// The reference the pointer rests on after a scroll: in the visible text, in
    /// the active app, with no button held. Nil otherwise.
    var restingTarget: () -> HoverTarget? = { nil }
    /// What a popover shows, how big it is when its content does not say, and the
    /// rect it is anchored to, in text-container coordinates.
    struct Popover {
      let content: NSViewController
      var size: CGSize?
      let anchor: CGRect
    }

    /// A reference's card, or nil when it has none.
    var card: (HoverTarget) -> Popover? = { _ in nil }
    /// The document a reference names, previewed (#29), or nil when it has none.
    var documentPreview: (HoverTarget) -> Popover? = { _ in nil }

    // MARK: - Setup

    /// Added once, the moment the text view is set. `.mouseEnteredAndExited` is
    /// what lets `mouseExited` end a hover when the pointer leaves the view
    /// entirely, rather than only on the next in-view move. `.activeInActiveApp`
    /// rather than `.activeInKeyWindow`: the popover's window can become key, and
    /// then the moves and the exit that close it would stop arriving.
    func attach(to textView: NSTextView) {
      guard trackingArea == nil else { return }
      self.textView = textView
      let area = NSTrackingArea(
        rect: .zero,
        options: [.mouseMoved, .mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
        owner: self,
        userInfo: nil
      )
      textView.addTrackingArea(area)
      trackingArea = area
    }

    /// A tracking area does not retain its owner, so it must not outlive this on a
    /// view that might. Called from `dismantleNSView`.
    func tearDown() {
      send(.reset)
      if let trackingArea { textView?.removeTrackingArea(trackingArea) }
      trackingArea = nil
    }

    // MARK: - Events

    /// Hands `event` to the rules and does what they ask of the window layer. The
    /// effects that are the caller's to act on — following a link, committing a
    /// preview, swallowing a click — are returned.
    @discardableResult
    func send(_ event: ReferenceHover.Event) -> [ReferenceHover.Effect] {
      readVoiceOver()
      let effects = state.handle(event)
      for effect in effects {
        switch effect {
        case .startDwell(let dwell):
          startDwell(dwell)
        case .cancelDwell:
          dwellTask?.cancel()
          dwellTask = nil
        case .closePopover:
          // Forgotten before it is closed, so its delegate call, whenever it
          // lands, is for a popover no longer current and changes nothing: the
          // rules have already moved on, perhaps to the preview replacing it.
          let closing = popover
          popover = nil
          if closing?.isShown == true { closing?.performClose(nil) }
        case .showCard(let target):
          showCard(target)
        case .showDocumentPreview(let target):
          showDocumentPreview(target)
        case .commitPreview, .swallowClick, .followLink:
          break
        }
      }
      return effects
    }

    /// Named explicitly, and so is `mouseExited` below: a tracking area sends its
    /// owner `mouseMoved:`, but the selector Swift derives for `mouseMoved(with:)`
    /// on a class that is not an `NSResponder` is `mouseMovedWith:`. AppKit checks
    /// before sending and skips an owner that does not respond, so with the derived
    /// name the tracking area was installed and no hover ever reached this.
    @objc(mouseMoved:)
    private func mouseMoved(with event: NSEvent) {
      let location = NSEvent.mouseLocation
      // Before `wantsTarget`, which asks it too: a move right after VoiceOver is
      // turned off must hit-test.
      readVoiceOver()
      let hit = state.wantsTarget(at: location) ? target(event.locationInWindow) : nil
      send(.pointerMoved(location: location, target: hit))
    }

    /// Read per event rather than observed: it is a property read, and so follows
    /// VoiceOver being turned on or off mid-document.
    private func readVoiceOver() {
      state.previewsOnHover = !NSWorkspace.shared.isVoiceOverEnabled
    }

    @objc(mouseExited:)
    private func mouseExited(with event: NSEvent) {
      send(.pointerExited)
    }

    private func startDwell(_ dwell: ReferenceHover.Dwell) {
      dwellTask?.cancel()
      dwellTask = Task { [weak self] in
        try? await Task.sleep(for: .milliseconds(500))
        guard !Task.isCancelled, let self else { return }
        self.dwellTask = nil
        switch dwell {
        case .card:
          self.send(.cardDwellElapsed(buttonPressed: NSEvent.pressedMouseButtons != 0))
        case .restingPointer:
          self.send(.restingDwellElapsed(target: self.restingTarget()))
        }
      }
    }

    // MARK: - Popover

    /// Each popover is shown here and the rules told once it is on screen, so the
    /// two cannot disagree about whether one is up.
    private func showCard(_ target: HoverTarget) {
      guard let card = card(target), present(card) else { return }
      send(.cardShown)
    }

    private func showDocumentPreview(_ target: HoverTarget) {
      guard let preview = documentPreview(target), present(preview) else { return }
      send(.documentPreviewShown)
    }

    /// A heading's backlinks (#183), opened by the click on its caption, which has
    /// already ended whatever was timing or showing.
    func showBacklinks(_ list: Popover) {
      guard present(list) else { return }
      send(.backlinksShown)
    }

    /// Shared by the card, the document preview and the backlinks, so the popovers
    /// are anchored and dismissed the same way. False when there is no text view to
    /// anchor to.
    private func present(_ content: Popover) -> Bool {
      guard let textView else { return false }
      let shown = NSPopover()
      shown.behavior = .transient
      shown.delegate = self
      shown.contentViewController = content.content
      if let size = content.size { shown.contentSize = size }
      let anchor = content.anchor.offsetBy(
        dx: textView.textContainerOrigin.x, dy: textView.textContainerOrigin.y)
      shown.show(relativeTo: anchor, of: textView, preferredEdge: .maxY)
      popover = shown
      return true
    }

    /// A transient popover also closes on its own — Esc, a click elsewhere, the app
    /// going to the background. Only for the popover still current: one closed by
    /// the rules has been replaced or dropped already, and its close may land after
    /// the next hover began.
    func popoverDidClose(_ notification: Notification) {
      guard let closed = notification.object as? NSPopover, closed === popover else { return }
      popover = nil
      send(.popoverClosedItself)
    }
  }
#endif
