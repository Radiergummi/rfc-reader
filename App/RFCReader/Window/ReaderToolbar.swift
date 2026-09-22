#if os(macOS)
import AppKit
import RFCKit
import RFCReaderKit

extension NSToolbarItem.Identifier {
    static let rfcSidebarSeparator = NSToolbarItem.Identifier("rfc.sidebarSeparator")
    static let rfcNavigation = NSToolbarItem.Identifier("rfc.navigation")
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

    private static func label(_ font: NSFont, _ colour: NSColor) -> NSTextField {
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
        // Capped, because a long RFC title would otherwise push the document's own
        // actions off the toolbar.
        let text = max(
            self.title.intrinsicContentSize.width,
            self.subtitle.isHidden ? 0 : self.subtitle.intrinsicContentSize.width
        )
        widthConstraint.constant = min(text, 360) + 16
    }
}

@MainActor
final class ReaderToolbar: NSObject, NSToolbarDelegate, NSToolbarItemValidation, NSMenuDelegate {
    private unowned let controller: ReaderWindowController

    /// The window's title and subtitle, drawn by us; see `ReaderWindowController`
    /// for why AppKit is not allowed to draw them.
    private let titleView = TitleView()

    private var navigation: NavigationModel { controller.navigation }
    private var reader: ReaderState { controller.reader }
    private var id: DocumentID? { navigation.selection }
    private var metadata: RFCMetadata? { id.flatMap { LibraryModel.shared.metadata($0) } }

    init(controller: ReaderWindowController) {
        self.controller = controller
        super.init()
    }

    func showTitle(_ title: String, subtitle: String) {
        titleView.show(title, subtitle: subtitle)
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
            .rfcNavigation, .rfcTitle, .flexibleSpace,
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
            let back = button(NSToolbarItem.Identifier("rfc.back"), "Back", "chevron.backward", #selector(goBack))
            let forward = button(NSToolbarItem.Identifier("rfc.forward"), "Forward", "chevron.forward", #selector(goForward))
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
            // The first thing to give up its room when the window narrows — the tab
            // bar carries the same title, and the document's actions do not.
            item.visibilityPriority = .low
            return item

        case .rfcBookmark:
            return button(identifier, "Bookmark", "bookmark", #selector(toggleBookmark))

        case .rfcCite:
            let item = NSMenuToolbarItem(itemIdentifier: identifier)
            item.label = "Cite"
            item.image = NSImage(systemSymbolName: "quote.opening", accessibilityDescription: "Cite")
            item.showsIndicator = false
            item.menu = menu(delegate: self, tag: MenuTag.cite)
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
            item.menu = menu(delegate: self, tag: MenuTag.more)
            return item

        case .rfcPanelToggle:
            return button(identifier, "Contents", "list.bullet.indent", #selector(togglePanel))

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

    /// Both menus are built when they open rather than held and mutated: what they
    /// say depends on the document, and the document changes under them.
    private enum MenuTag {
        static let cite = 1
        static let more = 2
    }

    private func menu(delegate: NSMenuDelegate, tag: Int) -> NSMenu {
        let menu = NSMenu()
        menu.delegate = delegate
        menu.identifier = NSUserInterfaceItemIdentifier("rfc.menu.\(tag)")
        return menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        switch menu.identifier?.rawValue {
        case "rfc.menu.\(MenuTag.cite)":
            for style in CitationStyle.allCases {
                let item = NSMenuItem(title: style.displayName, action: #selector(copyCitation), keyEquivalent: "")
                item.target = self
                item.representedObject = style
                menu.addItem(item)
            }
            menu.addItem(.separator())
            let link = NSMenuItem(title: "Copy Link to Current Section", action: #selector(copySectionLink), keyEquivalent: "")
            link.target = self
            menu.addItem(link)

        case "rfc.menu.\(MenuTag.more)":
            let original = NSMenuItem(title: "Original Text", action: #selector(toggleOriginalText), keyEquivalent: "")
            original.target = self
            original.state = reader.showOriginal ? .on : .off
            menu.addItem(original)
            add(to: menu, "Open on rfc-editor.org", #selector(openInfoPage))
            if metadata?.errataURL != nil {
                add(to: menu, "Errata", #selector(openErrata))
            }
            add(to: menu, "Datatracker", #selector(openDatatracker))

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

    func validateToolbarItem(_ item: NSToolbarItem) -> Bool {
        switch item.itemIdentifier.rawValue {
        case "rfc.back": return navigation.canGoBack
        case "rfc.forward": return navigation.canGoForward
        case NSToolbarItem.Identifier.rfcBookmark.rawValue:
            // The filled glyph is the state, and validation is the one call AppKit
            // makes often enough to keep it honest.
            item.image = NSImage(
                systemSymbolName: controller.isBookmarked ? "bookmark.fill" : "bookmark",
                accessibilityDescription: "Bookmark"
            )
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
        let section = style == .bibtex ? nil : reader.currentSection
        Clipboard.copy(CitationFormatter().cite(metadata, section: section, style: style))
    }

    @objc private func copySectionLink() {
        guard let id else { return }
        Clipboard.copy(RFCLink(id: id, section: reader.currentSection).webURL.absoluteString)
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
}

extension ReaderToolbar: NSSharingServicePickerToolbarItemDelegate {
    func items(for pickerToolbarItem: NSSharingServicePickerToolbarItem) -> [Any] {
        guard let id else { return [] }
        return [RFCEditorEndpoints.infoPage(id)]
    }
}
#endif
