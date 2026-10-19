#if os(macOS)
  import AppKit
  import RFCReaderKit
  import SwiftUI

  /// RFC Reader Help's one window on macOS (#780), opened from the Help menu or a
  /// search field's "Search Syntax…", and brought forward rather than made again, as
  /// the primer's is (`PrimerWindow`). Its hosted root reads no model, so it needs
  /// none handed to it.
  enum HelpWindow {
    private static var window: NSWindow?

    /// Shows the help, at `section` when one is given.
    static func show(at section: HelpSection? = nil) {
      let window = window ?? make()
      Self.window = window
      // A new target each time, so asking again for a section scrolls back to it.
      (window.contentViewController as? NSHostingController<HelpView>)?.rootView = HelpView(
        target: HelpTarget(section: section))
      window.makeKeyAndOrderFront(nil)
    }

    private static func make() -> NSWindow {
      let hosting = NSHostingController(rootView: HelpView())
      // The window's size is the one set below or last left at, not one the content
      // reports, as for every other hosted root (ReaderWindowController.host).
      hosting.sizingOptions = []
      let window = NSWindow(contentViewController: hosting)
      window.title = HelpContent.title()
      window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
      window.isReleasedWhenClosed = false
      // Over a reader in full screen rather than on a Space of its own, and on the
      // Space it is opened from, as the primer's.
      window.collectionBehavior = [.fullScreenAuxiliary, .moveToActiveSpace]
      // Not a reader, so not a tab of one.
      window.tabbingMode = .disallowed
      window.setContentSize(NSSize(width: 560, height: 680))
      window.center()
      window.setFrameAutosaveName("Help")
      return window
    }
  }
#endif
