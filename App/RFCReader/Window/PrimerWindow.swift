#if os(macOS)
  import AppKit
  import RFCReaderKit
  import SwiftUI

  /// The primer's one window on macOS (#365), opened from a glossary popover or the
  /// empty reader, and brought forward rather than made again.
  ///
  /// A window of its own rather than a sheet: a popover cannot present one, and the
  /// primer is read beside a document, not instead of it. Its hosted root reads no
  /// model, so it needs none handed to it.
  enum PrimerWindow {
    private static var window: NSWindow?

    static func show() {
      let window = window ?? make()
      Self.window = window
      window.makeKeyAndOrderFront(nil)
    }

    private static func make() -> NSWindow {
      let window = NSWindow(
        contentViewController: NSHostingController(rootView: ScrollView { PrimerView() }))
      window.title = Glossary.primer().title
      window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
      window.isReleasedWhenClosed = false
      window.setContentSize(NSSize(width: 520, height: 640))
      window.center()
      window.setFrameAutosaveName("Primer")
      return window
    }
  }
#endif
