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

    /// What this tab keeps; see `SceneSnapshot`.
    var sceneSnapshot: SceneSnapshot {
      navigation.snapshot(inspectorTab: reader.tab)
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
      navigation.restore(snapshot)
      reader.tab = snapshot.inspectorTab.flatMap(InspectorTab.init(rawValue:)) ?? reader.tab
    }
  }

  /// Makes the windows AppKit restores at launch. AppKit decodes each one's state
  /// into it afterwards, through its delegate, and puts it back in its tab group.
  final class ReaderWindowRestoration: NSObject, NSWindowRestoration {
    static func restoreWindow(
      withIdentifier identifier: NSUserInterfaceItemIdentifier, state: NSCoder,
      completionHandler: @escaping (NSWindow?, (any Error)?) -> Void
    ) {
      guard identifier == ReaderWindowController.restorationIdentifier,
        let delegate = NSApp.delegate as? AppDelegate
      else {
        completionHandler(nil, nil)
        return
      }
      completionHandler(delegate.restoredWindow(), nil)
    }
  }
#endif
