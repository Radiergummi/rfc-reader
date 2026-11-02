#if os(macOS)
  import AppKit
  import RFCReaderKit
  import SwiftUI

  /// Tells a SwiftUI view about a force click on it, which SwiftUI has no gesture for:
  /// the References panel's rows preview their RFC on one, as a reference in the
  /// prose does (#580).
  ///
  /// A background that takes no clicks of its own. It watches the window's pressure
  /// events through a local monitor, which sees them even while the row's button is
  /// tracking the click, and reports when a click that began inside it presses
  /// through to the second stage there. The button is left the click, and asks the
  /// same `ForceClickTracker` whether its release opens the RFC: not the release of
  /// the click that opened the preview.
  struct ForceClickReader: NSViewRepresentable {
    /// The row's, which its button asks too.
    let tracker: ForceClickTracker
    /// A click pressed through.
    let report: () -> Void

    func makeNSView(context: Context) -> MonitorView {
      MonitorView()
    }

    func updateNSView(_ view: MonitorView, context: Context) {
      view.tracker = tracker
      view.report = report
    }

    /// A view freed with its window never moves out of it, and its monitor would
    /// outlive it.
    static func dismantleNSView(_ view: MonitorView, coordinator: ()) {
      view.stopWatching()
    }

    final class MonitorView: NSView {
      var tracker: ForceClickTracker?
      var report: () -> Void = {}
      private var monitor: Any?

      override func hitTest(_ point: NSPoint) -> NSView? { nil }

      override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        stopWatching()
        guard window != nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(
          matching: [.leftMouseDown, .leftMouseUp, .pressure]
        ) {
          [weak self] event in
          self?.handle(event)
          return event
        }
      }

      func stopWatching() {
        if let monitor {
          NSEvent.removeMonitor(monitor)
          self.monitor = nil
        }
      }

      private func handle(_ event: NSEvent) {
        // The part of the row on screen: a row scrolled out of the list is still in
        // the window, under the panel's titlebar or past its end. Below the toolbar
        // too: the window's content runs under it (`.fullSizeContentView`), so a row
        // scrolled up there is "visible" beneath a toolbar item's click.
        guard let window, let tracker else { return }
        let isInside =
          event.window === window
          && window.contentLayoutRect.contains(event.locationInWindow)
          && visibleRect.contains(convert(event.locationInWindow, from: nil))
        let tracked: ForceClickTracker.Event
        switch event.type {
        case .leftMouseDown: tracked = .mouseDown(inside: isInside)
        case .leftMouseUp: tracked = .mouseUp
        case .pressure: tracked = .pressure(stage: event.stage, inside: isInside)
        default: return
        }
        if tracker.handle(tracked) {
          report()
        }
      }
    }
  }
#endif
