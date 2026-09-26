#if os(macOS)
  import AppKit
  import Observation
  import RFCKit

  /// Makes windows, because nothing else does any more.
  ///
  /// The app's only scene on macOS is `Settings`, which still gives us the menu bar and
  /// everything `.commands` declares — measured — but contributes no windows. Every
  /// reader window is created here and kept here: an `NSWindowController` with no owner
  /// is deallocated the moment the call that made it returns.
  @MainActor
  final class AppDelegate: NSObject, NSApplicationDelegate {
    private(set) static weak var shared: AppDelegate?

    private var controllers: [ReaderWindowController] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
      Self.shared = self
      // The scene's `.task` did this; there is no scene on macOS any more.
      Task { await LibraryModel.shared.bootstrap() }
      openWindow(tabbedWith: nil, inBackground: false)
    }

    /// The dock icon, with every window closed.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
      if !hasVisibleWindows {
        openWindow(tabbedWith: nil, inBackground: false)
      }
      return true
    }

    /// `rfc://9110/section/4.2`, plus rfc-editor.org and datatracker links handed over
    /// by the share sheet.
    ///
    /// This was `onOpenURL` on the scene. With no `WindowGroup` there is no scene to
    /// declare it on — and this is the better place regardless, because the routing
    /// decision was never the view's: `LibraryModel` holds the registry of open tabs
    /// and picks exactly one to act on the link.
    func application(_ application: NSApplication, open urls: [URL]) {
      for url in urls {
        guard let link = RFCLink(url: url) else { continue }
        if controllers.isEmpty {
          openWindow(tabbedWith: nil, inBackground: false)
        }
        LibraryModel.shared.route(link)
      }
    }

    /// Opens a window as a tab of the window the user is looking at — ⌘T, the tab
    /// bar's `+`, and a link that asked for a tab of its own.
    func openTab(inBackground: Bool) {
      openWindow(tabbedWith: activeController, inBackground: inBackground)
    }

    /// Opens a window, as a tab of `sibling` when there is one.
    func openWindow(tabbedWith sibling: ReaderWindowController?, inBackground: Bool) {
      let controller = ReaderWindowController(library: LibraryModel.shared)
      // Only the first window of the session remembers its frame: an autosave name
      // belongs to one window, and sharing it across tabs mangles all of them.
      if controllers.isEmpty {
        controller.window?.setFrameAutosaveName("ReaderWindow")
      }
      controllers.append(controller)

      if let host = sibling?.window, let fresh = controller.window {
        host.addTabbedWindow(fresh, ordered: .above)
        if inBackground {
          // The new tab is ordered front as part of being made, so taking the
          // focus back any sooner is simply undone by it.
          host.makeKeyAndOrderFront(nil)
        } else {
          fresh.makeKeyAndOrderFront(nil)
        }
        // Ordering a window into a tab group is what copies the group's inspector
        // state onto it, so this is the one moment the panel's rule can be broken
        // by something other than the document changing — and the one place that
        // has to put it back. See `closePanelWithoutDocument()` for the readings.
        controller.closePanelWithoutDocument()
      } else {
        controller.showWindow(nil)
      }
    }

    /// A window controller owns its window, so a closed tab lives until this runs.
    /// Called from `windowWillClose(_:)` rather than inferred from visibility: a
    /// window that has been made but not yet shown is not visible either, and
    /// treating that as closed emptied the registry between making the first window
    /// and showing it — so the `rfc://` link that followed opened a second one.
    func forget(_ controller: ReaderWindowController) {
      controllers.removeAll { $0 === controller }
    }

    /// The window the menu and the actions both act on.
    ///
    /// `ActiveReaderWindow` is the one answer to this: it holds the reader that was
    /// made key last, which is still the right one when the key window is a sheet
    /// over it or the settings beside it. The fallback covers the only case it
    /// cannot — that window having closed.
    var activeController: ReaderWindowController? {
      ActiveReaderWindow.shared.controller
        ?? NSApp.orderedWindows.lazy.compactMap(ReaderWindowController.controller(for:)).first
    }
  }

  /// Which window the menu acts on.
  ///
  /// Menu items used to find their target with `@FocusedValue`, published by
  /// `ContentView` with `focusedSceneValue`. Measured on this build: with the reader's
  /// views hosted in `NSHostingController`s rather than in a scene, those values never
  /// resolve — ⌘L opened nothing at all. The key window is the better question anyway:
  /// Back means the tab you are looking at.
  ///
  /// Written by `ReaderWindowController`, which is its window's delegate, rather than
  /// by a notification observer: a `Notification` cannot cross an isolation boundary
  /// under strict concurrency, and the delegate is already on the main actor.
  @Observable
  @MainActor
  final class ActiveReaderWindow {
    static let shared = ActiveReaderWindow()

    private(set) var controller: ReaderWindowController?

    private init() {}

    func becameKey(_ controller: ReaderWindowController) {
      self.controller = controller
    }

    func willClose(_ controller: ReaderWindowController) {
      guard self.controller === controller else { return }
      self.controller = nil
    }
  }
#endif
