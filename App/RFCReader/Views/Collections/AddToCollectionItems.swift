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
  /// Called after New Collection has asked for the editor, so a sheet showing
  /// these items can get out of the editor's way.
  var onNewCollection: (() -> Void)?

  var body: some View {
    let containing = library.collections.collections(containing: document)
    ForEach(library.collections.collections) { entry in
      Toggle(
        entry.name,
        isOn: Binding(
          get: { containing.contains(entry.id) },
          set: { _ in
            library.editCollections {
              try CollectionStore.toggle(
                document, in: entry.id, undoManager: undoManager, in: $0)
            }
          }))
    }
    if !library.collections.collections.isEmpty { Divider() }
    Button("New Collection…") {
      navigation.collectionEditor = .create(adding: document)
      onNewCollection?()
    }
  }
}

/// The same choice as a sheet, for a swipe action, which cannot open a menu.
struct AddToCollectionSheet: View {
  let document: DocumentID

  @Environment(LibraryModel.self) private var library
  @Environment(NavigationModel.self) private var navigation
  @Environment(\.undoManager) private var undoManager
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      List {
        // The editor is presented by the window's root, so this sheet steps aside
        // for it.
        AddToCollectionItems(
          document: document, library: library, navigation: navigation,
          undoManager: undoManager, onNewCollection: { dismiss() })
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
