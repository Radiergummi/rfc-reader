import RFCKit
import RFCReaderKit
import SwiftUI

/// Every collection, checked where the document is already in it, and New
/// Collection (#349). One set of items for every entry point: the reader, list
/// rows, and the Mac's menu bar.
///
/// Takes its models as properties rather than from the environment: the Mac's
/// menu bar has no environment to read them from.
struct AddToCollectionItems: View {
  let document: DocumentID
  let library: LibraryModel
  let navigation: NavigationModel
  var undoManager: UndoManager?
  /// Asks for the editor in place of these items, where they are on a sheet: the
  /// sheet has to be gone before the window's root can present another, or UIKit
  /// refuses it and nothing appears.
  var onNewCollection: (() -> Void)?

  var body: some View {
    MenuSections(
      sections: DocumentMenus.addToCollection(document, in: library.collections), perform: perform)
  }

  private func perform(_ action: DocumentMenus.Action) {
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
    default:
      break
    }
  }
}

/// The same choice as a sheet, for a swipe action, which cannot open a menu.
struct AddToCollectionSheet: View {
  let document: DocumentID
  /// New Collection, asked for once this sheet has been dismissed.
  let onNewCollection: () -> Void

  @Environment(LibraryModel.self) private var library
  @Environment(NavigationModel.self) private var navigation
  @Environment(\.undoManager) private var undoManager
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      List {
        // The editor is presented by the window's root, so this sheet steps aside
        // for it: its presenter asks for the editor once it has gone.
        AddToCollectionItems(
          document: document, library: library, navigation: navigation,
          undoManager: undoManager,
          onNewCollection: {
            onNewCollection()
            dismiss()
          })
      }
      .navigationTitle("Add to Collection")
      #if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
      #endif
      .toolbar {
        ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
      }
    }
    .presentationDetents([.medium, .large])
  }
}
