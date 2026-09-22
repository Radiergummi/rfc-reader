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

    let splitController = NSSplitViewController()
    private(set) var readerItem: NSSplitViewItem!
    private(set) var panelItem: NSSplitViewItem!

    private let library: LibraryModel

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

        let reader = NSSplitViewItem(viewController: host(ReaderHost()))
        // On the *content* item, never on the panel: this is what makes the reader's
        // frame span the panel and hands the panel's width back as a right safe-area
        // inset instead of taking the width away. The reader then ignores that inset
        // in the representable, which is what keeps the text from re-wrapping.
        reader.automaticallyAdjustsSafeAreaInsets = true
        reader.minimumThickness = ReaderLayout.minimumPaneWidth
        readerItem = reader

        let panel = NSSplitViewItem(inspectorWithViewController: host(PanelHost()))
        panel.allowsFullHeightLayout = true
        panel.minimumThickness = Self.panelWidth
        panel.maximumThickness = Self.panelWidth
        panel.isCollapsed = true
        panelItem = panel

        for item in [sidebar, list, reader, panel] {
            splitController.addSplitViewItem(item)
        }

        window.contentViewController = splitController
        Self.controllers[ObjectIdentifier(window)] = WeakController(controller: self)

        // Takes the link a new tab was opened for, if it was opened for one.
        library.register(navigation)
        observeTitle()

        // Read by the measurement harness, and the first thing that would show a
        // window churn: one line per window means one window per window.
        NSLog("RFCWINDOW number=\(window.windowNumber)")
    }

    /// Every hosted root is handed the models by hand.
    ///
    /// An `NSHostingController` sits outside any SwiftUI environment chain, so
    /// `@Environment(LibraryModel.self)` inside one is a runtime trap with no
    /// compile-time warning — the same reason `DocumentHeaderView` and `StatusBanner`
    /// take theirs as properties.
    private func host(_ view: some View) -> NSViewController {
        NSHostingController(
            rootView: view
                .environment(library)
                .environment(navigation)
                .modelContainer(AppData.container)
        )
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

/// The contents panel. Filled in once the reader has a document to describe.
struct PanelHost: View {
    var body: some View {
        Color.clear
    }
}
#endif
