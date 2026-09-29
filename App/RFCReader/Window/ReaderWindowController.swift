#if os(macOS)
  import AppKit
  import RFCKit
  import RFCReaderKit
  import SwiftData
  import SwiftUI

  /// One window — which is one tab — and everything in it.
  ///
  /// The window is ours from the moment it is made, and that is the point. Window
  /// chrome (the inspector's glass, the titlebar section an item owns, and the tab bar
  /// that follows it) only engages for a split view controller that *is* the window's
  /// root, so the contents panel can only confine the tab bar if AppKit sees it as a
  /// real `NSSplitViewItem` in the window's own controller.
  ///
  /// `WindowGroup` cannot be talked into this. Adding an item to SwiftUI's split view
  /// controller is reconciled away (issue #34), and replacing a `WindowGroup` window's
  /// `contentViewController` makes SwiftUI destroy the window and open a replacement —
  /// measured at 24 windows in 0.9 s, in
  /// `docs/decisions/2026-09-22-window-hijack-probe-results.md`. The menu bar
  /// is still SwiftUI's: a `Settings`-only scene keeps `.commands` working, so only
  /// window creation moved to AppKit.
  final class ReaderWindowController: NSWindowController, NSWindowDelegate {
    /// This window's own navigation: which document, which filter, what was searched
    /// for, and the back/forward stack that got here. `ContentView` held it as
    /// `@State`, which is what made a tab a tab; now the window holds it, and every
    /// hosted root is handed the same one.
    let navigation: NavigationModel

    /// What the reader is showing, for the toolbar and the panel — which are not
    /// inside it any more.
    let reader = ReaderState()

    let splitController = ReaderSplitViewController()
    private(set) var sidebarItem: NSSplitViewItem!
    private(set) var listItem: NSSplitViewItem!
    private(set) var readerItem: NSSplitViewItem!
    private(set) var panelItem: NSSplitViewItem!

    /// The library this window was made with, which its toolbar reads too.
    let library: LibraryModel
    /// See `placeInitialFocus()`.
    private var hasPlacedInitialFocus = false
    /// The Go to RFC palette, while it is showing.
    private var quickOpen: QuickOpenPanel?
    /// `NSToolbar.delegate` is weak; an unheld delegate gives an empty toolbar.
    private var toolbar: ReaderToolbar?

    /// How wide the contents panel is drawn. Unchanged from the overlay it replaces.
    static let panelWidth: CGFloat = 320

    /// `NSWindowController.init(window:)` makes itself the window's controller, so
    /// AppKit already keeps this mapping; a registry of our own would only be a
    /// second copy to prune, keyed by an address a later window can be handed again.
    static func controller(for window: NSWindow?) -> ReaderWindowController? {
      window?.windowController as? ReaderWindowController
    }

    init(library: LibraryModel) {
      self.library = library
      self.navigation = NavigationModel(library: library)
      let window = ReaderWindow(
        contentRect: NSRect(x: 0, y: 0, width: 1400, height: 900),
        styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
        backing: .buffered,
        defer: false
      )
      // Everything in this app is the same kind of window, so a new one joins the
      // front window's tab group rather than opening beside it.
      window.tabbingIdentifier = "org.rfc-editor.reader"
      window.tabbingMode = .preferred
      // No frame autosave name here. It is one name per window, and giving every
      // window the same one made opening a tab collapse the window from 950 pt tall
      // to 307 and leave the new tab's split view laid out for the old width. The
      // first window of the session takes the name, in `AppDelegate`; a tab inherits
      // its sibling's frame from `addTabbedWindow(_:ordered:)`.
      super.init(window: window)
      window.delegate = self
      build(in: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
      fatalError("init(coder:) is not used: windows are made in code")
    }

    private func build(in window: NSWindow) {
      let sidebar = NSSplitViewItem(sidebarWithViewController: host(SidebarView()))
      sidebar.minimumThickness = Self.sidebarMinimum
      sidebar.maximumThickness = 320
      sidebarItem = sidebar

      let list = NSSplitViewItem(contentListWithViewController: host(RFCListView()))
      list.minimumThickness = Self.listMinimum
      listItem = list

      // The panel's width arrives as a right safe-area inset, and honoring it
      // would take 320 pt off the reader the moment the panel opened — which
      // re-wraps the text, rebuilds the document and loses the reader's place.
      // What the panel overlaps, it covers.
      //
      // Two layers have to refuse it, because they are two different measurements
      // of two different things. This one is SwiftUI's: the width `DocumentView`
      // derives its column from comes from a `GeometryReader` in this hosted root,
      // and a root that honors the inset reports 919 pt shut and 599 pt open.
      // Clearing `safeAreaRegions` holds it at 919 both ways — measured, with the
      // view's own frame unchanged at 919 and the inset still arriving as 320.
      // `ignoresSafeArea` inside `NavigationSplitView`'s detail column did not do
      // this; on the hosted root of a split item it does (issue #34).
      //
      // It reaches no further down than SwiftUI, though. Underneath, AppKit hands
      // the same inset to the scroll view, which turns it into content insets the
      // text view tracks — 1019 → 699 pt there, separately measured. That one is
      // `ReaderScrollView`'s to refuse.
      let readerHost = host(ReaderHost())
      readerHost.safeAreaRegions = []
      let reader = NSSplitViewItem(viewController: readerHost)
      // On the *content* item, never on the panel: this is what makes the reader's
      // frame span the panel and hands the panel's width back as a right safe-area
      // inset instead of taking the width away. The reader then ignores that inset
      // in the representable, which is what keeps the text from re-wrapping.
      reader.automaticallyAdjustsSafeAreaInsets = true
      // Deliberately no `minimumThickness`. AppKit adds up the minimum thickness of
      // every uncollapsed item to get the window's own minimum width, and the
      // inspector counts even though it overlays rather than displaces — so a
      // 420 pt floor here plus the panel's 320 grew the window from 901 to 1222 pt
      // the moment the panel opened. Measured. The floor is the window's instead,
      // below, where the panel is not part of the sum.
      readerItem = reader

      // The glass is the window's business, not the panel's: without this the list
      // draws its own opaque sidebar background over the inspector and the panel
      // stops being translucent at all. Applied here rather than inside
      // `PanelHost`, which iOS presents in a sheet that wants its own background.
      let panel = NSSplitViewItem(
        inspectorWithViewController: host(PanelHost().scrollContentBackground(.hidden))
      )
      panel.allowsFullHeightLayout = true
      // The window must not grow when the panel opens. By default an inspector
      // widens the window by its own thickness to keep its siblings' widths —
      // measured at 900 → 1222 pt, which re-wraps the text and loses the reader's
      // place. This keeps the window fixed and lets the siblings take the change;
      // the reader's own frame spans the panel regardless, so what it loses is
      // covered, not removed.
      panel.collapseBehavior = .preferResizingSiblingsWithFixedSplitView
      panel.minimumThickness = Self.panelWidth
      panel.maximumThickness = Self.panelWidth
      panel.isCollapsed = true
      panelItem = panel

      for item in [sidebar, list, reader, panel] {
        splitController.addSplitViewItem(item)
      }

      window.contentViewController = splitController
      applyMinimumWidth(to: window)

      let toolbar = ReaderToolbar(controller: self)
      // The title is capped to the column it sits over, so it has to be told when
      // that column is dragged.
      // Collapsing or expanding the sidebar resizes the subviews too, so this is also
      // where View ▸ Show Sidebar learns which title to show.
      splitController.didResizeSubviews = { [weak self] in
        guard let self else { return }
        self.toolbar?.capTitleToList()
        ActiveReaderWindow.shared.sidebarChanged(self)
      }
      window.toolbar = toolbar.makeToolbar()
      window.toolbarStyle = .unified
      // The title is the toolbar's own item, not AppKit's.
      //
      // A window that draws its own title puts it in a block at the start of the
      // document's toolbar section, and that block expands to fill — measured, it
      // pushed Back and Forward from 204 pt out to 1199 on a 1500 pt window, with
      // and without a subtitle. The expanded style gives the title a row of its
      // own and costs a second row of titlebar; a leading titlebar accessory is
      // laid out over the sidebar and pushes the sidebar's toggle into the
      // overflow menu. An ordinary toolbar item is none of those things: it sits
      // where it is declared and takes the width it needs.
      window.titleVisibility = .hidden

      self.toolbar = toolbar
      self.reader.updateToolbarTitle = { [weak toolbar] in toolbar?.updateDocumentTitle($0) }
      self.reader.openPanel = { [weak self] in self?.setPanelOpen(true) }

      // Takes the link a new tab was opened for, if it was opened for one.
      library.register(navigation)
      // Once now, so the window is never shown untitled, and then on every change.
      apply(windowTitle)
      apply(listTitle)
      observe()
    }

    // MARK: - Observation

    /// What this window follows in its models: its title, the list's, the panel's
    /// rule and the palette. A task per sequence, all canceled as the window
    /// closes; each holds the controller weakly.
    private var observations: [Task<Void, Never>] = []

    /// Each sequence yields its value now and again after every change to what it
    /// read, a turn later — which `updateToolbarTitle` cannot wait for, so the title
    /// coupled to the scroll is a callback instead (see `ReaderState`).
    private func observe() {
      let titles = Observations { [weak self] in self?.windowTitle }
      let listTitles = Observations { [weak self] in self?.listTitle }
      let hasDocument = Observations { [weak self] in self?.reader.hasDocument }
      let showsQuickOpen = Observations { [weak self] in self?.navigation.isShowingGoToSheet }
      observations = [
        Task(name: "Observe window title") { [weak self] in
          for await title in titles { if let title { self?.apply(title) } }
        },
        Task(name: "Observe list title") { [weak self] in
          for await title in listTitles { if let title { self?.apply(title) } }
        },
        Task(name: "Observe document") { [weak self] in
          for await _ in hasDocument { self?.closePanelWithoutDocument() }
        },
        Task(name: "Observe Go to RFC") { [weak self] in
          for await _ in showsQuickOpen { self?.showOrHideQuickOpen() }
        },
      ]
    }

    /// Every hosted root is handed the models by hand.
    ///
    /// An `NSHostingController` sits outside any SwiftUI environment chain, so
    /// `@Environment(LibraryModel.self)` inside one is a runtime trap with no
    /// compile-time warning — the same reason `DocumentHeaderView` and `StatusBanner`
    /// take theirs as properties.
    ///
    /// The root keeps its own type rather than being erased to `AnyView`: these roots
    /// are re-evaluated by observation — `PanelHost` reads `reader.currentAnchor`, so
    /// it updates on every section crossing while scrolling — and an erased root
    /// gives SwiftUI nothing to diff against.
    private func host(_ view: some View) -> NSHostingController<some View> {
      let controller = NSHostingController(
        rootView:
          view
          .environment(library)
          .environment(navigation)
          .environment(reader)
          .modelContainer(AppData.container)
      )
      // The hosted view must not size the window. By default a hosting controller
      // reports its content's preferred size, and as a split view item that reaches
      // the window: measured, it pinned the window at 219 pt tall and left the
      // split laid out for a width it no longer had. The window's size is the
      // window's business; these views fill whatever they are given.
      controller.sizingOptions = []
      return controller
    }

    /// How wide the list column is right now. The title drawn over it is capped to
    /// this, and the column is draggable, so it is read rather than remembered.
    var listWidth: CGFloat {
      listItem.viewController.view.frame.width
    }

    // MARK: - Title

    /// The window's title, and therefore the tab's; the reader's own copy of it in
    /// the toolbar; and the bookmark glyph, which follows the selection and the
    /// bookmarks.
    ///
    /// `navigationTitle` reached the window through the scene, and macOS has no scene
    /// any more, so the window is titled directly.
    private struct WindowTitle: Sendable {
      var title: String
      var subtitle: String
      var documentTitle: String
      var documentSubtitle: String
      var isBookmarked: Bool
    }

    private var windowTitle: WindowTitle {
      WindowTitle(
        // Still set on the window, because the tab bar reads it from there.
        title: navigation.selection?.displayName ?? library.title(for: navigation.filter),
        // The prose title, where macOS has room for it — truncated, because a tab
        // is far narrower than the window and clips rather than eliding.
        subtitle: navigation.selection
          .flatMap {
            DocumentActions.subtitle(
              metadata: library.metadata($0), documentTitle: reader.documentTitle)
          }?
          .truncated(to: Self.subtitleLimit) ?? "",
        // The reader's own copy, shown once its header scrolls away. Whole, not
        // truncated like the tab's: the item ellipsizes to whatever room it has.
        documentTitle: navigation.selection?.displayName ?? "",
        documentSubtitle: navigation.selection.flatMap { library.metadata($0)?.title } ?? "",
        isBookmarked: isBookmarked
      )
    }

    private func apply(_ title: WindowTitle) {
      window?.title = title.title
      window?.subtitle = title.subtitle
      toolbar?.showDocumentTitle(title.documentTitle, subtitle: title.documentSubtitle)
      toolbar?.showBookmarked(title.isBookmarked)
      window?.toolbar?.validateVisibleItems()
    }

    /// The title over the list names the list: the collection the sidebar chose and
    /// how many documents it holds after the search. The document is the tab's to
    /// name, and the reader's own.
    ///
    /// Its own sequence, apart from the window's title: the count changes with most
    /// keystrokes in the search field, and nothing else there — the window's
    /// title, the reader's, the bookmark glyph — depends on it.
    private struct ListTitle: Sendable {
      var title: String
      var subtitle: String
    }

    private var listTitle: ListTitle {
      ListTitle(
        title: library.title(for: navigation.filter),
        subtitle: library.listSubtitle(for: navigation))
    }

    private func apply(_ title: ListTitle) {
      toolbar?.showTitle(title.title, subtitle: title.subtitle)
    }

    /// Long enough that most RFC titles survive whole, short enough that the series'
    /// genuinely long ones stop before the tab's edge.
    private static let subtitleLimit = 64

    private static let sidebarMinimum: CGFloat = 200
    private static let listMinimum: CGFloat = 280

    /// The narrowest the window may be: the two fixed columns plus a readable
    /// measure. Named rather than restated, so dragging a column's floor cannot leave
    /// the window's behind. Nothing here for the panel — deliberately.
    private static let minimumContentWidth: CGFloat =
      sidebarMinimum + listMinimum + ReaderLayout.minimumPaneWidth

    /// Holds the window's minimum *constant* as the panel opens and closes.
    ///
    /// AppKit adds an uncollapsed inspector's thickness on top of `contentMinSize`,
    /// so a fixed 900 pt minimum became 1222 the moment the panel appeared and the
    /// window grew to meet it — which widens the pane, changes the column, rebuilds
    /// the document and loses the reader's place, the whole chain the overlay existed
    /// to avoid. Taking the panel's width off the minimum while it is showing leaves
    /// the effective floor where it was, and the window never moves.
    private func applyMinimumWidth(to window: NSWindow) {
      let panelAllowance = panelItem.isCollapsed ? 0 : Self.panelWidth
      window.contentMinSize = NSSize(width: Self.minimumContentWidth - panelAllowance, height: 480)
      // A restored frame is not re-checked against the minimum, so a window saved
      // narrower than the floor comes back narrower than the floor.
      var frame = window.frame
      frame.size.width = max(frame.width, window.contentMinSize.width)
      frame.size.height = max(frame.height, window.contentMinSize.height)
      if frame != window.frame { window.setFrame(frame, display: false) }
    }

    /// Keeps the panel shut while there is nothing for it to describe: an inspector's
    /// glass over a tab with no document in it is a strip of nothing. `observe()`
    /// applies it whenever `hasDocument` changes, and `AppDelegate` from outside for
    /// the one case observation cannot see: nothing about this window changed, its
    /// sibling's panel state was copied onto it.
    ///
    /// A window ordered into a tab group adopts the group's inspector state. Measured
    /// on this build: `isCollapsed` is still the one this controller set immediately
    /// after `addTabbedWindow(_:ordered:)`, and the sibling's immediately after the
    /// window is ordered front — so the adoption happens inside
    /// `makeKeyAndOrderFront(_:)`, and a tab opened in the background, which is never
    /// made key, never inherits at all. A correction made once the ordering call has
    /// returned holds: measured unchanged on the next turn of the run loop and a
    /// second later. `AppDelegate` makes it there, which is why nothing here has to
    /// watch for it afterwards.
    func closePanelWithoutDocument() {
      guard !reader.hasDocument, !panelItem.isCollapsed else { return }
      panelItem.isCollapsed = true
    }

    // MARK: - The sidebar

    /// Through the split view controller rather than down the responder chain, so
    /// the menu toggles this window's sidebar whatever holds focus in it.
    func toggleSidebar() {
      splitController.toggleSidebar(nil)
    }

    /// ⌥⌘F. Opens the sidebar first if it is collapsed: the field is in it.
    func focusSearch() {
      if sidebarItem.isCollapsed { sidebarItem.isCollapsed = false }
      guard let field = FirstResponderSearch.searchField(in: sidebarItem.viewController.view)
      else { return }
      window?.makeFirstResponder(field)
    }

    // MARK: - The panel

    /// Animated, so the panel slides in rather than appearing between frames — which
    /// is what `.inspector` did for the overlay, and an ordinary `isCollapsed`
    /// assignment does not.
    func togglePanel() {
      NSAnimationContext.runAnimationGroup { context in
        context.allowsImplicitAnimation = true
        panelItem.animator().isCollapsed.toggle()
      }
      // Before AppKit gets a chance to enforce the old minimum against the new
      // arrangement.
      if let window { applyMinimumWidth(to: window) }
    }

    /// A pane's toolbar button: opens the panel on that pane, swaps an open panel to
    /// it, or closes the panel showing it (`InspectorPane.pressing`).
    func press(_ pane: InspectorPane) {
      let result = InspectorPane.pressing(pane, isOpen: isPanelOpen, showing: reader.pane)
      reader.pane = result.pane
      if result.isOpen != isPanelOpen { togglePanel() }
    }

    /// Whether the contents panel is showing.
    var isPanelOpen: Bool {
      !panelItem.isCollapsed
    }

    /// Opens or closes the panel, the way the toolbar's toggle does — so only over
    /// a document, which is what the toggle's validation allows. False when it
    /// refused to open.
    @discardableResult
    func setPanelOpen(_ open: Bool) -> Bool {
      guard !open || reader.hasDocument else { return false }
      if open != isPanelOpen { togglePanel() }
      return true
    }

    #if DEBUG
      /// Called from the debugger when a geometry claim needs re-checking: the reader's
      /// own frame must not change when the panel opens, and the panel's width must
      /// come back as a safe-area inset rather than as lost width. The readings this
      /// produced are written up in
      /// `docs/decisions/2026-09-22-window-hijack-probe-results.md`.
      func logGeometry(_ label: String) {
        guard let window else { return }
        let readerView = readerItem.viewController.view
        NSLog(
          "RFCGEOM \(label) number=\(window.windowNumber) title=\(window.title) window=\(window.frame.width) reader=\(readerView.frame.width) "
            + "safeR=\(readerView.safeAreaInsets.right) panelCollapsed=\(panelItem.isCollapsed) "
            + "toolbarItems=\(window.toolbar?.items.count ?? -1)"
        )
      }
    #endif

    // MARK: - The document's actions

    /// Whether the document on screen is bookmarked, for the toolbar's glyph.
    ///
    /// From the library's one set of bookmarked numbers, which every tab reads, so
    /// a bookmark toggled in another tab shows here too (#141). Read by the title's
    /// observation, which re-runs when the selection or the set changes.
    var isBookmarked: Bool {
      navigation.selection.map { library.bookmarkedDocuments.contains($0) } ?? false
    }

    /// Puts focus in the text on screen, for Find. Nothing else focuses it: after a
    /// document opens focus is still in the library list, and after Original Text
    /// swaps the body out it falls back to the window, so ⌘F reached no find bar.
    /// Focus moves only when Find is asked for, never when the text appears.
    func focusSearchableText() {
      guard let window,
        let text = FirstResponderSearch.searchableText(in: readerItem.viewController.view)
      else { return }
      // The find bar is the scroll view's, not the text view's: ⌘G typed in its field
      // has to leave focus there.
      if let focused = window.firstResponder as? NSView,
        focused.isDescendant(of: text.enclosingScrollView ?? text)
      {
        return
      }
      window.makeFirstResponder(text)
    }

    /// Shared by the toolbar's bookmark button and the ⌘D menu item, so the two
    /// cannot disagree about what bookmarking means.
    func toggleBookmark() {
      guard let id = navigation.selection else { return }
      library.toggleBookmark(id, documentTitle: reader.documentTitle)
    }

    // MARK: - Go to RFC

    /// ⌘L, the menu and the empty reader's button all ask for the palette the same
    /// way, by setting `isShowingGoToSheet`; this is what answers on the Mac.
    private func showOrHideQuickOpen() {
      if navigation.isShowingGoToSheet {
        guard quickOpen == nil, let window else { return }
        // ⌘L reaches the last reader window that was key, which may since have been
        // minimized: the palette hangs from it, so it comes back first. The palette
        // waits for it, since the window takes key back as it lands, and a panel that
        // loses key closes.
        if window.isMiniaturized {
          window.deminiaturize(nil)
          return
        }
        let hide: () -> Void = { [weak self] in self?.navigation.isShowingGoToSheet = false }
        let panel = QuickOpenPanel(
          content: QuickOpenPalette(library: library, navigation: navigation, dismiss: hide),
          onClose: hide
        )
        quickOpen = panel
        // A window left on another Space comes forward too, rather than the palette
        // floating alone where the window used to be.
        window.makeKeyAndOrderFront(nil)
        panel.show(over: window)
      } else {
        quickOpen?.dismiss()
        quickOpen = nil
      }
    }

    // MARK: - Lifetime

    func windowDidBecomeKey(_ notification: Notification) {
      ActiveReaderWindow.shared.becameKey(self)
      placeInitialFocus()
    }

    /// Hands the list first responder the first time this window comes up, so the
    /// arrow keys walk the library without a click to wake them.
    ///
    /// Once per window rather than once per activation: coming back to the app after
    /// reading should leave focus wherever the reader left it.
    private func placeInitialFocus() {
      guard !hasPlacedInitialFocus, let window = window as? ReaderWindow else { return }
      hasPlacedInitialFocus = window.giveFocus(inside: listItem.viewController.view)
    }

    /// Where a palette asked for while the window was minimized is shown.
    func windowDidDeminiaturize(_ notification: Notification) {
      showOrHideQuickOpen()
    }

    func windowWillClose(_ notification: Notification) {
      for observation in observations {
        observation.cancel()
      }
      observations = []
      ActiveReaderWindow.shared.willClose(self)
      library.unregister(navigation)
      AppDelegate.shared?.forget(self)
    }

    // MARK: - Tabs

    /// The tab bar's own `+`, and ⌘T.
    ///
    /// Nothing else answers this now: it was SwiftUI's `WindowGroup` that implemented
    /// it, and there is no `WindowGroup` on macOS any more.
    @objc override func newWindowForTab(_ sender: Any?) {
      AppDelegate.shared?.openWindow(tabbedWith: self, inBackground: false)
    }
  }

  /// Reports a column being dragged, so the toolbar can cap the title to the list it
  /// sits over.
  final class ReaderSplitViewController: NSSplitViewController {
    var didResizeSubviews: (() -> Void)?

    override func splitViewDidResizeSubviews(_ notification: Notification) {
      super.splitViewDidResizeSubviews(notification)
      didResizeSubviews?()
    }
  }

  /// What the detail column of `NavigationSplitView` used to hold, and the scene's
  /// SwiftUI part (`ReaderScene`): a presentation has to be declared by a view that
  /// is actually in the window, and there is no scene to declare it on.
  struct ReaderHost: View {
    @Environment(LibraryModel.self) private var library
    @Environment(NavigationModel.self) private var navigation
    @Environment(ReaderState.self) private var reader

    var body: some View {
      Group {
        if let selection = navigation.selection {
          DocumentView(id: selection)
            .id(selection)
            // Faded only when the change is animated: following a document preview
            // (`RFCTextViewCoordinator.documentCrossFade`). Every other open cuts.
            .transition(.opacity)
        } else {
          EmptyDetailView()
        }
      }
      .readerScene(library: library, navigation: navigation, reader: reader)
    }
  }
#endif
