import RFCKit
import RFCReaderKit
import SwiftUI

#if os(macOS)
  /// What a Mac list row offers on a right click (#349): `DocumentMenus.rowActions`,
  /// the table iOS's menu renders too (#761). A series row is bookmarked as itself,
  /// but not added to a collection, which holds RFCs (#321).
  struct MacRowActions: ViewModifier {
    let row: LibraryRow
    let collection: UUID?
    let library: LibraryModel
    let navigation: NavigationModel
    let undoManager: UndoManager?
    let remove: (DocumentID) -> Void

    func body(content: Content) -> some View {
      content.contextMenu {
        let sections = DocumentMenus.rowActions(
          isRFC: row.rfc != nil, opensTabs: true, opensWindows: true,
          inCollection: collection != nil, hasCitationIndex: library.hasCitationIndex)
        DividedSections(sections: sections, item: item)
      }
    }

    @ViewBuilder
    private func item(_ action: DocumentMenus.RowAction) -> some View {
      switch action {
      case .openInNewTab:
        Button {
          library.openTab(RFCLink(id: row.id), beside: navigation)
        } label: {
          Label("Open in New Tab", systemImage: "plus.square.on.square")
        }
        // macOS 27 hides a menu item's icon unless the label asks to keep it.
        .labelStyle(.titleAndIcon)
      case .openInNewWindow:
        Button {
          library.open(RFCLink(id: row.id), placement: .newWindow)
        } label: {
          Label("Open in New Window", systemImage: "macwindow.badge.plus")
        }
        .labelStyle(.titleAndIcon)
      case .bookmark:
        Button(action: toggleBookmark) {
          Label(
            DocumentActions.bookmarkCommand(isBookmarked: isBookmarked),
            systemImage: isBookmarked ? "bookmark.fill" : "bookmark")
        }
        .labelStyle(.titleAndIcon)
      case .addToCollection:
        Menu("Add to Collection", systemImage: "folder.badge.plus") {
          AddToCollectionItems(
            document: row.id, library: library, navigation: navigation,
            undoManager: undoManager)
        }
        .labelStyle(.titleAndIcon)
      case .readingPath:
        Button {
          navigation.readingPath = ReadingPathRequest(root: row.id)
        } label: {
          Label("Reading Path", systemImage: "list.number")
        }
        .labelStyle(.titleAndIcon)
      case .keepOffline:
        KeepOfflineButton(document: row.id, library: library)
          .labelStyle(.titleAndIcon)
      case .share:
        ShareLink(
          item: RFCEditorEndpoints.infoPage(row.id),
          subject: Text(verbatim: "\(row.id.displayName): \(row.title)")
        )
        .labelStyle(.titleAndIcon)
      case .removeFromCollection:
        Button("Remove from Collection") { remove(row.id) }
      }
    }

    private var isBookmarked: Bool { library.bookmarkedDocuments.contains(row.id) }

    private func toggleBookmark() {
      library.toggleBookmark(row.id, undoManager: undoManager)
    }
  }
#endif
