#if os(macOS)
  import AppKit
  import RFCReaderKit
  import SwiftUI

  /// The window's four columns, sidebar, list, reader and contents panel, and the
  /// rules that keep the reader's text where it is as they open and close.
  ///
  /// `ReaderWindowController` hands it the four hosted roots and asks it to open and
  /// close things; how the items are set up, when the panel is collapsed and how wide
  /// the window may be are this controller's alone. The reasons are in
  /// `docs/decisions/2026-09-22-the-window-layer-is-appkits-on-macos.md`.
  final class ReaderSplitViewController: NSSplitViewController {
    /// Told when a column is dragged, or the sidebar collapses or expands, so the
    /// toolbar can cap the title to the list it sits over.
    var didResizeSubviews: (() -> Void)?

    private let sidebarItem: NSSplitViewItem
    private let listItem: NSSplitViewItem
    private let readerItem: NSSplitViewItem
    private let panelItem: NSSplitViewItem

    init(
      sidebar: NSViewController, list: NSViewController, reader: NSHostingController<some View>,
      panel: NSViewController
    ) {
      sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebar)
      sidebarItem.minimumThickness = ReaderLayout.sidebarMinimum
      sidebarItem.maximumThickness = 320

      listItem = NSSplitViewItem(contentListWithViewController: list)
      listItem.minimumThickness = ReaderLayout.listMinimum

      // The panel's width arrives as a right safe-area inset, and honoring it
      // would take 320 pt off the reader the moment the panel opened — which
      // re-wraps the text, rebuilds the document and loses the reader's place.
      // What the panel overlaps, it covers.
      //
      // Two layers have to refuse it, because they are two different measurements
      // of two different things. This one is SwiftUI's: the width `DocumentView`
      // derives its column from comes from a `GeometryReader` in the reader's hosted
      // root, and a root that honors the inset reports 919 pt shut and 599 pt open.
      // Clearing `safeAreaRegions` on it holds it at 919 both ways — measured, with
      // the view's own frame unchanged at 919 and the inset still arriving as 320.
      // `ignoresSafeArea` inside `NavigationSplitView`'s detail column did not do
      // this; on the hosted root of a split item it does (issue #34).
      //
      // It reaches no further down than SwiftUI, though. Underneath, AppKit hands
      // the same inset to the scroll view, which turns it into content insets the
      // text view tracks — 1019 → 699 pt there, separately measured. That one is
      // `ReaderScrollView`'s to refuse.
      reader.safeAreaRegions = []
      readerItem = NSSplitViewItem(viewController: reader)
      // On the *content* item, never on the panel: this is what makes the reader's
      // frame span the panel and hands the panel's width back as a right safe-area
      // inset instead of taking the width away. The reader then ignores that inset
      // in the representable, which is what keeps the text from re-wrapping.
      readerItem.automaticallyAdjustsSafeAreaInsets = true
      // Deliberately no `minimumThickness`. AppKit adds up the minimum thickness of
      // every uncollapsed item to get the window's own minimum width, and the
      // inspector counts even though it overlays rather than displaces — so a
      // 420 pt floor here plus the panel's 320 grew the window from 901 to 1222 pt
      // the moment the panel opened. Measured. The floor is the window's instead
      // (`applyMinimumWidth()`), where the panel is not part of the sum.

      panelItem = NSSplitViewItem(inspectorWithViewController: panel)
      panelItem.allowsFullHeightLayout = true
      // The window must not grow when the panel opens. By default an inspector
      // widens the window by its own thickness to keep its siblings' widths —
      // measured at 900 → 1222 pt, which re-wraps the text and loses the reader's
      // place. This keeps the window fixed and lets the siblings take the change;
      // the reader's own frame spans the panel regardless, so what it loses is
      // covered, not removed.
      panelItem.collapseBehavior = .preferResizingSiblingsWithFixedSplitView
      panelItem.minimumThickness = ReaderLayout.panelWidth
      panelItem.maximumThickness = ReaderLayout.panelWidth
      panelItem.isCollapsed = true

      super.init(nibName: nil, bundle: nil)
      for item in [sidebarItem, listItem, readerItem, panelItem] {
        addSplitViewItem(item)
      }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
      fatalError("init(coder:) is not used: the split view is made in code")
    }

    override func splitViewDidResizeSubviews(_ notification: Notification) {
      super.splitViewDidResizeSubviews(notification)
      didResizeSubviews?()
    }

    // MARK: - The columns' views

    var sidebarView: NSView { sidebarItem.viewController.view }
    var listView: NSView { listItem.viewController.view }
    var readerView: NSView { readerItem.viewController.view }

    /// How wide the list column is right now. The title drawn over it is capped to
    /// this, and the column is draggable, so it is read rather than remembered.
    var listWidth: CGFloat { listView.frame.width }

    // MARK: - The sidebar

    var isSidebarCollapsed: Bool { sidebarItem.isCollapsed }

    /// Opens a collapsed sidebar at once, unanimated.
    func openSidebar() {
      if sidebarItem.isCollapsed { sidebarItem.isCollapsed = false }
    }

    /// Slides a collapsed sidebar open and runs `then` once it is: straight away when
    /// it already was, after the slide when it was not. A sheet has to wait for it,
    /// because the two cannot move together. AppKit opens a sheet in a run loop of
    /// its own (`NSSheetMoveHelper openSheet` → `NSMoveHelper _doAnimation`, sampled),
    /// in a private mode that the split view's animation is not scheduled in, so a
    /// slide begun beside a sheet held still for the sheet's 300 ms and only then set
    /// out (measured: the list's leading edge at 0 pt until 0.317 s, at 200 pt by
    /// 0.548 s).
    func revealSidebar(then: @escaping @MainActor @Sendable () -> Void) {
      guard sidebarItem.isCollapsed else {
        then()
        return
      }
      NSAnimationContext.runAnimationGroup { _ in
        sidebarItem.animator().isCollapsed = false
      } completionHandler: {
        // AppKit calls it on the main thread; the SDK only does not say so.
        MainActor.assumeIsolated { then() }
      }
    }

    // MARK: - The panel

    var isPanelOpen: Bool { !panelItem.isCollapsed }

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
      applyMinimumWidth()
    }

    /// Shuts the panel at once, unanimated, and puts the window's floor back where it
    /// is with the panel shut.
    func closePanel() {
      guard isPanelOpen else { return }
      panelItem.isCollapsed = true
      applyMinimumWidth()
    }

    // MARK: - The window's width

    /// Holds the window's minimum *constant* as the panel opens and closes
    /// (`ReaderLayout.minimumWindowWidth(panelIsOpen:)`).
    func applyMinimumWidth() {
      guard let window = view.window else { return }
      window.contentMinSize = NSSize(
        width: ReaderLayout.minimumWindowWidth(panelIsOpen: isPanelOpen), height: 480)
      // A restored frame is not re-checked against the minimum, so a window saved
      // narrower than the floor comes back narrower than the floor.
      var frame = window.frame
      frame.size.width = max(frame.width, window.contentMinSize.width)
      frame.size.height = max(frame.height, window.contentMinSize.height)
      if frame != window.frame { window.setFrame(frame, display: false) }
    }
  }
#endif
