import RFCKit
import RFCReaderKit
import SwiftUI

/// The library, searchable, for adding documents to a collection (#349). Choosing
/// a result toggles it, and the sheet stays open for more.
struct CollectionPickerSheet: View {
  let collection: UUID

  @Environment(LibraryModel.self) private var library
  @Environment(\.dismiss) private var dismiss
  @Environment(\.undoManager) private var undoManager
  @State private var query = ""
  @State private var limit = ListWindow.page

  var body: some View {
    // Unsearched, the whole library newest first, as All RFCs lists it:
    // `librarySearch` goes through the same list computation with the `.all` filter.
    let rows = library.librarySearch(query)
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
