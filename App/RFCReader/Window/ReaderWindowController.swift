#if os(macOS)
  import AppKit
  import PDFKit
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

    /// The window's columns; see `ReaderSplitViewController`.
    private(set) var splitController: ReaderSplitViewController!

    /// The library this window was made with, which its toolbar reads too.
    let library: LibraryModel
    /// See `placeInitialFocus()`.
    private var hasPlacedInitialFocus = false
    /// Set on a window AppKit restores (#155), whose panel is put right once, the
    /// first time it is made key. See `windowDidBecomeKey(_:)`.
    var correctsPanelOnFirstKey = false
    /// The Go to RFC palette, while it is showing.
    private var quickOpen: QuickOpenPanel?
    /// Whether a print is being prepared or its panel is up, so a second ⌘P
    /// neither builds the PDF again nor asks for a second sheet.
    private var isPrinting = false
    /// Whether an export's save panel is up or its file is being made, so a second
    /// ⌘⇧E neither asks for a second panel nor makes the file again.
    private var isExporting = false
    /// `NSToolbar.delegate` is weak; an unheld delegate gives an empty toolbar.
    private var toolbar: ReaderToolbar?

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
      makeRestorable(window)
      build(in: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
      fatalError("init(coder:) is not used: windows are made in code")
    }

    private func build(in window: NSWindow) {
      splitController = ReaderSplitViewController(
        sidebar: host(SidebarView()),
        list: host(RFCListView()),
        reader: host(ReaderHost()),
        // The glass is the window's business, not the panel's: without this the list
        // draws its own opaque sidebar background over the inspector and the panel
        // stops being translucent at all. Applied here rather than inside
        // `PanelHost`, which iOS presents in a sheet that wants its own background.
        panel: host(PanelHost().scrollContentBackground(.hidden)))

      window.contentViewController = splitController
      splitController.applyMinimumWidth()

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
      let canDescribe = Observations { [weak self] in self?.reader.canDescribe }
      let showsQuickOpen = Observations { [weak self] in self?.navigation.isShowingGoToSheet }
      let snapshots = Observations { [weak self] in self?.sceneSnapshot }
      let besides = Observations { [weak self] in
        self?.reader.sideBySide.map(ObjectIdentifier.init)
      }
      observations = [
        Task(name: "Observe window title") { [weak self] in
          for await title in titles { if let title { self?.apply(title) } }
        },
        Task(name: "Observe list title") { [weak self] in
          for await title in listTitles { if let title { self?.apply(title) } }
        },
        Task(name: "Observe document") { [weak self] in
          for await _ in canDescribe { self?.closePanelWithoutDocument() }
        },
        Task(name: "Observe Go to RFC") { [weak self] in
          for await _ in showsQuickOpen { self?.showOrHideQuickOpen() }
        },
        // AppKit asks for the window's state again only once told it changed (#155).
        Task(name: "Observe scene snapshot") { [weak self] in
          for await _ in snapshots { self?.window?.invalidateRestorableState() }
        },
        Task(name: "Observe side by side") { [weak self] in
          for await _ in besides { self?.showBeside() }
        },
      ]
    }

    /// What every hosted root of this window is given; see `ReaderEnvironment`.
    private var environment: ReaderEnvironment {
      ReaderEnvironment(
        library: library, navigation: navigation, reader: reader)
    }

    /// Every hosted root is handed `environment`: an `NSHostingController` sits
    /// outside any SwiftUI environment chain.
    ///
    /// The root keeps its own type rather than being erased to `AnyView`: these roots
    /// are re-evaluated by observation — `PanelHost` reads `reader.currentAnchor`, so
    /// it updates on every section crossing while scrolling — and an erased root
    /// gives SwiftUI nothing to diff against.
    private func host(_ view: some View) -> NSHostingController<some View> {
      host(view, in: environment)
    }

    private func host(_ view: some View, in environment: ReaderEnvironment)
      -> NSHostingController<some View>
    {
      let controller = NSHostingController(rootView: view.readerEnvironment(environment))
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
      splitController.listWidth
    }

    // MARK: - Side by side

    /// Adds the reader beside the window's own while a document is compared with
    /// another (#187), and takes it away after.
    ///
    /// A fifth item rather than a second reader inside the reader's hosted root: each
    /// reader keeps a hosted root of its own, given its own navigation and reader
    /// state, so what the one beside reports reaches neither the toolbar nor the
    /// panel, which stay the window's reader's. See
    /// `docs/decisions/2026-10-04-a-document-read-beside-another-is-a-fifth-split-item.md`.
    private func showBeside() {
      if let reading = reader.sideBySide {
        splitController.showBeside(
          host(
            BesideReader(reading: reading, main: reader, mainNavigation: navigation),
            in: ReaderEnvironment(
              library: library, navigation: reading.navigation, reader: reading.reader)))
      } else {
        splitController.closeBeside()
      }
      trackPanelEdge()
    }

    /// Keeps the toolbar's panel section over the contents panel, whose divider moves
    /// along one as the reader beside is inserted in front of it or removed.
    private func trackPanelEdge() {
      let divider = ReaderWindowDividers.panel(comparing: splitController.isComparing)
      for case let separator as NSTrackingSeparatorToolbarItem in window?.toolbar?.items ?? []
      where separator.itemIdentifier == .rfcPanelSeparator {
        separator.dividerIndex = divider
      }
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

    /// Keeps the panel shut while there is nothing for it to describe: an inspector's
    /// glass over a tab with no document in it is a strip of nothing. `observe()`
    /// applies it whenever `canDescribe` changes, and `AppDelegate` from outside for
    /// the one case observation cannot see: nothing about this window changed, its
    /// sibling's panel state was copied onto it. A window AppKit restores is ordered
    /// into its group by AppKit, so `windowDidBecomeKey(_:)` makes it for that one.
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
      if reader.canDescribe {
        // The panel may have been opened or shut by the tab group rather than by a
        // toggle, so the floor follows whatever state it is in now.
        splitController.applyMinimumWidth()
      } else {
        splitController.closePanel()
      }
    }

    // MARK: - The sidebar

    /// Through the split view controller rather than down the responder chain, so
    /// the menu and the toolbar's toggle act on this window's sidebar whatever holds
    /// focus in it.
    func toggleSidebar() {
      splitController.toggleSidebar(nil)
    }

    /// Slides a collapsed sidebar open and runs `then` once it is; see
    /// `ReaderSplitViewController.revealSidebar(then:)`.
    func revealSidebar(then: @escaping @MainActor @Sendable () -> Void) {
      splitController.revealSidebar(then: then)
    }

    /// An empty collection, from the toolbar's New Collection and File > New
    /// Collection… alike; only the Bookmark menu's adds the open document. It opens
    /// a collapsed sidebar first, so the collection is in view once made, and the
    /// sheet comes in once the sidebar has slid open.
    func newCollection() {
      revealSidebar { [navigation] in
        navigation.collectionEditor = .create(adding: nil)
      }
    }

    /// ⌥⌘F. Opens the sidebar first if it is collapsed: the field is in it.
    func focusSearch() {
      splitController.openSidebar()
      guard let field = FirstResponderSearch.searchField(in: splitController.sidebarView)
      else { return }
      window?.makeFirstResponder(field)
    }

    // MARK: - The panel

    func togglePanel() {
      splitController.togglePanel()
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
      splitController.isPanelOpen
    }

    /// Opens or closes the panel, the way the toolbar's toggle does — so only over
    /// something to describe, which is what the toggle's validation allows. False when it
    /// refused to open.
    @discardableResult
    func setPanelOpen(_ open: Bool) -> Bool {
      guard !open || reader.canDescribe else { return false }
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
        let readerView = splitController.readerView
        NSLog(
          "RFCGEOM \(label) number=\(window.windowNumber) title=\(window.title) window=\(window.frame.width) reader=\(readerView.frame.width) "
            + "safeR=\(readerView.safeAreaInsets.right) panelCollapsed=\(!isPanelOpen) "
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
        let text = FirstResponderSearch.searchableText(in: splitController.readerView)
      else { return }
      // The find bar is the scroll view's, not the text view's: ⌘G typed in its field
      // has to leave focus there. The reader beside a compared document finds in its
      // own text (#187).
      if let focused = window.firstResponder as? NSView,
        focused.isDescendant(of: text.enclosingScrollView ?? text)
          || splitController.besideView.map({ focused.isDescendant(of: $0) }) == true
      {
        return
      }
      window.makeFirstResponder(text)
    }

    /// Edit ▸ Copy as Quote, handed to the reader's text itself (#186). Not through the
    /// responder chain, which reaches no text view with the sidebar, the contents
    /// panel or the find bar focused: the find bar is the scroll view's, a parent of
    /// the text view, not a child.
    func copyAsQuote() {
      let text = FirstResponderSearch.searchableText(in: quotedReaderView)
      (text as? ReaderTextView)?.copyAsQuote(nil)
    }

    /// The reader whose selection Copy as Quote copies: the one beside a compared
    /// document (#187) when the selection in its text is the only one, or the focus is
    /// in it; the window's own otherwise.
    private var quotedReaderView: NSView {
      guard let beside = splitController.besideView,
        reader.sideBySide?.reader.hasSelection == true
      else { return splitController.readerView }
      let focused = window?.firstResponder as? NSView
      if !reader.hasSelection || focused?.isDescendant(of: beside) == true { return beside }
      return splitController.readerView
    }

    /// Shared by the toolbar's bookmark button and the ⌘D menu item, so the two
    /// cannot disagree about what bookmarking means.
    func toggleBookmark() {
      guard let id = navigation.selection else { return }
      library.toggleBookmark(id, documentTitle: reader.documentTitle)
    }

    // MARK: - Print

    /// File > Print…: the document laid out for paper, handed to the system's print
    /// panel as a sheet on this window (#375). Laid out for the paper Page Setup has
    /// chosen; a different paper picked in the panel itself is scaled to fit.
    func printDocument() {
      guard !isPrinting, let id = navigation.selection, reader.offersPrintAndExport, let window
      else {
        return
      }
      // The PDF's pages carry their own margins; AppKit's, left in, would shrink
      // every page to fit inside a second set.
      guard let printInfo = NSPrintInfo.shared.copy() as? NSPrintInfo else { return }
      printInfo.leftMargin = 0
      printInfo.rightMargin = 0
      printInfo.topMargin = 0
      printInfo.bottomMargin = 0
      let original = reader.showOriginal
      isPrinting = true
      Task {
        do {
          let data = try await DocumentPDF.make(
            for: id, original: original, paperSize: printInfo.paperSize, library: library)
          guard let pdf = PDFDocument(data: data),
            let operation = pdf.printOperation(
              for: printInfo, scalingMode: .pageScaleToFit, autoRotate: false)
          else {
            isPrinting = false
            return
          }
          // The one field of the Save as PDF sheet a print can fill: its Author,
          // Subject and Keywords have no public setting (#375).
          operation.jobTitle = PrintFurniture.documentTitle(
            id: id, title: reader.documentTitle ?? library.metadata(id)?.title)
          operation.runModal(
            for: window, delegate: self,
            didRun: #selector(printOperationDidRun(_:success:contextInfo:)), contextInfo: nil)
        } catch {
          isPrinting = false
          _ = window.presentError(error)
        }
      }
    }

    @objc private func printOperationDidRun(
      _ operation: NSPrintOperation, success: Bool, contextInfo: UnsafeMutableRawPointer?
    ) {
      isPrinting = false
    }

    /// File > Export…: the document saved in the format the save panel's pop-up
    /// picks (#376), as a sheet on this window. A paged format is laid out for the
    /// paper Page Setup has chosen, as a print is.
    func exportDocument() {
      guard !isExporting, let id = navigation.selection, reader.offersPrintAndExport, let window
      else {
        return
      }
      let panel = NSSavePanel()
      let chooser = ExportFormatChooser(panel: panel, document: id, offered: reader.exportFormats)
      panel.accessoryView = chooser.view
      panel.isExtensionHidden = false
      panel.canCreateDirectories = true
      panel.tagNames = ExportFormat.tagNames(for: library.metadata(id))
      isExporting = true
      panel.beginSheetModal(for: window) { [library] response in
        guard response == .OK, let url = panel.url else {
          self.isExporting = false
          return
        }
        // Read here, not captured earlier: the chooser is what the panel's pop-up
        // changed, and holding it in this closure is what keeps it alive.
        let format = chooser.format
        let tags = panel.tagNames ?? []
        Task {
          do {
            let data = try await DocumentExport.data(
              for: id, as: format, paperSize: NSPrintInfo.shared.paperSize, library: library)
            try data.write(to: url, options: .atomic)
            // The panel only collects the tags; the file is written after it, and
            // an atomic write replaces it, so they are set on what was written.
            if !tags.isEmpty {
              try (url as NSURL).setResourceValue(tags, forKey: .tagNamesKey)
            }
            self.isExporting = false
          } catch {
            self.isExporting = false
            _ = window.presentError(error)
          }
        }
      }
    }

    /// File > Page Setup…, which sets the paper `printDocument()` lays out for.
    func runPageSetup() {
      guard let window else { return }
      NSPageLayout().beginSheet(
        with: NSPrintInfo.shared, modalFor: window, delegate: nil, didEnd: nil, contextInfo: nil)
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
      // A restored window is ordered into its tab group by AppKit, not by
      // `AppDelegate.openWindow(tabbedWith:inBackground:)`, so the correction made
      // there after the ordering call is made here instead. Not when its state is
      // decoded: it is not yet in its group or on screen then, and measured, its
      // panel is shut and nothing describes it yet, so the correction did nothing.
      // On the next turn, since the group's inspector state is copied onto a window
      // inside `makeKeyAndOrderFront(_:)`, which is still running; see
      // `closePanelWithoutDocument()`.
      //
      // That puts the window's floor right too: AppKit gave the window its saved
      // frame after it was made, without checking it against the minimum.
      if correctsPanelOnFirstKey {
        correctsPanelOnFirstKey = false
        Task { [weak self] in self?.closePanelWithoutDocument() }
      }
    }

    /// Hands the list first responder the first time this window comes up, so the
    /// arrow keys walk the library without a click to wake them.
    ///
    /// Once per window rather than once per activation: coming back to the app after
    /// reading should leave focus wherever the reader left it.
    private func placeInitialFocus() {
      guard !hasPlacedInitialFocus, let window = window as? ReaderWindow else { return }
      hasPlacedInitialFocus = window.giveFocus(inside: splitController.listView)
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
      releaseWindowContent()
    }

    /// Empties a closing window, so that if something keeps the window itself, it
    /// keeps a few hundred bytes and not a whole document.
    ///
    /// Something does, sometimes (#432): SwiftUI's focus bookkeeping for the menu
    /// bar's `.commands` can hold a closed window whose first responder was the
    /// sidebar's list, long after this controller is gone. Everything the window
    /// showed — the split view controller, its hosted roots, the reader's text view
    /// and its storage — hangs off `contentViewController`, and the toolbar and the
    /// delegate point back at this controller.
    ///
    /// Not `WindowGroup`'s forbidden content replacement: the window is closing, it
    /// is AppKit's, and nothing takes the content's place.
    private func releaseWindowContent() {
      guard let window else { return }
      window.contentViewController = nil
      window.toolbar = nil
      window.delegate = nil
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
#endif
