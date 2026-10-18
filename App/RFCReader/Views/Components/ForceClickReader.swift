#if os(macOS)
  import AppKit
  import SwiftUI

  /// Tells a SwiftUI view about a force click on it, which SwiftUI has no gesture for:
  /// the References panel's rows preview their RFC on one, as a reference in the
  /// prose does (#580).
  ///
  /// A background that takes no clicks of its own. It watches the window's pressure
  /// events through a local monitor, which sees them even while the row's button is
  /// tracking the click, and reports when a click that began inside it presses
  /// through to the second stage there. The button is left the click, so its action
  /// can tell that the click that opened the preview is not also one that opens the
  /// RFC.
  struct ForceClickReader: NSViewRepresentable {
    let report: () -> Void

    func makeNSView(context: Context) -> ReaderView {
      ReaderView()
    }

    func updateNSView(_ view: ReaderView, context: Context) {
      view.report = report
    }

    final class ReaderView: NSView {
      var report: () -> Void = {}
      private var monitor: Any?
      /// Whether the mouse went down inside, and is still down: a press dragged in
      /// from elsewhere is not a click on this row.
      private var isPressing = false
      /// Whether this click has reported its force click already: stage 2 arrives
      /// again with every change of pressure past it.
      private var hasReported = false

      override func hitTest(_ point: NSPoint) -> NSView? { nil }

      override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let monitor {
          NSEvent.removeMonitor(monitor)
          self.monitor = nil
        }
        guard window != nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(
          matching: [.leftMouseDown, .leftMouseUp, .pressure]
        ) {
          [weak self] event in
          self?.handle(event)
          return event
        }
      }

      private func handle(_ event: NSEvent) {
        let isInside =
          event.window === window && bounds.contains(convert(event.locationInWindow, from: nil))
        switch event.type {
        case .leftMouseDown:
          isPressing = isInside
          hasReported = false
        case .leftMouseUp:
          isPressing = false
        case .pressure where isPressing && isInside && event.stage >= 2 && !hasReported:
          hasReported = true
          report()
        default:
          break
        }
      }
    }
  }
#endif
