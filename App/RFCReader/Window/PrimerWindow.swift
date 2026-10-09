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
      let hosting = NSHostingController(rootView: ScrollView { PrimerView() })
      // The window's size is the one set below or last left at, not one the content
      // reports, as for every other hosted root (ReaderWindowController.host).
      hosting.sizingOptions = []
      let window = NSWindow(contentViewController: hosting)
      window.title = Glossary.primerTitle()
      window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
      window.isReleasedWhenClosed = false
      // Over a reader in full screen rather than on a Space of its own, which would
      // hide the document it is read beside; and on the Space it is opened from.
      window.collectionBehavior = [.fullScreenAuxiliary, .moveToActiveSpace]
      // Not a reader, so not a tab of one: the reader windows' tab commands would
      // otherwise reach it.
      window.tabbingMode = .disallowed
      window.setContentSize(NSSize(width: 520, height: 640))
      window.center()
      window.setFrameAutosaveName("Primer")
      return window
    }
  }
#endif
