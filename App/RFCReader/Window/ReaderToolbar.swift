#if os(macOS)
  import AppKit
  import RFCKit
  import RFCReaderKit

  extension NSToolbarItem.Identifier {
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
  /// hosting view reports no width the toolbar will honour, so every item was laid out
  /// on top of the one before it — the bookmark drew inside the back/forward group and
  /// the share icon over the panel's toggle. Native items also get the system's own
  /// grouping and glass, which a hosted control cannot.
  /// Title over subtitle, the shape a window's own titlebar draws — as a view we own,
  /// so that it takes the width of its text instead of every pixel that is going.
  @MainActor
  private final class TitleView: NSView {
    private let title = TitleView.label(.systemFont(ofSize: 13, weight: .semibold), .labelColor)
    private let subtitle = TitleView.label(.systemFont(ofSize: 11), .secondaryLabelColor)

    static func label(_ font: NSFont, _ colour: NSColor) -> NSTextField {
      let field = NSTextField(labelWithString: "")
      field.font = font
      field.textColor = colour
      field.lineBreakMode = .byTruncatingTail
      field.cell?.usesSingleLineMode = true
      return field
    }

    /// The toolbar sizes a custom view from its constraints, and from nothing else:
    /// an intrinsic width alone left the title drawn on top of the navigation group,
    /// the same way the hosted SwiftUI items drew on top of each other.
    private var widthConstraint: NSLayoutConstraint!

    init() {
      super.init(frame: .zero)
      let stack = NSStackView(views: [title, subtitle])
      stack.orientation = .vertical
      stack.alignment = .leading
      stack.spacing = 0
      stack.translatesAutoresizingMaskIntoConstraints = false
      addSubview(stack)
      translatesAutoresizingMaskIntoConstraints = false
      widthConstraint = widthAnchor.constraint(equalToConstant: 1)
      NSLayoutConstraint.activate([
        stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
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
      self.title.stringValue = title
      self.subtitle.stringValue = subtitle
      self.subtitle.isHidden = subtitle.isEmpty
      // The only place the strings change, so the only place the text has to be
      // measured. `limit(to:)` runs once per frame of a divider drag.
      textWidth = max(
        self.title.intrinsicContentSize.width,
        subtitle.isEmpty ? 0 : self.subtitle.intrinsicContentSize.width
      )
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
    private var textWidth: CGFloat = 0

    private func applyWidth() {
      let width = ToolbarTitleLayout.width(forText: textWidth, inColumn: limit)
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
  /// nothing at all below `ToolbarTitleLayout.isWorthDrawing`. Its text rises in
  /// from below the item's bottom edge and fades in as the heading passes under the
  /// toolbar, scrubbing with the scroll; see `ToolbarTitleReveal`.
  @MainActor
  private final class DocumentTitleView: NSView {
    private let title = TitleView.label(.systemFont(ofSize: 13, weight: .semibold), .labelColor)
    private let subtitle = TitleView.label(.systemFont(ofSize: 11), .secondaryLabelColor)
    private let stack: NSStackView

    private var progress: CGFloat = 0
    private var stackHeight: CGFloat = 0

    init() {
      stack = NSStackView(views: [title, subtitle])
      super.init(frame: .zero)
      stack.orientation = .vertical
      stack.alignment = .leading
      stack.spacing = 0
      for label in [title, subtitle] {
        // Truncated rather than pushing the item wider than it was given.
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
      }
      // Placed by frame, not by constraints: it moves on every scroll tick, and a
      // frame set inside a view whose own size does not change dirties nothing
      // outside it.
      addSubview(stack)
      // The text slides in from outside the item's bounds, and is not seen there.
      wantsLayer = true
      layer?.masksToBounds = true
      translatesAutoresizingMaskIntoConstraints = false
      // Only the height: the width is the toolbar's to hand out, between the
      // item's `minSize` and `maxSize`.
      heightAnchor.constraint(equalToConstant: 32).isActive = true
      reveal(0)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
      fatalError("init(coder:) is not used: the titlebar is built in code")
    }

    func show(_ title: String, subtitle: String) {
      self.title.stringValue = title
      self.subtitle.stringValue = subtitle
      self.subtitle.isHidden = subtitle.isEmpty
      stackHeight = stack.fittingSize.height
      placeStack()
    }

    func reveal(_ progress: CGFloat) {
      self.progress = progress
      // On the text, not on this view: the toolbar sets its items' own alpha
      // for their enabled state and overrides whatever is set here.
      stack.alphaValue = progress
      placeStack()
    }

    override func layout() {
      super.layout()
      placeStack()
    }

    private func placeStack() {
      let resting = (bounds.height - stackHeight) / 2
      // Not flipped, so down is a smaller y: at 0 the text sits a whole item's
      // height below where it rests, just out of sight under the bottom edge.
      let offset = (1 - progress) * bounds.height
      stack.frame = CGRect(
        x: Self.padding,
        y: resting - offset,
        width: max(0, bounds.width - Self.padding * 2),
        height: stackHeight
      )
      // Hidden, not only transparent, while it is out of sight or too narrow to
      // say anything: VoiceOver reads a transparent label all the same.
      stack.isHidden = progress == 0 || !ToolbarTitleLayout.isWorthDrawing(width: bounds.width)
    }

    private static let padding: CGFloat = 8
  }

  @MainActor
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

    private var navigation: NavigationModel { controller.navigation }
    private var reader: ReaderState { controller.reader }
    private var id: DocumentID? { navigation.selection }
    private var metadata: RFCMetadata? { id.flatMap { LibraryModel.shared.metadata($0) } }

    init(controller: ReaderWindowController) {
      self.controller = controller
      super.init()
      citeMenu.delegate = self
      moreMenu.delegate = self
    }

    func showTitle(_ title: String, subtitle: String) {
      titleView.show(title, subtitle: subtitle)
      capTitleToList()
    }

    func showDocumentTitle(_ title: String, subtitle: String) {
      documentTitleView.show(title, subtitle: subtitle)
    }

    func revealDocumentTitle(_ progress: CGFloat) {
      documentTitleView.reveal(progress)
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
        // lands inside that section.
        .toggleSidebar, .rfcSidebarSeparator,
        // The list's section: what is on screen there is what the title names.
        .rfcTitle, .rfcListSeparator,
        // The reader's own section, so Back and Forward stand at the leading edge
        // of the document they act on rather than over the list beside it. The
        // document's title fills the room between them and its actions, which is
        // what holds the actions against the panel's edge.
        .rfcNavigation, .rfcDocumentTitle,
        .rfcBookmark, .rfcCite, .rfcShare, .rfcMore,
        // The panel's own section. The flexible space holds the toggle against
        // the window's trailing corner, so it stays in the corner whether the
        // panel is showing or not rather than travelling with the panel's edge.
        .rfcPanelSeparator, .flexibleSpace, .rfcPanelToggle,
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
        // Deprecated, and the only thing that works. The replacement — width
        // constraints on the view — gives an item exactly its fitting size:
        // measured, a `>= 0, <= text` pair left it 0 pt wide with or without a
        // flexible space beside it, and a low-priority preferred width made it
        // a fixed width the toolbar would not compress, so Back and Forward were
        // pushed out over the list instead. A range here makes it flex.
        item.minSize = NSSize(width: 0, height: 32)
        item.maxSize = NSSize(width: 10_000, height: 32)
        item.isBordered = false
        item.isNavigational = false
        return item

      case .rfcBookmark:
        return button(identifier, "Bookmark", "bookmark", #selector(toggleBookmark))

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

      case .rfcPanelToggle:
        return button(
          identifier, "Contents", "list.bullet.rectangle.portrait", #selector(togglePanel))

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
      switch menu {
      case citeMenu:
        for style in CitationStyle.allCases {
          let item = NSMenuItem(
            title: style.displayName, action: #selector(copyCitation), keyEquivalent: "")
          item.target = self
          item.representedObject = style
          menu.addItem(item)
        }
        menu.addItem(.separator())
        add(to: menu, "Copy Link to Current Section", #selector(copySectionLink))

      case moreMenu:
        let original = NSMenuItem(
          title: "Original Text", action: #selector(toggleOriginalText), keyEquivalent: "")
        original.target = self
        original.state = reader.showOriginal ? .on : .off
        menu.addItem(original)
        add(to: menu, "Open on rfc-editor.org", #selector(openInfoPage))
        if metadata?.errataURL != nil {
          add(to: menu, "Errata", #selector(openErrata))
        }
        add(to: menu, "Datatracker", #selector(openDatatracker))
        if reader.precedingDraft != nil {
          add(to: menu, "Preceding Draft", #selector(openPrecedingDraft))
        }

      default:
        break
      }
    }

    private func add(to menu: NSMenu, _ title: String, _ action: Selector) {
      let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
      item.target = self
      menu.addItem(item)
    }

    // MARK: - Validation

    /// What the bookmark item's glyph is currently showing.
    private var bookmarkSymbol = "bookmark"

    func validateToolbarItem(_ item: NSToolbarItem) -> Bool {
      switch item.itemIdentifier.rawValue {
      case "rfc.back": return navigation.canGoBack
      case "rfc.forward": return navigation.canGoForward
      case NSToolbarItem.Identifier.rfcBookmark.rawValue:
        // The filled glyph is the state, and validation is the one call AppKit
        // makes often enough to keep it honest — which is also why it allocates
        // an image only when the glyph actually changed.
        let symbol = controller.isBookmarked ? "bookmark.fill" : "bookmark"
        if symbol != bookmarkSymbol {
          bookmarkSymbol = symbol
          item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Bookmark")
        }
        return id != nil
      case NSToolbarItem.Identifier.rfcPanelToggle.rawValue:
        return reader.hasDocument
      default:
        return id != nil
      }
    }

    // MARK: - Actions

    @objc private func goBack() { navigation.goBack() }
    @objc private func goForward() { navigation.goForward() }
    @objc private func togglePanel() { controller.togglePanel() }
    @objc private func toggleBookmark() { controller.toggleBookmark() }
    @objc private func toggleOriginalText() { reader.showOriginal.toggle() }

    @objc private func copyCitation(_ sender: NSMenuItem) {
      guard let metadata, let style = sender.representedObject as? CitationStyle else { return }
      Clipboard.copy(
        DocumentActions.citation(metadata, section: reader.currentSection, style: style))
    }

    @objc private func copySectionLink() {
      guard let id else { return }
      Clipboard.copy(DocumentActions.sectionLink(id: id, section: reader.currentSection))
    }

    @objc private func openInfoPage() {
      guard let id else { return }
      NSWorkspace.shared.open(RFCEditorEndpoints.infoPage(id))
    }

    @objc private func openErrata() {
      guard let url = metadata?.errataURL else { return }
      NSWorkspace.shared.open(url)
    }

    @objc private func openDatatracker() {
      guard let id else { return }
      NSWorkspace.shared.open(RFCEditorEndpoints.datatracker(id))
    }

    @objc private func openPrecedingDraft() {
      guard let draft = reader.precedingDraft else { return }
      NSWorkspace.shared.open(draft)
    }
  }

  extension ReaderToolbar: NSSharingServicePickerToolbarItemDelegate {
    func items(for pickerToolbarItem: NSSharingServicePickerToolbarItem) -> [Any] {
      guard let id else { return [] }
      return [RFCEditorEndpoints.infoPage(id)]
    }
  }
#endif
