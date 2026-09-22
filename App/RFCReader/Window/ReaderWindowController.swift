#if os(macOS)
import AppKit
import RFCReaderKit
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

    let splitController = NSSplitViewController()
    private(set) var readerItem: NSSplitViewItem!
    private(set) var panelItem: NSSplitViewItem!

    private let library: LibraryModel
    /// `NSToolbar.delegate` is weak; an unheld delegate gives an empty toolbar.
    private var toolbar: ReaderToolbar?

    /// How wide the contents panel is drawn. Unchanged from the overlay it replaces.
    static let panelWidth: CGFloat = 320

    /// Weak, keyed by window: a closed tab must not be kept alive by this registry.
    private static var controllers: [ObjectIdentifier: WeakController] = [:]

    private struct WeakController {
        weak var controller: ReaderWindowController?
    }

    static func controller(for window: NSWindow) -> ReaderWindowController? {
        controllers[ObjectIdentifier(window)]?.controller
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
        window.setFrameAutosaveName("ReaderWindow")
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

        let readerHost = host(ReaderHost().ignoresSafeArea(.container, edges: .trailing))
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

        let panel = NSSplitViewItem(inspectorWithViewController: host(PanelHost()))
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
        Self.controllers[ObjectIdentifier(window)] = WeakController(controller: self)

        let toolbar = ReaderToolbar(controller: self)
        window.toolbar = toolbar.makeToolbar()
        window.toolbarStyle = .unified
        self.toolbar = toolbar

        // Takes the link a new tab was opened for, if it was opened for one.
        library.register(navigation)
        observeTitle()

        // Read by the measurement harness, and the first thing that would show a
        // window churn: one line per window means one window per window.
        NSLog("RFCWINDOW number=\(window.windowNumber)")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.logGeometry("at launch") }
    }

    /// Every hosted root is handed the models by hand.
    ///
    /// An `NSHostingController` sits outside any SwiftUI environment chain, so
    /// `@Environment(LibraryModel.self)` inside one is a runtime trap with no
    /// compile-time warning — the same reason `DocumentHeaderView` and `StatusBanner`
    /// take theirs as properties.
    private func host(_ view: some View) -> NSHostingController<AnyView> {
        NSHostingController(rootView: AnyView(withWindowEnvironment(view)))
    }

    /// The models this window's views share, handed to anything hosted in it —
    /// including the toolbar's items, which are hosted too.
    func withWindowEnvironment(_ view: some View) -> some View {
        view
            .environment(library)
            .environment(navigation)
            .environment(reader)
            .modelContainer(AppData.container)
    }

    // MARK: - Title

    /// The window's title, and therefore the tab's.
    ///
    /// `navigationTitle` reached the window through the scene, and macOS has no scene
    /// any more, so the window is titled directly. `withObservationTracking` fires
    /// once, which is why it re-arms itself.
    private func observeTitle() {
        withObservationTracking {
            window?.title = navigation.selection?.displayName ?? navigation.filter.title
            // The prose title, where macOS has room for it — truncated, because a tab
            // is far narrower than the window and clips rather than eliding.
            window?.subtitle = navigation.selection
                .flatMap { library.metadata($0)?.title }?
                .truncated(to: Self.subtitleLimit) ?? ""
        } onChange: {
            Task { @MainActor [weak self] in self?.observeTitle() }
        }
    }

    /// Long enough that most RFC titles survive whole, short enough that the series'
    /// genuinely long ones stop before the tab's edge.
    private static let subtitleLimit = 64

    /// The narrowest the window may be: the two fixed columns plus a readable
    /// measure. Nothing here for the panel — deliberately.
    private static let minimumContentWidth: CGFloat = 200 + 280 + ReaderLayout.minimumPaneWidth

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
        // The evidence for "the reader keeps its width underneath": the reader's own
        // frame must not change when the panel opens, and the panel's width must come
        // back as a safe-area inset rather than as lost width.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.logGeometry("panel \(self?.panelItem.isCollapsed == true ? "closed" : "open")")
        }
    }

    func logGeometry(_ label: String) {
        guard let window else { return }
        let readerView = readerItem.viewController.view
        NSLog(
            "RFCGEOM \(label) window=\(window.frame.width) reader=\(readerView.frame.width) "
                + "safeR=\(readerView.safeAreaInsets.right) panelCollapsed=\(panelItem.isCollapsed) "
                + "toolbarItems=\(window.toolbar?.items.count ?? -1)"
        )
    }

    // MARK: - Lifetime

    func windowWillClose(_ notification: Notification) {
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

/// The contents panel: a split item of its own, so the window's chrome knows it is
/// there. What it draws is the same `DocumentInspector` the overlay drew.
struct PanelHost: View {
    @Environment(LibraryModel.self) private var library
    @Environment(NavigationModel.self) private var navigation
    @Environment(ReaderState.self) private var reader

    var body: some View {
        @Bindable var reader = reader
        if reader.hasDocument {
            DocumentInspector(
                sections: reader.sections,
                groups: reader.groups,
                tab: $reader.tab,
                current: reader.currentAnchor,
                selectSection: { navigation.jump(toSection: $0) },
                openDocument: { library.open($0, activation: .current, in: navigation) }
            )
            // Without this the list draws its own opaque sidebar background over the
            // inspector's glass, and the panel stops being translucent at all.
            .scrollContentBackground(.hidden)
        } else {
            Color.clear
        }
    }
}
#endif
