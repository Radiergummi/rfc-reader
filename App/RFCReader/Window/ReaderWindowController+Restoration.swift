#if os(macOS)
  import AppKit
  import RFCReaderKit

  /// Windows that come back on the next launch (#155), through AppKit's own state
  /// restoration: AppKit keeps each window's frame, its place in its tab group and
  /// what it encodes here, and on launch asks `ReaderWindowRestoration` for each one.
  ///
  /// AppKit's, so it follows the user's choice: with "Close windows when quitting an
  /// application" on, nothing comes back, and quitting with Option held keeps them
  /// all the same, as in every other document app.
  extension ReaderWindowController {
    static let restorationIdentifier = NSUserInterfaceItemIdentifier("reader")
    private static let sceneKey = "scene"

    /// What this tab keeps; see `SceneSnapshot`: its navigation, and the window's
    /// panel and columns (#762).
    var sceneSnapshot: SceneSnapshot {
      // Each part as the window shows it, except the parts of a restored layout not
      // yet put back, which the window would otherwise lose to its defaults.
      let widths = splitController.columnWidths
      let pending = restoredLayout
      let layout = WindowLayout(
        panelIsOpen: restoresPanel ? pending?.panelIsOpen ?? false : isPanelOpen,
        pane: reader.pane,
        sidebarWidth: restoresColumns ? pending?.sidebarWidth : widths.sidebar,
        listWidth: restoresColumns ? pending?.listWidth : widths.list)
      return navigation.snapshot(inspectorTab: reader.tab, layout: layout)
    }

    func makeRestorable(_ window: NSWindow) {
      window.identifier = Self.restorationIdentifier
      window.isRestorable = true
      window.restorationClass = ReaderWindowRestoration.self
    }

    func window(_ window: NSWindow, willEncodeRestorableState state: NSCoder) {
      state.encode(sceneSnapshot.encoded(), forKey: Self.sceneKey)
    }

    func window(_ window: NSWindow, didDecodeRestorableState state: NSCoder) {
      guard let data = state.decodeObject(of: NSData.self, forKey: Self.sceneKey),
        let snapshot = SceneSnapshot.decoded(from: data as Data)
      else { return }
      navigation.restore(snapshot, into: reader)
      guard let layout = snapshot.layout else { return }
      reader.pane = layout.pane
      // Neither yet: the columns are put back once the window is laid out, when it
      // first becomes key, and an open panel only over a document, which has not
      // loaded; `closePanelWithoutDocument()` opens it once there is one. A shut
      // panel is already as it was.
      restoredLayout = layout
      restoresColumns = true
      restoresPanel = layout.panelIsOpen
    }
  }

  /// Makes the windows AppKit restores at launch. AppKit decodes each one's state
  /// into it afterwards, through its delegate, and puts it back in its tab group.
  final class ReaderWindowRestoration: NSObject, NSWindowRestoration {
    static func restoreWindow(
      withIdentifier identifier: NSUserInterfaceItemIdentifier, state: NSCoder,
      completionHandler: @escaping (NSWindow?, (any Error)?) -> Void
    ) {
      // `shared`, not `NSApp.delegate`: under `@NSApplicationDelegateAdaptor` that is
      // SwiftUI's own delegate, which forwards to ours.
      guard identifier == ReaderWindowController.restorationIdentifier,
        let delegate = AppDelegate.shared
      else {
        completionHandler(nil, nil)
        return
      }
      completionHandler(delegate.restoredWindow(), nil)
    }
  }
#endif
