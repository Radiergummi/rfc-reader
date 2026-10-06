#if !canImport(UIKit)
  import AppKit
  import RFCKit
  import RFCReaderKit
  import SwiftUI

  extension RFCTextViewCoordinator {
    /// Hands the controller the text view and what only the document knows: where a
    /// reference is, what its card says, and what rests under the pointer.
    func setUpHover() {
      guard let textView else { return }
      hover.attach(to: textView)
      hover.target = { [weak self] point in self?.reference(atWindowPoint: point) }
      hover.restingTarget = { [weak self] in self?.referenceUnderRestingPointer() }
      hover.card = { [weak self] target in
        guard let self, let environment = self.environment,
          let preview = self.preview(for: target.box.reference),
          let rect = self.referenceRect(for: target.range)
        else { return nil }
        return ReferenceHoverController.Popover(
          content: NSHostingController(rootView: preview.readerEnvironment(environment)),
          anchor: rect)
      }
      hover.documentPreview = { [weak self] target in self?.documentPreview(for: target) }
    }

    /// Called from `dismantleNSView`.
    func tearDownHoverTracking() {
      hover.tearDown()
    }

    private func referenceUnderRestingPointer() -> HoverTarget? {
      guard NSApp.isActive, NSEvent.pressedMouseButtons == 0, let textView,
        let window = textView.window
      else { return nil }
      let point = window.mouseLocationOutsideOfEventStream
      guard textView.visibleRect.contains(textView.convert(point, from: nil)) else { return nil }
      return reference(atWindowPoint: point)
    }

    /// Force click on a reference: Safari's link preview, for documents (#29) — the
    /// document it names, readable and scrollable, at the place it names. A
    /// bibliography entry that names no RFC has no document of ours to show, and
    /// gets its card instead. Anywhere else, and on a reference with neither, it
    /// returns false and `ReaderTextView` hands the event on to AppKit's Look Up.
    /// So does Look Up from the keyboard, which means the selection, not whatever
    /// the pointer happens to rest on — and a key event has no location to test.
    /// So does an event from any other window, such as a menu's: its location is
    /// in that window's coordinates, not the text view's.
    func quickLookReference(with event: NSEvent) -> Bool {
      guard event.type != .keyDown,
        let textView, event.window === textView.window,
        let target = reference(atWindowPoint: event.locationInWindow),
        let forceClick = forceClick(on: target)
      else { return false }
      hover.send(forceClick)
      return true
    }

    /// What a force click on the reference at `characterIndex` shows, or nil where it
    /// shows nothing of ours; the link menu's Preview offers the same (#776).
    func forceClick(at characterIndex: Int) -> ReferenceHover.Event? {
      reference(at: characterIndex).flatMap {
        forceClick(on: HoverTarget(box: $0.box, range: $0.range))
      }
    }

    private func forceClick(on target: HoverTarget) -> ReferenceHover.Event? {
      guard commitsOnClick == nil, let documentID,
        let url = link(at: target.range.location),
        let resolved = LinkPreview.resolve(
          target.box.reference, linkedTo: url, from: documentID, in: environment?.library.index)
      else { return nil }
      switch resolved {
      case .card:
        guard preview(for: target.box.reference) != nil else { return nil }
        return .forceClickCard(target)
      case .document:
        guard environment != nil, referenceRect(for: target.range) != nil else { return nil }
        return .forceClickDocument(target)
      }
    }

    /// The link a click on the reference under `event` follows, and the character
    /// it is on, or nil when the mouse-down is on no reference. `ReaderTextView`
    /// tracks a click on a reference itself, to see its force click (#29). Not in a
    /// link preview's reader, whose clicks commit the preview.
    func referenceLink(under event: NSEvent) -> (link: Any, characterIndex: Int)? {
      guard commitsOnClick == nil, let textView, event.window === textView.window,
        let target = reference(atWindowPoint: event.locationInWindow),
        let url = link(at: target.range.location)
      else { return nil }
      return (url, target.range.location)
    }

    /// The preview is a reader of its own — its own text view and storage, built by
    /// `DocumentTextBuilder` — in a popover beside the reference. A click in it does
    /// what a click on the reference would have, with the modifiers held for it,
    /// and closes it. Nil for a reference that names no document of ours.
    private func documentPreview(for target: HoverTarget) -> ReferenceHoverController.Popover? {
      guard let documentID, let environment, let url = link(at: target.range.location),
        case .document(let id, let place)? = LinkPreview.resolve(
          url, from: documentID, in: environment.library.index),
        let rect = referenceRect(for: target.range)
      else { return nil }
      let preview = DocumentPreview(library: environment.library, id: id, place: place) {
        [weak self] in
        guard let self else { return }
        let sameDocument = id == self.documentID
        // The popover fades out as the reader moves, not before it: waiting for the
        // fade to finish left the reader standing still behind it. And a click, as
        // far as the reader is concerned: the scroll it causes must not preview
        // whatever lands under the pointer, which is now over the reader.
        self.hover.send(.previewCommitted(pointer: NSEvent.mouseLocation))
        if sameDocument {
          _ = self.onLink(url, .current)
        } else {
          // Another document replaces this one; `ReaderHost` cross-fades the two.
          withAnimation(Self.documentCrossFade) { _ = self.onLink(url, .current) }
        }
      }
      let host = NSHostingController(rootView: preview.readerEnvironment(environment))
      return ReferenceHoverController.Popover(
        content: host, size: preview.size, anchor: rect)
    }

    /// The reference under a point in window coordinates. `textContainerOrigin` is
    /// the inset: the view is flipped, so subtracting it is all it takes to reach
    /// container space.
    private func reference(atWindowPoint point: NSPoint) -> HoverTarget? {
      guard let textView else { return nil }
      let viewPoint = textView.convert(point, from: nil)
      return reference(
        at: CGPoint(
          x: viewPoint.x - textView.textContainerOrigin.x,
          y: viewPoint.y - textView.textContainerOrigin.y)
      ).map { HoverTarget(box: $0.box, range: $0.range) }
    }

    private func reference(at containerPoint: CGPoint) -> (box: ReferenceBox, range: NSRange)? {
      characterOffset(atContainerPoint: containerPoint).flatMap { reference(at: $0) }
    }

    /// The rect of a reference's run, in text-container coordinates — the
    /// popover's anchor. `enumerateTextSegments` folds a run that wraps across
    /// lines into the right set of rects on its own, the same as it does for
    /// selection rendering.
    func referenceRect(for range: NSRange) -> CGRect? {
      guard let layout = textView?.textLayoutManager,
        let textRange = layout.textRange(for: range)
      else { return nil }
      var union: CGRect?
      layout.enumerateTextSegments(in: textRange, type: .standard) { _, frame, _, _ in
        union = union.map { $0.union(frame) } ?? frame
        return true
      }
      return union
    }
  }
#endif
