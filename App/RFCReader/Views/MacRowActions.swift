import RFCKit
import RFCReaderKit
import SwiftUI

#if os(macOS)
  /// What a Mac list row offers on a right click (#349). A series row is bookmarked
  /// as itself, but not added to a collection, which holds RFCs (#321).
  struct MacRowActions: ViewModifier {
    let row: LibraryRow
    let collection: UUID?
    let library: LibraryModel
    let navigation: NavigationModel
    let undoManager: UndoManager?
    let remove: (DocumentID) -> Void

    func body(content: Content) -> some View {
      content.contextMenu {
        Button(action: toggleBookmark) {
          Label(
            DocumentActions.bookmarkCommand(isBookmarked: isBookmarked),
            systemImage: isBookmarked ? "bookmark.fill" : "bookmark")
        }
        // macOS 27 hides a menu item's icon unless the label asks to keep it.
        .labelStyle(.titleAndIcon)
        if row.rfc != nil {
          Menu("Add to Collection") {
            AddToCollectionItems(
              document: row.id, library: library, navigation: navigation,
              undoManager: undoManager)
          }
          Button {
            navigation.readingPath = ReadingPathRequest(root: row.id)
          } label: {
            Label("Reading Path", systemImage: "list.number")
          }
          .labelStyle(.titleAndIcon)
          Button {
            library.setKeptOfflineInBackground(row.id, !isKeptOffline)
          } label: {
            Label(
              isKeptOffline ? "Stop Keeping Offline" : "Keep Offline",
              systemImage: isKeptOffline ? "xmark.circle" : "arrow.down.circle")
          }
          .labelStyle(.titleAndIcon)
        }
        if collection != nil {
          Button("Remove from Collection") { remove(row.id) }
        }
      }
    }

    private var isBookmarked: Bool { library.bookmarkedDocuments.contains(row.id) }
    private var isKeptOffline: Bool { library.offlineMarks.contains(row.id) }

    private func toggleBookmark() {
      library.toggleBookmark(row.id)
    }
  }
#endif
