#if os(macOS)
  import AppKit
  import RFCKit
  import RFCReaderKit

  extension NSToolbarItem.Identifier {
    static let rfcNewCollection = NSToolbarItem.Identifier("rfc.newCollection")
    static let rfcSidebarToggle = NSToolbarItem.Identifier("rfc.sidebarToggle")
    static let rfcSidebarSeparator = NSToolbarItem.Identifier("rfc.sidebarSeparator")
    static let rfcListSeparator = NSToolbarItem.Identifier("rfc.listSeparator")
    static let rfcNavigation = NSToolbarItem.Identifier("rfc.navigation")
    static let rfcBack = NSToolbarItem.Identifier("rfc.back")
    static let rfcForward = NSToolbarItem.Identifier("rfc.forward")
    static let rfcDocumentTitle = NSToolbarItem.Identifier("rfc.documentTitle")
    static let rfcTitle = NSToolbarItem.Identifier("rfc.title")
    static let rfcBookmark = NSToolbarItem.Identifier("rfc.bookmark")
    static let rfcCite = NSToolbarItem.Identifier("rfc.cite")
    static let rfcShare = NSToolbarItem.Identifier("rfc.share")
    static let rfcMore = NSToolbarItem.Identifier("rfc.more")
    static let rfcPanelSeparator = NSToolbarItem.Identifier("rfc.panelSeparator")
    static let rfcPanelToggle = NSToolbarItem.Identifier("rfc.panelToggle")
    static let rfcInfoToggle = NSToolbarItem.Identifier("rfc.infoToggle")
  }

  /// `NSToolbarItem.minSize` and `maxSize`, reached without the deprecation warning
  /// they carry since macOS 12.
  ///
  /// Deprecated, and the only thing that makes an item flex. The replacement —
  /// width constraints on the view — gives an item exactly its fitting size:
  /// measured, a `>= 0, <= text` pair left the document's title 0 pt wide with or
  /// without a flexible space beside it, and a low-priority preferred width made it
  /// a fixed width the toolbar would not compress, so Back and Forward were pushed
  /// out over the list instead. The properties still work; going through a
  /// protocol keeps the one deliberate use from being a standing warning that a
  /// build is otherwise clean of. If they stop working, the title collapses to
  /// nothing — it does not break the rest of the toolbar.
  private protocol FlexibleToolbarItem: AnyObject {
    var minSize: NSSize { get set }
    var maxSize: NSSize { get set }
  }

  extension NSToolbarItem: FlexibleToolbarItem {}

  /// The window's toolbar.
  ///
  /// `NSToolbar` only accepts items from its delegate, which is why the overlay panel
  /// could never split it: SwiftUI owned the delegate and would not share it. The item
  /// that does the splitting is `NSTrackingSeparatorToolbarItem`, bound to the divider
  /// between the reader and the panel — AppKit then lays the document's actions out in
  /// what is left of the titlebar, and the panel's toggle sits out on the panel's own
  /// glass, which is where Pages puts it.
  ///
  /// The items are AppKit's own rather than SwiftUI hosted in `NSHostingView`. Hosted
  /// ones were tried first, to keep the declarations `DocumentView` already had: a
  /// hosting view reports no width the toolbar will honor, so every item was laid out
  /// on top of the one before it — the bookmark drew inside the back/forward group and
  /// the share icon over the panel's toggle. Native items also get the system's own
  /// grouping and glass, which a hosted control cannot.
  final class ReaderToolbar: NSObject, NSToolbarDelegate, NSToolbarItemValidation,
    NSMenuItemValidation, NSMenuDelegate
  {
    private unowned let controller: ReaderWindowController

    /// The window's title and subtitle, drawn by us; see `ReaderWindowController`
    /// for why AppKit is not allowed to draw them.
    private let titleView = TitleView()
    private let documentTitleView = DocumentTitleView()

    /// Held so `menuNeedsUpdate` can tell them apart by identity. Their contents are
    /// built when they open rather than held and mutated: what they say depends on
    /// the document, and the document changes under them.
    private let citeMenu = NSMenu()
    private let moreMenu = NSMenu()
    /// Add to Collection, on the Bookmark item's indicator (#349).
    private let collectionMenu = NSMenu()

    private var navigation: NavigationModel { controller.navigation }
    private var reader: ReaderState { controller.reader }
    private var id: DocumentID? { navigation.selection }
    private var library: LibraryModel { controller.library }
    private var metadata: RFCMetadata? { id.flatMap { library.metadata($0) } }

    init(controller: ReaderWindowController) {
      self.controller = controller
      super.init()
      citeMenu.delegate = self
      collectionMenu.delegate = self
      moreMenu.delegate = self
    }

    func showTitle(_ title: String, subtitle: String) {
      titleView.show(title, subtitle: subtitle)
      capTitleToList()
    }

    func showDocumentTitle(_ title: String, subtitle: String) {
      documentTitleView.show(title, subtitle: subtitle)
    }

    /// The bookmark item, for its glyph.
    private weak var bookmarkItem: NSToolbarItem?

    /// Whether the bookmark item currently shows the document as bookmarked.
    private var showsBookmarked = false

    /// Fills the bookmark glyph or empties it. Set from the window's observation of
    /// the selection and the bookmarks, not in `validateToolbarItem`: the item is an
    /// `NSMenuToolbarItem`, which AppKit never validates, so a glyph kept there stayed
    /// empty however the document was bookmarked. An image is made only when the
    /// glyph actually changes.
    ///
    /// The state goes in the tooltip as well, which VoiceOver reads as the item's
    /// help after its label (#278). It would be its value, as on iOS, but neither
    /// `NSToolbarItem` nor `NSMenuToolbarItem` has any accessibility API: the button
    /// VoiceOver reads is a private view AppKit makes for the item, and the tooltip
    /// is the one public way to reach it.
    func showBookmarked(_ isBookmarked: Bool) {
      guard isBookmarked != showsBookmarked else { return }
      showsBookmarked = isBookmarked
      if let bookmarkItem {
        showBookmarkState(on: bookmarkItem)
      }
    }

    /// Puts what `showBookmarked` last chose on the item: the glyph and the tooltip.
    private func showBookmarkState(on item: NSToolbarItem) {
      item.image = NSImage(
        systemSymbolName: showsBookmarked ? "bookmark.fill" : "bookmark",
        accessibilityDescription: String(localized: "Bookmark"))
      item.toolTip = DocumentActions.bookmarkState(isBookmarked: showsBookmarked)
    }

    func updateDocumentTitle(_ state: ToolbarTitleState) {
      documentTitleView.update(state)
    }

    /// Keeps the title inside the column it names. Without it a long title ran past
    /// the list's trailing edge and over the reader's own section.
    func capTitleToList() {
      titleView.limit(to: controller.listWidth)
    }

    func makeToolbar() -> NSToolbar {
      let toolbar = NSToolbar(identifier: "org.rfc-editor.reader.toolbar")
      toolbar.delegate = self
      toolbar.displayMode = .iconOnly
      toolbar.allowsUserCustomization = false
      return toolbar
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
      [
        // Over the sidebar, beside the traffic lights, where Notes and Mail put
        // it: a tracking separator on the sidebar's own divider gives the toolbar
        // a section that ends with the sidebar, and what is declared before it
        // lands inside that section. New Collection stands at the section's
        // trailing edge, against the sidebar's divider, as Notes keeps New Note
        // and Mail keeps Compose: the sidebar's one action, over the sidebar it
        // adds to (#349).
        //
        // The toggle is ours, not AppKit's `.toggleSidebar`. With the sidebar
        // collapsed its section shrinks to the two buttons, which then touch, and
        // Liquid Glass joins the system item to its neighbor with a neck: two
        // circles half fused. Two items of our own touching become one capsule,
        // as Cite, Share and More do, and apart they are two circles exactly like
        // the system's (compared in screenshots of both states). Spacing them
        // does not help: a `.space` gets no width while collapsed, and a spacer
        // view pushed New Collection into the overflow menu.
        .rfcSidebarToggle, .flexibleSpace, .rfcNewCollection, .rfcSidebarSeparator,
        // The list's section: what is on screen there is what the title names.
        .rfcTitle, .rfcListSeparator,
        // The reader's own section, so Back and Forward stand at the leading edge
        // of the document they act on rather than over the list beside it. The
        // document's title fills the room between them and its actions, which is
        // what holds the actions against the panel's edge.
        .rfcNavigation, .rfcDocumentTitle,
        .rfcBookmark, .rfcCite, .rfcShare, .rfcMore,
        // The panel's own section. The flexible space holds the toggles against
        // the window's trailing corner, so they stay in the corner whether the
        // panel is showing or not rather than traveling with the panel's edge.
        // Two, as Pages has Format and Document: each shows its own pane in the
        // one panel (#25).
        .rfcPanelSeparator, .flexibleSpace, .rfcInfoToggle, .rfcPanelToggle,
      ]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
      toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbar(
      _ toolbar: NSToolbar,
      itemForItemIdentifier identifier: NSToolbarItem.Identifier,
      willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
      switch identifier {
      case .rfcSidebarSeparator:
        // Divider 0: sidebar | list.
        return NSTrackingSeparatorToolbarItem(
          identifier: identifier,
          splitView: controller.splitController.splitView,
          dividerIndex: 0
        )

      case .rfcListSeparator:
        // Divider 1: list | reader.
        return NSTrackingSeparatorToolbarItem(
          identifier: identifier,
          splitView: controller.splitController.splitView,
          dividerIndex: 1
        )

      case .rfcPanelSeparator:
        // Divider 2 of four items: sidebar | list | reader | panel, so the
        // dividers are 0, 1, 2 and this is the reader's trailing edge.
        return NSTrackingSeparatorToolbarItem(
          identifier: identifier,
          splitView: controller.splitController.splitView,
          dividerIndex: 2
        )

      case .rfcNavigation:
        // Always both, dimmed when there is nowhere to go, as Safari does. A pair
        // that appears and vanishes with the history shifts everything beside it.
        let back = button(.rfcBack, "Back", "chevron.backward", #selector(goBack))
        let forward = button(.rfcForward, "Forward", "chevron.forward", #selector(goForward))
        let group = NSToolbarItemGroup(itemIdentifier: identifier)
        group.label = String(localized: "Navigation")
        group.subitems = [back, forward]
        group.controlRepresentation = .expanded
        return group

      case .rfcTitle:
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.label = String(
          localized: "Title", comment: "Toolbar item that shows the document's title")
        item.view = titleView
        // Text, not a control: without this the toolbar draws the title inside a
        // bordered pill and it reads as a button.
        item.isBordered = false
        item.isNavigational = false
        // The first thing to give up its room when the window narrows — the
        // sidebar shows which collection is chosen, and the document's actions
        // are nowhere else.
        item.visibilityPriority = .low
        return item

      case .rfcDocumentTitle:
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.label = String(
          localized: "Document", comment: "Toolbar item that shows the open document")
        item.view = documentTitleView
        // A range, so it flexes; see `FlexibleToolbarItem`.
        (item as any FlexibleToolbarItem).minSize = NSSize(width: 0, height: 32)
        (item as any FlexibleToolbarItem).maxSize = NSSize(width: 10_000, height: 32)
        item.isBordered = false
        item.isNavigational = false
        return item

      case .rfcBookmark:
        // A click bookmarks; the indicator opens Add to Collection (#349).
        let item = NSMenuToolbarItem(itemIdentifier: identifier)
        item.label = String(localized: "Bookmark")
        // What `showBookmarked` last chose, which may have come before the item did.
        showBookmarkState(on: item)
        item.showsIndicator = true
        item.target = self
        item.action = #selector(toggleBookmark)
        item.menu = collectionMenu
        bookmarkItem = item
        return item

      case .rfcCite:
        let item = NSMenuToolbarItem(itemIdentifier: identifier)
        item.label = String(localized: "Cite")
        item.image = NSImage(
          systemSymbolName: "quote.opening", accessibilityDescription: String(localized: "Cite"))
        item.showsIndicator = false
        item.menu = citeMenu
        return item

      case .rfcShare:
        let item = NSSharingServicePickerToolbarItem(itemIdentifier: identifier)
        item.label = String(localized: "Share")
        item.delegate = self
        return item

      case .rfcMore:
        let item = NSMenuToolbarItem(itemIdentifier: identifier)
        item.label = String(localized: "More")
        item.image = NSImage(
          systemSymbolName: "ellipsis.circle", accessibilityDescription: String(localized: "More"))
        item.showsIndicator = false
        item.menu = moreMenu
        return item

      case .rfcSidebarToggle:
        return button(identifier, "Sidebar", "sidebar.left", #selector(toggleSidebar))

      case .rfcNewCollection:
        return button(
          identifier, "New Collection", "folder.badge.plus", #selector(newEmptyCollection))

      case .rfcPanelToggle:
        return button(
          identifier, "Contents", "list.bullet.rectangle.portrait", #selector(togglePanel))

      case .rfcInfoToggle:
        return button(identifier, "Info", "info.circle", #selector(toggleInfo))

      default:
        return nil
      }
    }

    private func button(
      _ identifier: NSToolbarItem.Identifier,
      _ label: String.LocalizationValue,
      _ symbol: String,
      _ action: Selector
    ) -> NSToolbarItem {
      // A LocalizationValue rather than a String, so the compiler records each label.
      let label = String(localized: label)
      let item = NSToolbarItem(itemIdentifier: identifier)
      item.label = label
      item.toolTip = label
      item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
      item.target = self
      item.action = action
      item.isBordered = true
      return item
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
      menu.removeAllItems()
      // `NSMenuToolbarItem` opens its menu as a pull-down, and a pull-down's first
      // item is its title, never shown: Cite had no "Short" and More no "Original
      // Text", which left the original text out of reach on the Mac. Hidden, so the
      // menu still reads right where it is not a pull-down -- the overflow menu.
      let title = NSMenuItem()
      title.isHidden = true
      menu.addItem(title)
      switch menu {
      case citeMenu:
        add(DocumentMenus.cite(), to: menu)
      case moreMenu:
        add(
          DocumentMenus.more(
            showsOriginal: reader.showOriginal, errata: metadata?.errataURL,
            precedingDraft: reader.precedingDraft),
          to: menu)
      case collectionMenu:
        add(DocumentMenus.addToCollection(id, in: library.collections), to: menu)
      default:
        return
      }
      // Export and Print are the Mac's own: a chooser and the print panel, where
      // iOS lists the formats and presents its print sheet.
      if menu === moreMenu {
        menu.addItem(.separator())
        let exportItem = NSMenuItem(
          title: String(localized: "Export…"), action: #selector(exportDocument), keyEquivalent: "")
        exportItem.target = self
        menu.addItem(exportItem)
        let printItem = NSMenuItem(
          title: String(localized: "Print…"), action: #selector(printDocument), keyEquivalent: "")
        printItem.target = self
        menu.addItem(printItem)
      }
    }

    /// Each item carries its action, which `performMenuAction` carries out.
    private func add<Performed>(_ sections: DocumentMenus.Sections<Performed>, to menu: NSMenu) {
      for (index, items) in sections.enumerated() {
        if index > 0 { menu.addItem(.separator()) }
        for entry in items {
          let item = NSMenuItem(
            title: entry.title, action: #selector(performMenuAction), keyEquivalent: "")
          item.target = self
          item.representedObject = entry.action
          if let isOn = entry.isOn { item.state = isOn ? .on : .off }
          if let icon = entry.icon {
            item.image = icon.image
            item.showsImageOnMacOS27()
          }
          menu.addItem(item)
        }
      }
    }

    // MARK: - Validation

    /// More's Export and Print, for a document read as its text (#207); the rest of
    /// what the toolbar's menus hold is always available.
    func validateMenuItem(_ item: NSMenuItem) -> Bool {
      switch item.action {
      case #selector(exportDocument), #selector(printDocument): reader.offersPrintAndExport
      default: true
      }
    }

    func validateToolbarItem(_ item: NSToolbarItem) -> Bool {
      switch item.itemIdentifier.rawValue {
      case NSToolbarItem.Identifier.rfcBack.rawValue: return navigation.canGoBack
      case NSToolbarItem.Identifier.rfcForward.rawValue: return navigation.canGoForward
      case NSToolbarItem.Identifier.rfcPanelToggle.rawValue,
        NSToolbarItem.Identifier.rfcInfoToggle.rawValue:
        // Whatever the index describes, before its body or without it (#325).
        return reader.canDescribe
      case NSToolbarItem.Identifier.rfcNewCollection.rawValue,
        NSToolbarItem.Identifier.rfcSidebarToggle.rawValue:
        // Neither needs a document, so a window without one has both.
        return true
      default:
        return id != nil
      }
    }

    // MARK: - Actions

    @objc private func goBack() { navigation.goBack() }
    @objc private func goForward() { navigation.goForward() }
    @objc private func togglePanel() { controller.press(.navigation) }
    @objc private func toggleInfo() { controller.press(.info) }
    @objc private func toggleBookmark() { controller.toggleBookmark() }
    @objc private func toggleSidebar() { controller.toggleSidebar() }

    /// What an item of Cite, More or Add to Collection does.
    @objc private func performMenuAction(_ sender: NSMenuItem) {
      guard let id else { return }
      switch sender.representedObject {
      case let action as DocumentMenus.Action:
        DocumentActionPerformer(
          id: id, metadata: metadata, reader: reader, open: { NSWorkspace.shared.open($0) }
        ).perform(action)
      case let action as DocumentMenus.CollectionAction:
        CollectionActionPerformer(
          document: id, library: library, navigation: navigation,
          undoManager: controller.window?.undoManager
        ).perform(action)
      default:
        break
      }
    }

    @objc private func newEmptyCollection() { controller.newCollection() }

    @objc private func printDocument() { controller.printDocument() }
    @objc private func exportDocument() { controller.exportDocument() }
  }

  extension ReaderToolbar: NSSharingServicePickerToolbarItemDelegate {
    func items(for pickerToolbarItem: NSSharingServicePickerToolbarItem) -> [Any] {
      guard let id else { return [] }
      return [RFCEditorEndpoints.infoPage(id)]
    }
  }
#endif
