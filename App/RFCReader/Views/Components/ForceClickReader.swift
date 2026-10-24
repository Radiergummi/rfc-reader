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
  /// tracking the click, and reports when a click begins inside it and when that
  /// click presses through to the second stage there (`ForceClickTracker`). The
  /// button is left the click, so its action can tell that the click that opened the
  /// preview is not also one that opens the RFC.
  struct ForceClickReader: NSViewRepresentable {
    /// A click began inside.
    let pressed: () -> Void
    /// That click pressed through.
    let report: () -> Void

    func makeNSView(context: Context) -> ReaderView {
      ReaderView()
    }

    func updateNSView(_ view: ReaderView, context: Context) {
      view.pressed = pressed
      view.report = report
    }

    /// A view freed with its window never moves out of it, and its monitor would
    /// outlive it.
    static func dismantleNSView(_ view: ReaderView, coordinator: ()) {
      view.stopWatching()
    }

    final class ReaderView: NSView {
      var pressed: () -> Void = {}
      var report: () -> Void = {}
      private var monitor: Any?
      private var tracker = ForceClickTracker()

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
        // the window, under the panel's titlebar or past its end.
        let isInside =
          event.window === window
          && visibleRect.contains(convert(event.locationInWindow, from: nil))
        let tracked: ForceClickTracker.Event
        switch event.type {
        case .leftMouseDown: tracked = .mouseDown(inside: isInside)
        case .leftMouseUp: tracked = .mouseUp
        case .pressure: tracked = .pressure(stage: event.stage, inside: isInside)
        default: return
        }
        switch tracker.handle(tracked) {
        case .pressBegan: pressed()
        case .forceClick: report()
        case nil: break
        }
      }
    }
  }
#endif
