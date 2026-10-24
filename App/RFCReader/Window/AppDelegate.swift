#if os(macOS)
  import AppKit
  import Observation
  import RFCKit
  import RFCReaderKit
  import os

  /// Makes windows, because nothing else does any more.
  ///
  /// The app's only scene on macOS is `Settings`, which still gives us the menu bar and
  /// everything `.commands` declares — measured — but contributes no windows. Every
  /// reader window is created here and kept here: an `NSWindowController` with no owner
  /// is deallocated the moment the call that made it returns.
  final class AppDelegate: NSObject, NSApplicationDelegate, WindowOpening {
    /// The one AppKit made, for what opens or forgets a window and has no owner to be
    /// handed it by: File ▸ New Window and New Tab, which SwiftUI makes, and a window
    /// controller closing. A singleton because AppKit's delegate is one, and the
    /// menus need a single target (#139).
    private(set) static weak var shared: AppDelegate?

    private(set) var controllers: [ReaderWindowController] = []

    /// The Services' provider (#195), kept here because `NSApp.servicesProvider` does
    /// not retain it.
    private let citationServices = CitationServices()

    /// Before AppKit restores the last session's windows (#155), which come back
    /// through `restoredWindow()` between this and `applicationDidFinishLaunching`.
    func applicationWillFinishLaunching(_ notification: Notification) {
      Self.shared = self
      signposter.emitEvent("Launched")
      // Before anything can route a link, since routing may need a window.
      LibraryModel.shared.windows = self
      // Before launch finishes, which is when a tap on a notification that launched
      // the app is delivered (#191).
      BookmarkNotifications.install()
      // Before any window, whose toolbar observes its tips (#782).
      ReaderTips.configure()
      NSApp.servicesProvider = citationServices
      // Before the first window, so it is made in the appearance and the page
      // themes chosen (#704).
      AppAppearance.follow()
      ReaderPalette.follow()
      // The scene's `.task` did this; there is no scene on macOS any more.
      // Immediate, so that the bootstrap has started reading the cached index by
      // the time the first window is made (#367), restored or not. A plain task
      // waited for the window, and the list for both, one after the other.
      Task.immediate(name: "Bootstrap library") { await LibraryModel.shared.bootstrap() }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
      // A window of its own only when none came back from the last session, and only
      // for a launch from the Finder or the Dock (#762): a script, a Shortcut or an
      // intent that launched the app to ask it something left a window behind. A
      // link that launched it makes the window it needs (`LibraryModel.route(_:)`).
      let isDefaultLaunch =
        notification.userInfo?[NSApplication.launchIsDefaultUserInfoKey] as? Bool ?? true
      if controllers.isEmpty, isDefaultLaunch {
        openWindow(tabbedWith: nil, inBackground: false)
        signposter.emitEvent("First window made")
      }
      warnIfTheStoreDidNotOpen()
      // Made by the menu's commands as a rule, which come first; made here if not, so
      // the scheduled checks never wait on the menu.
      _ = Updater.shared
    }

    /// Once, at launch, when the bookmarks store fell back to memory (#152):
    /// Continue to read without saving, or Quit to fix whatever kept it closed and
    /// try again.
    ///
    /// A sheet on the first window rather than `runModal()`: a modal loop here would
    /// keep `applicationDidFinishLaunching` from returning, and with it the `rfc://`
    /// link the app was launched with.
    private func warnIfTheStoreDidNotOpen() {
      guard let window = controllers.first?.window, AppData.claimStoreWarning() else { return }
      let alert = NSAlert()
      alert.alertStyle = .warning
      alert.messageText = AppData.storeWarning.title
      alert.informativeText = AppData.storeWarning.message
      alert.addButton(withTitle: String(localized: "Continue"))
      alert.addButton(withTitle: String(localized: "Quit"))
      alert.beginSheetModal(for: window) { response in
        if response == .alertSecondButtonReturn {
          NSApp.terminate(nil)
        }
      }
    }

    /// The dock icon, with every window closed, or every reader window: the primer's
    /// window or the settings left open alone do not count as one (#365). AppKit
    /// brings back a minimized window only when no window at all is visible, so with
    /// one of those open a minimized reader is brought back here.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
      if !hasVisibleWindows {
        openWindow(tabbedWith: nil, inBackground: false)
      } else {
        let readers = controllers.compactMap(\.window)
        if !readers.contains(where: \.isVisible) {
          if let minimized = readers.first(where: \.isMiniaturized) {
            minimized.deminiaturize(nil)
          } else {
            openWindow(tabbedWith: nil, inBackground: false)
          }
        }
      }
      return true
    }

    /// `rfc://9110#section-4.2`, plus rfc-editor.org and datatracker links handed over
    /// by the share sheet.
    ///
    /// This was `onOpenURL` on the scene. With no `WindowGroup` there is no scene to
    /// declare it on — and this is the better place regardless, because the routing
    /// decision was never the view's: `LibraryModel` holds the registry of open tabs
    /// and picks exactly one to act on the link.
    func application(_ application: NSApplication, open urls: [URL]) {
      for url in urls {
        // An RFC, or a draft (#728).
        guard let link = ReadableLink(url: url) else { continue }
        LibraryModel.shared.route(link)
      }
    }

    /// An RFC chosen in Spotlight (#178), routed the way a link from outside is.
    func application(
      _ application: NSApplication, continue userActivity: NSUserActivity,
      restorationHandler: @escaping ([any NSUserActivityRestoring]) -> Void
    ) -> Bool {
      guard let id = SpotlightEntry.documentID(from: userActivity) else { return false }
      LibraryModel.shared.route(RFCLink(id: id))
      return true
    }

    /// Opens a window as a tab of the window the user is looking at — ⌘T, the tab
    /// bar's `+`, and a link that asked for a tab of its own.
    func openTab(inBackground: Bool) {
      openWindow(tabbedWith: activeController, inBackground: inBackground)
    }

    /// A window of its own, whatever the user's "Prefer tabs" setting: a link or a
    /// script that asked for one (`LibraryModel.Placement.newWindow`).
    func openWindow() {
      openWindow(tabbedWith: nil, inBackground: false, standsAlone: true)
    }

    var activeNavigation: NavigationModel? { activeController?.navigation }

    /// Brings the window showing `scene` forward, selecting it within its tab group.
    func bringForward(_ scene: NavigationModel) {
      let controller = controllers.first { $0.navigation === scene }
      controller?.window?.makeKeyAndOrderFront(nil)
    }

    /// Opens a window, as a tab of `sibling` when there is one. Without one, AppKit
    /// tabs it into the front group where the user prefers tabs, unless it
    /// `standsAlone`.
    func openWindow(
      tabbedWith sibling: ReaderWindowController?, inBackground: Bool, standsAlone: Bool = false
    ) {
      let controller = ReaderWindowController(library: LibraryModel.shared)
      // Only the first window of the session remembers its frame: an autosave name
      // belongs to one window, and sharing it across tabs mangles all of them.
      if controllers.isEmpty {
        controller.window?.setFrameAutosaveName("ReaderWindow")
        // Naming it puts the saved frame back, unchecked against the floor.
        controller.splitController.applyMinimumWidth()
      }
      controllers.append(controller)
      // On the first window: a launch by a script or a link has none until one is
      // asked for. The warning is claimed once, so later windows show nothing.
      defer { warnIfTheStoreDidNotOpen() }

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
      } else if let fresh = controller.window {
        // Disallowed only while it is shown, which is when AppKit decides: tabs can
        // still be added to it afterwards.
        if standsAlone { fresh.tabbingMode = .disallowed }
        controller.showWindow(nil)
        fresh.tabbingMode = .automatic
        // Where the user prefers tabs, AppKit ordered it into the front group, which
        // copies the group's panel onto it, as `addTabbedWindow` does above.
        controller.closePanelWithoutDocument()
      }
    }

    /// A window from the last session, for AppKit to put back where it was: AppKit
    /// gives it its frame and its tab group, and shows it.
    func restoredWindow() -> NSWindow? {
      let controller = ReaderWindowController(library: LibraryModel.shared)
      controller.correctsPanelOnFirstKey = true
      if controllers.isEmpty { signposter.emitEvent("First window made") }
      controllers.append(controller)
      return controller.window
    }

    /// The windows' restorable state is a `SceneSnapshot` as data, which secure
    /// coding decodes as plainly as anything.
    func applicationSupportsSecureCoding(_ app: NSApplication) -> Bool {
      true
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
  final class ActiveReaderWindow {
    /// One per process, as the menu bar is: SwiftUI makes the commands that read it,
    /// with no way to hand them anything, and the key window is a single target
    /// (#139).
    static let shared = ActiveReaderWindow()

    private(set) var controller: ReaderWindowController?
    /// Whether the key window's sidebar is collapsed, for the title of View ▸ Show
    /// Sidebar. A SwiftUI menu item cannot ask the split view when the menu opens,
    /// so the window reports it here.
    private(set) var isSidebarCollapsed = false
    /// Whether the key window's panel is open, for the titles of View ▸ Show
    /// Contents and Show Info (#761), reported for the same reason.
    private(set) var isPanelOpen = false

    private init() {}

    func becameKey(_ controller: ReaderWindowController) {
      self.controller = controller
      isSidebarCollapsed = controller.splitController.isSidebarCollapsed
      isPanelOpen = controller.isPanelOpen
    }

    /// The sidebar or the panel opened or closed: both resize the subviews.
    func layoutChanged(_ controller: ReaderWindowController) {
      guard self.controller === controller else { return }
      isSidebarCollapsed = controller.splitController.isSidebarCollapsed
      isPanelOpen = controller.isPanelOpen
    }

    func willClose(_ controller: ReaderWindowController) {
      guard self.controller === controller else { return }
      self.controller = nil
    }
  }
#endif
