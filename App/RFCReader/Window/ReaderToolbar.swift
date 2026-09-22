#if os(macOS)
import AppKit
import RFCKit
import SwiftData
import SwiftUI

extension NSToolbarItem.Identifier {
    static let rfcNavigation = NSToolbarItem.Identifier("rfc.navigation")
    static let rfcDocumentActions = NSToolbarItem.Identifier("rfc.documentActions")
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
/// The items themselves are still SwiftUI: an `NSToolbarItem` can hold an
/// `NSHostingView`, so the buttons and menus are the ones `DocumentView` already
/// declared rather than a second set written in AppKit.
@MainActor
final class ReaderToolbar: NSObject, NSToolbarDelegate {
    private unowned let controller: ReaderWindowController

    init(controller: ReaderWindowController) {
        self.controller = controller
        super.init()
    }

    func makeToolbar() -> NSToolbar {
        let toolbar = NSToolbar(identifier: "org.rfc-editor.reader.toolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        return toolbar
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.toggleSidebar, .rfcNavigation, .flexibleSpace, .rfcDocumentActions, .rfcPanelSeparator, .rfcPanelToggle]
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
        case .rfcPanelSeparator:
            // Divider 2 of four items: sidebar | list | reader | panel, so the
            // dividers are 0, 1, 2 and this is the reader's trailing edge.
            return NSTrackingSeparatorToolbarItem(
                identifier: identifier,
                splitView: controller.splitController.splitView,
                dividerIndex: 2
            )
        case .rfcNavigation:
            return hosted(identifier, label: "Navigation", NavigationToolbarView())
        case .rfcDocumentActions:
            return hosted(identifier, label: "Document", DocumentActionsToolbarView())
        case .rfcPanelToggle:
            return hosted(identifier, label: "Contents", PanelToggleToolbarView(toggle: { [weak controller] in
                controller?.togglePanel()
            }))
        default:
            return nil
        }
    }

    private func hosted(_ identifier: NSToolbarItem.Identifier, label: String, _ view: some View) -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.label = label
        let hosting = NSHostingView(rootView: controller.withWindowEnvironment(view))
        hosting.sizingOptions = [.intrinsicContentSize]
        item.view = hosting
        return item
    }
}

// MARK: - Items

/// Back and forward, beside the sidebar toggle.
///
/// Always present, dimmed when there is nowhere to go, as Safari does. A pair that
/// appears and vanishes with the history shifts everything beside it.
private struct NavigationToolbarView: View {
    @Environment(NavigationModel.self) private var navigation

    var body: some View {
        ControlGroup {
            Button {
                navigation.goBack()
            } label: {
                Label("Back", systemImage: "chevron.backward")
            }
            .disabled(!navigation.canGoBack)

            Button {
                navigation.goForward()
            } label: {
                Label("Forward", systemImage: "chevron.forward")
            }
            .disabled(!navigation.canGoForward)
        }
        .controlGroupStyle(.navigation)
    }
}

/// What the document itself can do: bookmark, cite, share, and the rest.
///
/// These were `DocumentView`'s `.toolbar`. They read the window's models rather than
/// the reader's own state, because the toolbar is no longer inside the reader — the
/// one thing they need from the document, the section the reader is looking at, is
/// resolved into `ReaderState.currentSection` by the view that has the document.
private struct DocumentActionsToolbarView: View {
    @Environment(LibraryModel.self) private var library
    @Environment(NavigationModel.self) private var navigation
    @Environment(ReaderState.self) private var reader
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var systemOpenURL
    @Query private var bookmarks: [Bookmark]

    private var id: DocumentID? { navigation.selection }
    private var metadata: RFCMetadata? { id.flatMap { library.metadata($0) } }
    private var isBookmarked: Bool {
        guard let id else { return false }
        return bookmarks.contains { $0.number == id.number }
    }

    var body: some View {
        @Bindable var reader = reader
        if let id, let metadata {
            HStack(spacing: 12) {
                Button {
                    toggleBookmark(id, metadata)
                } label: {
                    Label("Bookmark", systemImage: isBookmarked ? "bookmark.fill" : "bookmark")
                }
                .keyboardShortcut("d", modifiers: .command)

                Menu {
                    ForEach(CitationStyle.allCases) { style in
                        Button(style.displayName) { copyCitation(style, metadata) }
                    }
                    Divider()
                    Button("Copy Link to Current Section") {
                        Clipboard.copy(RFCLink(id: id, section: reader.currentSection).webURL.absoluteString)
                    }
                } label: {
                    Label("Cite", systemImage: "quote.opening")
                }

                ShareLink(item: RFCEditorEndpoints.infoPage(id), subject: Text("\(id.displayName): \(metadata.title)"))

                Menu {
                    Toggle("Original Text", isOn: $reader.showOriginal)
                    Button("Open on rfc-editor.org") { systemOpenURL(RFCEditorEndpoints.infoPage(id)) }
                    if let url = metadata.errataURL {
                        Button("Errata") { systemOpenURL(url) }
                    }
                    Button("Datatracker") { systemOpenURL(RFCEditorEndpoints.datatracker(id)) }
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                }
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .labelStyle(.iconOnly)
            .fixedSize()
        }
    }

    private func toggleBookmark(_ id: DocumentID, _ metadata: RFCMetadata) {
        if let existing = bookmarks.first(where: { $0.number == id.number }) {
            modelContext.delete(existing)
        } else {
            modelContext.insert(Bookmark(number: id.number, title: metadata.title))
        }
    }

    private func copyCitation(_ style: CitationStyle, _ metadata: RFCMetadata) {
        let section = style == .bibtex ? nil : reader.currentSection
        Clipboard.copy(CitationFormatter().cite(metadata, section: section, style: style))
    }
}

/// The panel's toggle: the rightmost thing in the toolbar, out on the panel's glass.
private struct PanelToggleToolbarView: View {
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            Label("Contents", systemImage: "list.bullet.indent")
        }
        .labelStyle(.iconOnly)
        .keyboardShortcut("t", modifiers: [.command, .shift])
    }
}
#endif
