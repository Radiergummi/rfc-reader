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

  /// A title over a line of detail, as a window's own titlebar draws its title over
  /// its subtitle: the list's title.
  private final class TitleStack: NSStackView {
    private let title = TitleStack.titleLabel()
    private let subtitle = TitleStack.subtitleLabel()

    /// What the longer of the two lines needs. Measured when the strings change,
    /// which is the only time it can: the list's title is capped once per frame of
    /// a divider drag, and reads this rather than measuring again.
    private(set) var textWidth: CGFloat = 0

    init() {
      super.init(frame: .zero)
      orientation = .vertical
      alignment = .leading
      spacing = 0
      addArrangedSubview(title)
      addArrangedSubview(subtitle)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
      fatalError("init(coder:) is not used: the titlebar is built in code")
    }

    func show(_ title: String, subtitle: String) {
      self.title.stringValue = title
      self.subtitle.stringValue = subtitle
      self.subtitle.isHidden = subtitle.isEmpty
      textWidth = max(
        self.title.intrinsicContentSize.width,
        subtitle.isEmpty ? 0 : self.subtitle.intrinsicContentSize.width
      )
    }

    /// The two lines' type, shared with the reader's title — which lays its lines
    /// out itself — so the toolbar's two titles cannot drift apart in type.
    static func titleLabel() -> NSTextField {
      label(.systemFont(ofSize: 13, weight: .semibold), .labelColor)
    }

    static func subtitleLabel() -> NSTextField {
      label(.systemFont(ofSize: 11), .secondaryLabelColor)
    }

    private static func label(_ font: NSFont, _ color: NSColor) -> NSTextField {
      let field = NSTextField(labelWithString: "")
      field.font = font
      field.textColor = color
      field.lineBreakMode = .byTruncatingTail
      field.cell?.usesSingleLineMode = true
      // Truncated rather than pushing its title wider than it was given.
      field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
      return field
    }
  }

  /// Title over subtitle, the shape a window's own titlebar draws — as a view we own,
  /// so that it takes the width of its text instead of every pixel that is going.
  private final class TitleView: NSView {
    private let stack = TitleStack()

    /// The toolbar sizes a custom view from its constraints, and from nothing else:
    /// an intrinsic width alone left the title drawn on top of the navigation group,
    /// the same way the hosted SwiftUI items drew on top of each other.
    private var widthConstraint: NSLayoutConstraint!

    init() {
      super.init(frame: .zero)
      stack.translatesAutoresizingMaskIntoConstraints = false
      addSubview(stack)
      translatesAutoresizingMaskIntoConstraints = false
      widthConstraint = widthAnchor.constraint(equalToConstant: 1)
      NSLayoutConstraint.activate([
        stack.leadingAnchor.constraint(
          equalTo: leadingAnchor, constant: ToolbarTitleLayout.padding),
        stack.trailingAnchor.constraint(equalTo: trailingAnchor),
        stack.centerYAnchor.constraint(equalTo: centerYAnchor),
        heightAnchor.constraint(equalToConstant: 32),
        widthConstraint,
      ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
      fatalError("init(coder:) is not used: the titlebar is built in code")
    }

    func show(_ title: String, subtitle: String) {
      stack.show(title, subtitle: subtitle)
      applyWidth()
    }

    /// The width of the column the title sits over. The labels truncate with an
    /// ellipsis inside whatever this leaves them.
    func limit(to column: CGFloat) {
      guard column != limit else { return }
      limit = column
      applyWidth()
    }

    private var limit: CGFloat = 0

    private func applyWidth() {
      let width = ToolbarTitleLayout.width(forText: stack.textWidth, inColumn: limit)
      // Assigning a constant dirties the titlebar's layout whether or not it moved.
      guard width != widthConstraint.constant else { return }
      widthConstraint.constant = width
    }
  }

  /// The document's number over its title, in the reader's own toolbar section once
  /// the header that shows them has scrolled away.
  ///
  /// It is the filler between Back/Forward and the document's actions — the item
  /// takes the place of the flexible space that stood there — and it shrinks to
  /// nothing rather than overflowing into the toolbar's chevron menu, drawing
  /// nothing at all below `ToolbarTitleLayout.isWorthDrawing`. Its text rises out
  /// from under the toolbar's bottom edge and fades in as the heading passes under
  /// the toolbar, scrubbing with the scroll; see `ToolbarTitleReveal`. Its subtitle
  /// names the section being read; see `RunningHeading`.
  private final class DocumentTitleView: NSView {
    private let title = TitleStack.titleLabel()
    /// The subtitle's line, clipped to itself: a section's heading hands over to
    /// the next inside it, one rising out as the other rises in.
    private let subtitleLine = NSView()
    private let outgoing = TitleStack.subtitleLabel()
    private let incoming = TitleStack.subtitleLabel()
    /// Title over subtitle, which the reveal moves as one.
    private let content = NSView()
    /// What the text is clipped to: from the top of the item down to the toolbar's
    /// bottom edge, which is below the item's own — the toolbar gives the item 32
    /// pt in the middle of a taller bar. Clipped at the item's edge instead, the
    /// text appeared out of a line drawn across the middle of the toolbar.
    private let clip = NSView()

    private var state = ToolbarTitleState.hidden
    /// What the subtitle says wherever no section's heading does: over the title
    /// page and the abstract.
    private var documentTitle = ""
    /// The toolbar's bottom edge, in this view's coordinates: below zero.
    private var toolbarBottom: CGFloat = 0

    /// One line of each, measured once: the type is fixed, and a line's height
    /// does not depend on what it says.
    private let titleHeight: CGFloat
    private let subtitleHeight: CGFloat

    init() {
      titleHeight = TitleStack.titleLabel().fittingSize.height
      subtitleHeight = TitleStack.subtitleLabel().fittingSize.height
      super.init(frame: .zero)
      // Everything is placed by frame, not by constraints: it moves on every
      // scroll tick, and a frame set inside a view whose own size does not change
      // dirties nothing outside it.
      subtitleLine.wantsLayer = true
      subtitleLine.layer?.masksToBounds = true
      subtitleLine.addSubview(outgoing)
      subtitleLine.addSubview(incoming)
      content.addSubview(title)
      content.addSubview(subtitleLine)
      clip.wantsLayer = true
      clip.layer?.masksToBounds = true
      clip.addSubview(content)
      addSubview(clip)
      // The clip reaches below this view's bounds, so this view must not cut it
      // off at its own edge. Its size is the item's `minSize` and `maxSize`.
      clipsToBounds = false
      placeContent()
      placeHandOver()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
      fatalError("init(coder:) is not used: the titlebar is built in code")
    }

    func show(_ title: String, subtitle: String) {
      self.title.stringValue = title
      documentTitle = subtitle
      applyText()
    }

    /// Only what changed: while the title slides in the hand-over holds still,
    /// and while a heading hands over the title does, so a scroll tick moves one
    /// or the other rather than every view in the item.
    func update(_ state: ToolbarTitleState) {
      let previous = self.state
      self.state = state
      if state.runningHeading.outgoing != previous.runningHeading.outgoing
        || state.runningHeading.incoming != previous.runningHeading.incoming
      {
        applyText()
      }
      if state.reveal != previous.reveal {
        placeContent()
      }
      if state.runningHeading.progress != previous.runningHeading.progress {
        placeHandOver()
      }
    }

    override func layout() {
      super.layout()
      // Where the toolbar ends, which is where the window's content begins. Only
      // a layout pass can move it, so it is measured here rather than per tick.
      if let window {
        let edge = convert(NSPoint(x: 0, y: window.contentLayoutRect.maxY), from: nil).y
        toolbarBottom = min(0, edge)
      }
      clip.frame = CGRect(
        x: 0, y: toolbarBottom, width: bounds.width, height: bounds.height - toolbarBottom)
      // The lines' frames depend on the width alone.
      let width = lineWidth
      title.frame = CGRect(x: 0, y: subtitleHeight, width: width, height: titleHeight)
      subtitleLine.frame = CGRect(x: 0, y: 0, width: width, height: subtitleHeight)
      placeContent()
      placeHandOver()
    }

    private var lineWidth: CGFloat {
      max(0, bounds.width - ToolbarTitleLayout.padding * 2)
    }

    /// Each label only when its words change: a label assigned the same string
    /// redraws for nothing.
    private func applyText() {
      let outgoingText = state.runningHeading.outgoing ?? documentTitle
      let incomingText = state.runningHeading.incoming ?? documentTitle
      if outgoing.stringValue != outgoingText { outgoing.stringValue = outgoingText }
      if incoming.stringValue != incomingText { incoming.stringValue = incomingText }
    }

    /// The reveal: title and subtitle, moved and faded as one.
    private func placeContent() {
      // Not flipped, so up is a larger y. At 0 the text's top is at the
      // toolbar's bottom edge, just out of sight under it; at 1 it rests in the
      // middle of the item.
      let height = titleHeight + subtitleHeight
      let hidden = toolbarBottom - height
      let resting = (bounds.height - height) / 2
      let y = hidden + (resting - hidden) * state.reveal
      content.frame = CGRect(
        x: ToolbarTitleLayout.padding, y: y - toolbarBottom, width: lineWidth, height: height)
      // On the text, not on this view: the toolbar sets its items' own alpha
      // for their enabled state and overrides whatever is set here.
      content.alphaValue = ToolbarTitleReveal.opacity(atProgress: state.reveal)
      // Hidden, not only transparent, while out of sight or too narrow to say
      // anything: VoiceOver reads a transparent label all the same.
      content.isHidden =
        state.reveal == 0 || !ToolbarTitleLayout.isWorthDrawing(width: bounds.width)
    }

    /// The hand-over: the outgoing heading rises out of the subtitle's line as
    /// the incoming one rises in, each transparent while the line's edge cuts it.
    private func placeHandOver() {
      let handOver = state.runningHeading.progress
      let width = lineWidth
      outgoing.frame = CGRect(
        x: 0, y: handOver * subtitleHeight, width: width, height: subtitleHeight)
      incoming.frame = CGRect(
        x: 0, y: (handOver - 1) * subtitleHeight, width: width, height: subtitleHeight)
      outgoing.alphaValue = ToolbarTitleReveal.opacity(atProgress: 1 - handOver)
      incoming.alphaValue = ToolbarTitleReveal.opacity(atProgress: handOver)
      outgoing.isHidden = handOver == 1
      incoming.isHidden = handOver == 0
    }
  }

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
  final class ReaderToolbar: NSObject, NSToolbarDelegate, NSToolbarItemValidation, NSMenuDelegate {
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

    /// What the bookmark item's glyph is currently showing.
    private var bookmarkSymbol = "bookmark"

    /// Fills the bookmark glyph or empties it. Set from the window's observation of
    /// the selection and the bookmarks, not in `validateToolbarItem`: the item is an
    /// `NSMenuToolbarItem`, which AppKit never validates, so a glyph kept there stayed
    /// empty however the document was bookmarked. An image is made only when the
    /// glyph actually changes.
    func showBookmarked(_ isBookmarked: Bool) {
      let symbol = isBookmarked ? "bookmark.fill" : "bookmark"
      guard symbol != bookmarkSymbol else { return }
      bookmarkSymbol = symbol
      bookmarkItem?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Bookmark")
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
        let back = button(
          NSToolbarItem.Identifier("rfc.back"), "Back", "chevron.backward", #selector(goBack))
        let forward = button(
          NSToolbarItem.Identifier("rfc.forward"), "Forward", "chevron.forward",
          #selector(goForward))
        let group = NSToolbarItemGroup(itemIdentifier: identifier)
        group.label = "Navigation"
        group.subitems = [back, forward]
        group.controlRepresentation = .expanded
        return group

      case .rfcTitle:
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.label = "Title"
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
        item.label = "Document"
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
        item.label = "Bookmark"
        // What `showBookmarked` last chose, which may have come before the item did.
        item.image = NSImage(
          systemSymbolName: bookmarkSymbol, accessibilityDescription: "Bookmark")
        item.showsIndicator = true
        item.target = self
        item.action = #selector(toggleBookmark)
        item.menu = collectionMenu
        bookmarkItem = item
        return item

      case .rfcCite:
        let item = NSMenuToolbarItem(itemIdentifier: identifier)
        item.label = "Cite"
        item.image = NSImage(systemSymbolName: "quote.opening", accessibilityDescription: "Cite")
        item.showsIndicator = false
        item.menu = citeMenu
        return item

      case .rfcShare:
        let item = NSSharingServicePickerToolbarItem(itemIdentifier: identifier)
        item.label = "Share"
        item.delegate = self
        return item

      case .rfcMore:
        let item = NSMenuToolbarItem(itemIdentifier: identifier)
        item.label = "More"
        item.image = NSImage(systemSymbolName: "ellipsis.circle", accessibilityDescription: "More")
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
      _ label: String,
      _ symbol: String,
      _ action: Selector
    ) -> NSToolbarItem {
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
      let sections: DocumentMenus.Sections
      switch menu {
      case citeMenu:
        sections = DocumentMenus.cite()
      case moreMenu:
        sections = DocumentMenus.more(
          showsOriginal: reader.showOriginal, errata: metadata?.errataURL,
          precedingDraft: reader.precedingDraft)
      case collectionMenu:
        sections = DocumentMenus.addToCollection(id, in: library.collections)
      default:
        return
      }
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
      // Export and Print are the Mac's own: a chooser and the print panel, where
      // iOS lists the formats and presents its print sheet.
      if menu === moreMenu {
        menu.addItem(.separator())
        let exportItem = NSMenuItem(
          title: "Export…", action: #selector(exportDocument), keyEquivalent: "")
        exportItem.target = self
        menu.addItem(exportItem)
        let printItem = NSMenuItem(
          title: "Print…", action: #selector(printDocument), keyEquivalent: "")
        printItem.target = self
        menu.addItem(printItem)
      }
    }

    // MARK: - Validation

    func validateToolbarItem(_ item: NSToolbarItem) -> Bool {
      switch item.itemIdentifier.rawValue {
      case "rfc.back": return navigation.canGoBack
      case "rfc.forward": return navigation.canGoForward
      case NSToolbarItem.Identifier.rfcPanelToggle.rawValue,
        NSToolbarItem.Identifier.rfcInfoToggle.rawValue:
        return reader.hasDocument
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
      guard let id, let action = sender.representedObject as? DocumentMenus.Action else { return }
      switch action {
      case .copyCitation(let style):
        guard let metadata else { return }
        Clipboard.copy(
          DocumentActions.citation(metadata, section: reader.currentSection, style: style))
      case .copySectionLink:
        Clipboard.copy(DocumentActions.sectionLink(id: id, section: reader.currentSection))
      case .toggleOriginalText:
        reader.showOriginal.toggle()
      case .openInfoPage:
        NSWorkspace.shared.open(RFCEditorEndpoints.infoPage(id))
      case .openErrata(let url), .openPrecedingDraft(let url):
        NSWorkspace.shared.open(url)
      case .openDatatracker:
        NSWorkspace.shared.open(RFCEditorEndpoints.datatracker(id))
      case .toggleCollection(let collection):
        library.editCollections {
          try CollectionStore.toggle(
            id, in: collection, undoManager: controller.window?.undoManager, in: $0)
        }
      case .newCollection:
        navigation.collectionEditor = .create(adding: id)
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
