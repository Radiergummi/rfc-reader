import RFCKit
import RFCReaderKit
import SwiftUI

/// A request for a document's reading path, as `NavigationModel` holds it.
struct ReadingPathRequest: Identifiable {
  let root: DocumentID
  var id: DocumentID { root }
}

/// What to read before a document, in order (#189): the documents it cites
/// normatively, and theirs, each after what it depends on, from the `indexes` pack.
///
/// The documents nearly everything cites are listed once at the top as assumed.
/// Obsoleted documents stay on the path, since they are the text the citing
/// document depends on, and name their successors. The path can be saved as a
/// collection, in its order.
struct ReadingPathSheet: View {
  let root: DocumentID

  @Environment(LibraryModel.self) private var library
  @Environment(NavigationModel.self) private var navigation
  @Environment(\.dismiss) private var dismiss
  @State private var depth = ReadingPath.defaultDepth
  /// Nil until the first walk answers. A deeper walk keeps the last one on show.
  @State private var loaded: Loaded?
  @State private var isWalking = false
  @State private var isSaved = false

  /// A walk's answer, with its rows read once rather than on every body pass: a
  /// row's read mark is a fetch.
  private enum Loaded {
    case path(ReadingPath, assumed: [ReadingPath.Row], steps: [ReadingPath.Row])
    case noIndex
    case failed
  }

  private var title: String { ReadingPath.title(for: root) }

  private var path: ReadingPath? {
    if case .path(let path, _, _) = loaded { path } else { nil }
  }

  var body: some View {
    form
      .task(id: depth) {
        isWalking = true
        defer { isWalking = false }
        let result = await library.readingPath(from: root, depth: depth)
        // A deeper path is another list, which can be saved again; the one still on
        // show until now cannot.
        isSaved = false
        switch result {
        case .path(let path):
          let read = Set(library.recentlyRead())
          let rows = path.rows(metadata: library.metadata, isRead: read.contains)
          loaded = .path(path, assumed: rows.assumed, steps: rows.steps)
        case .noIndex:
          loaded = .noIndex
        case .failed:
          loaded = .failed
        }
      }
  }

  @ViewBuilder
  private var form: some View {
    #if os(macOS)
      VStack(alignment: .leading, spacing: 12) {
        Text(title).font(.headline)
        content
          .frame(maxWidth: .infinity, maxHeight: .infinity)
        HStack {
          saveButton
          Spacer()
          Button("Done") { dismiss() }
            .keyboardShortcut(.defaultAction)
        }
      }
      .padding(20)
      .frame(width: 480, height: 560)
    #else
      NavigationStack {
        content
          .navigationTitle(title)
          .navigationBarTitleDisplayMode(.inline)
          .toolbar {
            ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            ToolbarItem(placement: .bottomBar) { saveButton }
          }
      }
    #endif
  }

  @ViewBuilder
  private var content: some View {
    switch loaded {
    case nil:
      ProgressView()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    case .noIndex:
      ContentUnavailableView(
        "No Citation Index", systemImage: "point.3.connected.trianglepath.dotted",
        description: Text(
          "A reading path is computed from the citation index, which is a data pack of its own and isn't installed."
        ))
    case .failed:
      ContentUnavailableView(
        "Couldn't Read the Citation Index", systemImage: "exclamationmark.triangle",
        description: Text("The installed index pack couldn't be read."))
    case .path(let path, let assumed, let steps):
      list(path, assumed: assumed, steps: steps)
    }
  }

  private func list(
    _ path: ReadingPath, assumed: [ReadingPath.Row], steps: [ReadingPath.Row]
  ) -> some View {
    List {
      if !assumed.isEmpty {
        Section {
          ForEach(assumed) { row($0) }
        } header: {
          Text("Assumed")
        } footer: {
          Text(
            "Cited normatively across so much of the series that they're listed once here, not followed."
          )
        }
      }
      Section {
        ForEach(steps) { row($0) }
        if path.isCut {
          Button {
            depth += 1
          } label: {
            HStack {
              Text("Show Deeper")
              if isWalking {
                Spacer()
                ProgressView().controlSize(.small)
              }
            }
          }
          .disabled(isWalking)
        }
      } header: {
        Text("In Order")
      } footer: {
        if !path.undeclared.isEmpty {
          VStack(alignment: .leading, spacing: 4) {
            ForEach(path.undeclared, id: \.self) { id in
              Text(
                "\(id.displayName) doesn't say which of its references are normative, so none of them are followed."
              )
            }
          }
        }
      }
    }
  }

  private func row(_ row: ReadingPath.Row) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 10) {
      Image(systemName: row.isRead ? "checkmark.circle.fill" : "circle")
        .foregroundStyle(row.isRead ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
        .accessibilityLabel(row.isRead ? "Read" : "Not read")
      VStack(alignment: .leading, spacing: 2) {
        Button {
          open(row.document)
        } label: {
          VStack(alignment: .leading, spacing: 2) {
            Text(row.document.displayName)
              .font(.subheadline.monospacedDigit())
              .foregroundStyle(.secondary)
            if let title = row.title {
              Text(title).foregroundStyle(.primary)
            }
          }
          .frame(maxWidth: .infinity, alignment: .leading)
          .contentShape(.rect)
        }
        .buttonStyle(.borderless)
        if !row.obsoletedBy.isEmpty {
          HStack(spacing: 4) {
            Text("Obsoleted by")
            ForEach(row.obsoletedBy, id: \.self) { successor in
              Button(successor.displayName) { open(successor) }
                .buttonStyle(.borderless)
            }
          }
          .font(.caption)
          .foregroundStyle(.orange)
        }
      }
    }
    .typesettingLanguage(.init(identifier: "en"))
  }

  private var saveButton: some View {
    Button(action: save) {
      Label(
        isSaved ? "Saved as Collection" : "Save as Collection", systemImage: "folder.badge.plus")
    }
    .disabled(path == nil || isSaved)
  }

  /// A new collection, named for the root, holding the assumed documents and then
  /// the path, in order.
  private func save() {
    guard let path else { return }
    isSaved = library.editCollections { context in
      try CollectionStore.create(
        named: path.collectionName, color: .default, documents: path.documents, in: context)
    }
  }

  private func open(_ id: DocumentID) {
    dismiss()
    library.open(id, activation: .current, in: navigation)
  }
}
