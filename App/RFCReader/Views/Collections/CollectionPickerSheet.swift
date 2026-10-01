import RFCKit
import RFCReaderKit
import SwiftUI

/// The library, searchable, for adding documents to a collection (#349). Choosing
/// a result toggles it, and the sheet stays open for more.
struct CollectionPickerSheet: View {
  let collection: UUID
  /// The presenter's, so a removal can still be undone once the sheet is gone.
  let undoManager: UndoManager?

  @Environment(LibraryModel.self) private var library
  @Environment(\.dismiss) private var dismiss
  @State private var query = ""
  @State private var limit = ListWindow.page
  /// Unsearched, the whole library newest first, as All RFCs lists it: the same
  /// listing with the `.all` filter, made off the main actor (#597).
  @State private var rows: [RFCMetadata] = []

  /// What the rows are listed again for: the query, and a new index.
  private struct Listing: Equatable {
    let query: String
    let index: LibraryModel.IndexState
  }

  var body: some View {
    let members = Set(library.collections[collection]?.members ?? [])
    let trigger = ListWindow.triggerRow(limit: limit, total: rows.count).map { rows[$0].id }
    NavigationStack {
      List(rows.prefix(limit)) { rfc in
        let isMember = members.contains(rfc.id)
        Button {
          library.editCollections {
            try CollectionStore.toggle(rfc.id, in: collection, undoManager: undoManager, in: $0)
          }
        } label: {
          HStack {
            RFCRow(rfc: rfc, isBookmarked: false)
            Image(systemName: isMember ? "checkmark.circle.fill" : "circle")
              .foregroundStyle(isMember ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
              .accessibilityHidden(true)
          }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isMember ? .isSelected : [])
        .onAppear {
          guard rfc.id == trigger else { return }
          limit = ListWindow.extendedLimit(from: limit, total: rows.count)
        }
      }
      .searchable(text: $query, prompt: "Search RFCs")
      .onChange(of: query) { limit = ListWindow.page }
      .task(id: Listing(query: query, index: library.indexState)) {
        let list = LibraryList(filter: .all, query: query)
        let pause = list.query.isEmpty ? Duration.zero : AppliedSearch.pause
        guard await Debounce.outlasted(pause), let listed = await library.listed(list),
          !Task.isCancelled
        else { return }
        rows = listed.rows
      }
      // Deleted elsewhere — another window, a script, sync — there is nothing left
      // to add to.
      .onChange(of: library.collections[collection] == nil) { _, isGone in
        if isGone { dismiss() }
      }
      .navigationTitle("Add to \(library.title(for: .collection(collection)))")
      #if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
      #endif
      .toolbar {
        ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
      }
    }
    #if os(macOS)
      .frame(minWidth: 480, minHeight: 520)
    #endif
  }
}
