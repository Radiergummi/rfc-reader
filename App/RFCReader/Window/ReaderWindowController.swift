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
/// `docs/superpowers/specs/2026-09-22-window-hijack-probe-results.md`. The menu bar
/// is still SwiftUI's: a `Settings`-only scene keeps `.commands` working, so only
/// window creation moved to AppKit.
@MainActor
final class ReaderWindowController: NSWindowController, NSWindowDelegate {
    /// This window's own navigation: which document, which filter, what was searched
    /// for, and the back/forward stack that got here. `ContentView` held it as
    /// `@State`, which is what made a tab a tab; now the window holds it, and every
    /// hosted root is handed the same one.
    let navigation = NavigationModel()

    /// What the reader is showing, for the toolbar and the panel — which are not
    /// inside it any more.
    let reader = ReaderState()

    let splitController = ReaderSplitViewController()
    private(set) var listItem: NSSplitViewItem!
    private(set) var readerItem: NSSplitViewItem!
    private(set) var panelItem: NSSplitViewItem!

    private let library: LibraryModel
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
        let window = NSWindow(
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
        sidebar.minimumThickness = 200
        sidebar.maximumThickness = 320

        let list = NSSplitViewItem(contentListWithViewController: host(RFCListView()))
        list.minimumThickness = 280
        listItem = list

        // The reader ignores the trailing safe area, and this is the one place that
        // works. The panel's width arrives as a right safe-area inset, and honouring
        // it took the reader from 1019 pt to 699 and the column from 712 to 651 the
        // moment the panel opened — measured both ways. Issue #34 recorded that
        // `ignoresSafeArea` does not undo an AppKit inset, and inside
        // `NavigationSplitView`'s detail column it does not; on the hosted root of
        // the split item itself it does. What the panel overlaps, it covers.
        let readerHost = host(ReaderHost())
        // EXPERIMENT: clear the hosted root's safe area entirely.
        readerHost.safeAreaRegions = []
        // The panel's width comes back as a right safe-area inset, and honouring it
        // would take 320 pt off the column the moment the panel opened — measured at
        // 919 → 599 pt, which re-wraps the text, rebuilds the document and loses the
        // reader's place. What the panel overlaps, it covers.
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
        splitController.didResizeSubviews = { [weak self] in self?.toolbar?.capTitleToList() }
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

        // Takes the link a new tab was opened for, if it was opened for one.
        library.register(navigation)
        observeTitle()
        observeDocument()
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
            rootView: view
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

    /// The window's title, and therefore the tab's.
    ///
    /// `navigationTitle` reached the window through the scene, and macOS has no scene
    /// any more, so the window is titled directly. `withObservationTracking` fires
    /// once, which is why it re-arms itself.
    private func observeTitle() {
        withObservationTracking {
            // Still set on the window, because the tab bar reads it from there.
            let title = navigation.selection?.displayName ?? navigation.filter.title
            // The prose title, where macOS has room for it — truncated, because a tab
            // is far narrower than the window and clips rather than eliding.
            let subtitle = navigation.selection
                .flatMap { library.metadata($0)?.title }?
                .truncated(to: Self.subtitleLimit) ?? ""
            window?.title = title
            window?.subtitle = subtitle
            toolbar?.showTitle(title, subtitle: subtitle)
            // Here because this is already the one place that re-fires when the
            // selection changes, and the fetch must not be on the toolbar's
            // validation path; see `isBookmarked`.
            refreshBookmarked()
        } onChange: {
            Task { @MainActor [weak self] in self?.observeTitle() }
        }
    }

    /// Long enough that most RFC titles survive whole, short enough that the series'
    /// genuinely long ones stop before the tab's edge.
    private static let subtitleLimit = 64

    private static let sidebarMinimum: CGFloat = 200
    private static let listMinimum: CGFloat = 280

    /// The narrowest the window may be: the two fixed columns plus a readable
    /// measure. Named rather than restated, so dragging a column's floor cannot leave
    /// the window's behind. Nothing here for the panel — deliberately.
    private static let minimumContentWidth: CGFloat = sidebarMinimum + listMinimum + ReaderLayout.minimumPaneWidth

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
    /// glass over a tab with no document in it is a strip of nothing.
    private func observeDocument() {
        withObservationTracking {
            _ = reader.hasDocument
        } onChange: {
            Task { @MainActor [weak self] in
                self?.closePanelWithoutDocument()
                self?.observeDocument()
            }
        }
    }

    /// The same rule, applied from outside for the one case the observation cannot
    /// see: nothing about this window changed, its sibling's panel state was copied
    /// onto it.
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

    #if DEBUG
    /// Called from the debugger when a geometry claim needs re-checking: the reader's
    /// own frame must not change when the panel opens, and the panel's width must
    /// come back as a safe-area inset rather than as lost width. The readings this
    /// produced are written up in
    /// `docs/superpowers/specs/2026-09-22-window-hijack-probe-results.md`.
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
    /// Stored rather than fetched on demand: `NSToolbar` autovalidates every visible
    /// item once per event cycle, and asking SwiftData there put a compiled
    /// `#Predicate` and a store round trip under every mouse move, once per open tab.
    /// Nothing else on macOS writes a `Bookmark`, so the two places it can change
    /// are the selection moving and `toggleBookmark()`.
    private(set) var isBookmarked = false

    private func refreshBookmarked() {
        isBookmarked = navigation.selection.flatMap { bookmark(for: $0) } != nil
    }

    /// Shared by the toolbar's bookmark button and the ⌘D menu item, so the two
    /// cannot disagree about what bookmarking means.
    func toggleBookmark() {
        guard let id = navigation.selection else { return }
        let context = AppData.container.mainContext
        if let existing = bookmark(for: id) {
            context.delete(existing)
        } else {
            let title = library.metadata(id)?.title ?? id.displayName
            context.insert(Bookmark(number: id.number, title: title))
        }
        try? context.save()
        refreshBookmarked()
    }

    private func bookmark(for id: DocumentID) -> Bookmark? {
        let number = id.number
        let descriptor = FetchDescriptor<Bookmark>(predicate: #Predicate { $0.number == number })
        return try? AppData.container.mainContext.fetch(descriptor).first
    }

    // MARK: - Lifetime

    func windowDidBecomeKey(_ notification: Notification) {
        ActiveReaderWindow.shared.becameKey(self)
    }

    func windowWillClose(_ notification: Notification) {
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
@MainActor
final class ReaderSplitViewController: NSSplitViewController {
    var didResizeSubviews: (() -> Void)?

    override func splitViewDidResizeSubviews(_ notification: Notification) {
        super.splitViewDidResizeSubviews(notification)
        didResizeSubviews?()
    }
}

/// What the detail column of `NavigationSplitView` used to hold.
///
/// The sheet is declared here rather than on the scene, because a presentation has to
/// be declared by a view that is actually in the window.
struct ReaderHost: View {
    @Environment(LibraryModel.self) private var library
    @Environment(NavigationModel.self) private var navigation

    var body: some View {
        @Bindable var navigation = navigation
        Group {
            if let selection = navigation.selection {
                DocumentView(id: selection)
                    .id(selection)
            } else {
                EmptyDetailView()
            }
        }
        // Any navigation in this tab makes it the one an untargeted deep link lands in.
        .onChange(of: navigation.selection) { library.activate(navigation) }
        .sheet(isPresented: $navigation.isShowingGoToSheet) {
            GoToDocumentSheet()
        }
    }
}
#endif
