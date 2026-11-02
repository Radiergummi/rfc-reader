import RFCKit
import RFCReaderKit
import SwiftUI

/// The document panel's Annotations tab (#522, #523): every highlight of the document,
/// with the first line of each note on it, and every note on a block or a section of
/// its own, in document order, with its quote and its section. A click on a row goes
/// to it; a click on a note goes there too, and opens its editor. Those placed nowhere
/// come last, marked: an ambiguous highlight may be placed at one of the places its
/// quote is, and any of them deleted.
///
/// What is listed, and in what order, is `AnnotationList`'s, under test; this only
/// draws it.
struct AnnotationsView: View {
  let highlights: [AnnotationSnapshot.HighlightEntry]
  let notes: [AnnotationSnapshot.NoteEntry]
  /// Where the build on screen placed each one; nil without a build, when only the
  /// stored quotes can be listed.
  let statuses: [UUID: HighlightPlacement.Status]?
  let notePlacement: NotePlacement?
  /// Why they are not placed, when they are not.
  let note: String?
  /// The sections the body holds, which name a row's section.
  let sections: [RFCKit.Section]
  let library: LibraryModel
  /// Goes to an anchor, the way a Contents row goes to its section.
  let select: (String) -> Void
  /// Opens a note's editor in the reader.
  let openNote: (NoteRequest) -> Void

  @Environment(\.undoManager) private var undoManager
  /// A highlight with notes, whose deletion waits for the reader to confirm it.
  @State private var deleting: AnnotationList.Row?

  var body: some View {
    let rows = AnnotationList.rows(
      highlights, notes: notes, statuses: statuses, noteStatuses: notePlacement)
    if rows.isEmpty {
      ContentUnavailableView(
        "No Annotations", systemImage: "highlighter",
        description: Text("Select text in the document and choose Highlight or Add Note."))
    } else {
      VStack(spacing: 0) {
        if let note {
          Text(verbatim: note)
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        List(rows) { row in
          self.row(row)
            .contextMenu { menu(for: row) }
        }
        .listStyle(.sidebar)
        // A sidebar list is announced as "Sidebar", which is the window's own (#300).
        .accessibilityLabel("Annotations")
      }
      .confirmationDialog(
        "Delete the highlight and its notes?", isPresented: isConfirmingDelete,
        presenting: deleting
      ) { row in
        Button("Delete Highlight and Notes", role: .destructive) {
          library.deleteHighlight(row.id, undoManager: undoManager)
        }
      }
    }
  }

  private var isConfirmingDelete: Binding<Bool> {
    Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })
  }

  private func row(_ row: AnnotationList.Row) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Button {
        if case .placed(let anchor, _) = row.placement {
          select(anchor)
          if row.isNote, let note = row.notes.first { openNote(.existing(note.id)) }
        }
      } label: {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
          marker(of: row)
          VStack(alignment: .leading, spacing: 3) {
            if !row.quote.isEmpty {
              Text(verbatim: row.quote)
                .lineLimit(4)
                .fixedSize(horizontal: false, vertical: true)
            }
            if row.isNote, let note = row.notes.first {
              Text(verbatim: note.firstLine)
                .lineLimit(2)
                .foregroundStyle(row.quote.isEmpty ? .primary : .secondary)
            }
            if let caption = caption(of: row) {
              Text(verbatim: caption)
                .font(.caption)
                .foregroundStyle(.secondary)
            }
          }
        }
        .contentShape(.rect)
      }
      .buttonStyle(.plain)
      if !row.isNote {
        ForEach(row.notes) { note in
          Button {
            if case .placed(let anchor, _) = row.placement { select(anchor) }
            openNote(.existing(note.id))
          } label: {
            Label {
              Text(verbatim: note.firstLine).lineLimit(2)
            } icon: {
              Image(systemName: "note.text")
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            .padding(.leading, 22)
          }
          .buttonStyle(.plain)
        }
      }
    }
  }

  @ViewBuilder
  private func marker(of row: AnnotationList.Row) -> some View {
    if let color = row.color {
      HighlightSwatch(color: color)
        .scaleEffect(0.6)
        .frame(width: 14, height: 14)
        .accessibilityHidden(true)
    } else {
      Image(systemName: "note.text")
        .foregroundStyle(.secondary)
        .frame(width: 14, height: 14)
        .accessibilityHidden(true)
    }
  }

  /// The section a placed row is in, or what is the matter with one placed nowhere.
  private func caption(of row: AnnotationList.Row) -> String? {
    switch row.placement {
    case .placed(_, let section):
      guard let section else { return nil }
      if section == ModelText.abstractAnchor { return String(localized: "Abstract") }
      return sections.first { $0.anchor == section }?.displayTitle
    case .ambiguous(let places):
      // A note's row offers no place to choose.
      if places.isEmpty {
        return String(localized: "This passage is in several places in this document.")
      }
      return String(localized: "In several places: choose one, or delete it.")
    case .detached:
      return String(localized: "This passage no longer exists in this document.")
    case .unplaced:
      return nil
    }
  }

  @ViewBuilder
  private func menu(for row: AnnotationList.Row) -> some View {
    if row.isNote {
      if let note = row.notes.first {
        Button("Edit Note") {
          if case .placed(let anchor, _) = row.placement { select(anchor) }
          openNote(.existing(note.id))
        }
        Button("Delete Note", role: .destructive) {
          library.deleteNote(note.id, undoManager: undoManager)
        }
      }
    } else {
      if case .ambiguous(let places) = row.placement {
        ForEach(Array(places.enumerated()), id: \.offset) { index, place in
          Button("Place at Occurrence \(index + 1)") {
            library.placeHighlight(row.id, at: place, undoManager: undoManager)
          }
        }
        Divider()
      }
      if case .placed(let anchor, _) = row.placement {
        Button("Add Note") {
          select(anchor)
          openNote(.new(.highlight(row.id)))
        }
      }
      Button("Delete Highlight", role: .destructive) {
        if row.notes.isEmpty {
          library.deleteHighlight(row.id, undoManager: undoManager)
        } else {
          deleting = row
        }
      }
    }
  }
}
