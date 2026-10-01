import RFCKit
import RFCReaderKit
import SwiftUI

#if os(macOS)
  /// What a Mac list row offers on a right click (#349).
  struct MacRowActions: ViewModifier {
    let rfc: RFCMetadata
    let collection: UUID?
    let library: LibraryModel
    let navigation: NavigationModel
    let undoManager: UndoManager?
    let remove: (DocumentID) -> Void

    func body(content: Content) -> some View {
      content.contextMenu {
        Button(action: toggleBookmark) {
          Label(
            isBookmarked ? "Remove Bookmark" : "Bookmark",
            systemImage: isBookmarked ? "bookmark.fill" : "bookmark")
        }
        // macOS 27 hides a menu item's icon unless the label asks to keep it.
        .labelStyle(.titleAndIcon)
        Menu("Add to Collection") {
          AddToCollectionItems(
            document: rfc.id, library: library, navigation: navigation,
            undoManager: undoManager)
        }
        if collection != nil {
          Button("Remove from Collection") { remove(rfc.id) }
        }
      }
    }

    private var isBookmarked: Bool { library.bookmarkedDocuments.contains(rfc.id) }

    private func toggleBookmark() {
      library.toggleBookmark(rfc.id)
    }
  }
#endif
