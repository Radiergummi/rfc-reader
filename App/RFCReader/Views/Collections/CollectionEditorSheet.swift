import RFCKit
import RFCReaderKit
import SwiftUI

/// Creating a collection, or renaming and recoloring one (#349), and the query of
/// one made from a query (#355): one text field, read and written as the search
/// field's.
struct CollectionEditorSheet: View {
  let mode: CollectionEditorMode

  @Environment(LibraryModel.self) private var library
  @Environment(\.dismiss) private var dismiss
  @State private var name = ""
  @State private var color = CollectionColor.default
  /// The query of a collection made from one; nil for a manual collection.
  @State private var query: String?
  @FocusState private var isNameFocused: Bool

  private var title: String {
    switch mode {
    case .edit: String(localized: "Edit Collection")
    case .create: String(localized: "New Collection")
    case .save: String(localized: "Save as Collection")
    }
  }

  private var confirmation: String {
    if case .edit = mode { String(localized: "Save") } else { String(localized: "Create") }
  }

  /// Deleted elsewhere while being edited — another window, a script, sync.
  private var isGone: Bool {
    if case .edit(let identifier) = mode { library.collections[identifier] == nil } else { false }
  }

  /// The store refuses a name of only spaces, and an empty query; the button says
  /// so first.
  private var canSave: Bool {
    CollectionStore.isValidName(name) && (query.map(CollectionStore.isValidQuery) ?? true)
  }

  var body: some View {
    form
      .onAppear(perform: load)
      .onChange(of: isGone) { _, isGone in
        if isGone { dismiss() }
      }
  }

  @ViewBuilder
  private var form: some View {
    #if os(macOS)
      VStack(alignment: .leading, spacing: 12) {
        Text(title).font(.headline)
        fields
        HStack {
          Spacer()
          Button("Cancel", role: .cancel) { dismiss() }
            .keyboardShortcut(.cancelAction)
          Button(confirmation, action: save)
            .keyboardShortcut(.defaultAction)
            .disabled(!canSave)
        }
      }
      .padding(20)
      .frame(width: 360)
    #else
      NavigationStack {
        Form { fields }
          .navigationTitle(title)
          .navigationBarTitleDisplayMode(.inline)
          .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
              Button(confirmation, action: save).disabled(!canSave)
            }
          }
      }
      .presentationDetents([.medium])
    #endif
  }

  @ViewBuilder
  private var fields: some View {
    TextField("Name", text: $name)
      .focused($isNameFocused)
      .onSubmit { if canSave { save() } }
    if let query {
      TextField(
        "Query",
        text: Binding(get: { query }, set: { self.query = $0 }),
        prompt: Text(verbatim: "wg:quic status:std congestion"),
        axis: .vertical
      )
      .lineLimit(1...4)
      .onSubmit { if canSave { save() } }
      Text("Lists every RFC that matches, as the search field would.")
        .font(.caption)
        .foregroundStyle(.secondary)
    }
    HStack(spacing: 10) {
      ForEach(CollectionColor.allCases) { swatch in
        Button {
          color = swatch
        } label: {
          Circle()
            .fill(swatch.color)
            .frame(width: 24, height: 24)
            .overlay {
              if swatch == color {
                Circle().strokeBorder(.primary, lineWidth: 2).padding(-4)
              }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(swatch.title())
        .accessibilityAddTraits(swatch == color ? .isSelected : [])
      }
    }
    .padding(.vertical, 4)
  }

  private func load() {
    switch mode {
    case .edit(let identifier):
      guard let entry = library.collections[identifier] else { break }
      name = entry.name
      color = entry.color
      query = entry.query
    case .save(let saved):
      query = saved
    case .create:
      break
    }
    isNameFocused = true
  }

  private func save() {
    library.editCollections { context in
      switch mode {
      case .create(let document):
        let collection = try CollectionStore.create(named: name, color: color, in: context)
        if let document {
          try CollectionStore.add(document, to: collection.identifier, in: context)
        }
      case .save:
        try CollectionStore.create(named: name, color: color, query: query, in: context)
      case .edit(let identifier):
        try CollectionStore.update(
          identifier, name: name, color: color, query: query, in: context)
      }
    }
    dismiss()
  }
}
