import Foundation
import RFCKit
import RFCReaderKit

/// Carries out an item of Cite or More, on either platform: what it comes to is
/// `DocumentMenus.Action.effect`, and this copies, opens or toggles (#600). The
/// Mac's toolbar opens with `NSWorkspace`, iOS's with the environment's `openURL`.
struct DocumentActionPerformer {
  /// The RFC acted on; nil for a draft (#728), whose text has only its toggles.
  let id: DocumentID?
  /// What a citation is made from: the document the tab opened, a series as itself
  /// (#656), as `LibraryModel.citedDocument` has it.
  let cited: CitedDocument?
  let reader: ReaderState
  let open: (URL) -> Void

  func perform(_ action: DocumentMenus.Action) {
    let effect = action.effect(
      for: id, citing: cited, section: reader.currentSection,
      settings: ReaderSettings(defaults: .standard))
    switch effect {
    case .copy(let text, let feedback): Clipboard.copy(text, announcing: feedback)
    case .open(let url): open(url)
    case .toggleOriginalText: reader.showOriginal.toggle()
    case .toggleTranslation: reader.showTranslation.toggle()
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
        try CollectionStore.toggle(
          document, in: collection, undoManager: undoManager,
          onUndoFailure: library.collectionUndoFailed, in: $0)
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
