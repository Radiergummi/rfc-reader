import RFCKit
import RFCReaderKit
import SwiftUI

/// Creating a collection, or renaming and recoloring one (#349).
struct CollectionEditorSheet: View {
  let mode: CollectionEditorMode

  @Environment(LibraryModel.self) private var library
  @Environment(\.dismiss) private var dismiss
  @State private var name = ""
  @State private var color = CollectionColor.default
  @FocusState private var isNameFocused: Bool

  private var title: String {
    if case .edit = mode { "Edit Collection" } else { "New Collection" }
  }

  private var confirmation: String {
    if case .edit = mode { "Save" } else { "Create" }
  }

  /// Deleted elsewhere while being edited — another window, a script, sync.
  private var isGone: Bool {
    if case .edit(let identifier) = mode { library.collections[identifier] == nil } else { false }
  }

  /// The store refuses a name of only spaces; the button says so first.
  private var canSave: Bool {
    !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  var body: some View {
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
      .onAppear(perform: load)
      .onChange(of: isGone) { _, isGone in
        if isGone { dismiss() }
      }
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
      .onAppear(perform: load)
      .onChange(of: isGone) { _, isGone in
        if isGone { dismiss() }
      }
    #endif
  }

  @ViewBuilder
  private var fields: some View {
    TextField("Name", text: $name)
      .focused($isNameFocused)
      .onSubmit { if canSave { save() } }
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
        .accessibilityLabel(swatch.title)
        .accessibilityAddTraits(swatch == color ? .isSelected : [])
      }
    }
    .padding(.vertical, 4)
  }

  private func load() {
    if case .edit(let identifier) = mode, let entry = library.collections[identifier] {
      name = entry.name
      color = entry.color
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
      case .edit(let identifier):
        try CollectionStore.update(identifier, name: name, color: color, in: context)
      }
    }
    dismiss()
  }
}
