#if os(macOS)
  import AppKit
  import SwiftUI

  /// Tells a SwiftUI view about a force click on it, which SwiftUI has no gesture for:
  /// the References panel's rows preview their RFC on one, as a reference in the
  /// prose does (#580).
  ///
  /// A background that takes no clicks of its own. It watches the window's pressure
  /// events through a local monitor, which sees them even while the row's button is
  /// tracking the click, and reports `true` when one inside it reaches the second
  /// stage, and `false` at the mouse-down of every click inside it. The button is
  /// left the click, so its action reads what was reported and does nothing after a
  /// force click: the click that pressed through to the preview is not also a click
  /// that opens the RFC.
  struct ForceClickReader: NSViewRepresentable {
    let report: (Bool) -> Void

    func makeNSView(context: Context) -> ReaderView {
      ReaderView()
    }

    func updateNSView(_ view: ReaderView, context: Context) {
      view.report = report
    }

    final class ReaderView: NSView {
      var report: (Bool) -> Void = { _ in }
      private var monitor: Any?
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
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .pressure]) {
          [weak self] event in
          self?.handle(event)
          return event
        }
      }

      private func handle(_ event: NSEvent) {
        guard event.window === window,
          bounds.contains(convert(event.locationInWindow, from: nil))
        else { return }
        switch event.type {
        case .leftMouseDown:
          hasReported = false
          report(false)
        case .pressure where event.stage >= 2 && !hasReported:
          hasReported = true
          report(true)
        default:
          break
        }
      }
    }
  }
#endif
