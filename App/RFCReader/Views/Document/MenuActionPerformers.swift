import Foundation
import RFCKit
import RFCReaderKit

/// Carries out an item of Cite or More, on either platform: what it comes to is
/// `DocumentMenus.Action.effect`, and this copies, opens or toggles (#600). The
/// Mac's toolbar opens with `NSWorkspace`, iOS's with the environment's `openURL`.
struct DocumentActionPerformer {
  let id: DocumentID
  let metadata: RFCMetadata?
  let reader: ReaderState
  let open: (URL) -> Void

  func perform(_ action: DocumentMenus.Action) {
    switch action.effect(for: id, metadata: metadata, section: reader.currentSection) {
    case .copy(let text, let feedback): Clipboard.copy(text, announcing: feedback)
    case .open(let url): open(url)
    case .toggleOriginalText: reader.showOriginal.toggle()
    case nil: break
    }
  }
}

/// Carries out an item of Add to Collection, wherever it is offered: the reader's
/// toolbar on either platform, a list row, a sheet, and the Mac's menu bar.
struct CollectionActionPerformer {
  let document: DocumentID
  let library: LibraryModel
  let navigation: NavigationModel
  let undoManager: UndoManager?
  /// Asks for the editor in place of New Collection's own request, where the items
  /// are on a sheet: see `AddToCollectionItems`.
  var onNewCollection: (() -> Void)?

  func perform(_ action: DocumentMenus.CollectionAction) {
    switch action {
    case .toggleCollection(let collection):
      library.editCollections {
        try CollectionStore.toggle(document, in: collection, undoManager: undoManager, in: $0)
      }
    case .newCollection:
      if let onNewCollection {
        onNewCollection()
      } else {
        navigation.collectionEditor = .create(adding: document)
      }
    }
  }
}
