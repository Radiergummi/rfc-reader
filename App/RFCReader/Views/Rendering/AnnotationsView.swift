import RFCKit
import RFCReaderKit
import SwiftUI

/// The document panel's Annotations tab (#522): every highlight of the document, in
/// document order, with its quote and its section; a click goes to it. Those drawn
/// nowhere come last, marked: an ambiguous one may be placed at one of the places its
/// quote is, and either kind deleted.
///
/// What is listed, and in what order, is `AnnotationList`'s, under test; this only
/// draws it.
struct AnnotationsView: View {
  let highlights: [AnnotationSnapshot.HighlightEntry]
  /// Where the build on screen placed each one; nil without a build, when only the
  /// stored quotes can be listed.
  let statuses: [UUID: HighlightPlacement.Status]?
  /// The sections the body holds, which name a row's section.
  let sections: [RFCKit.Section]
  let library: LibraryModel
  /// Goes to an anchor, the way a Contents row goes to its section.
  let select: (String) -> Void

  @Environment(\.undoManager) private var undoManager

  var body: some View {
    let rows = AnnotationList.rows(highlights, statuses: statuses)
    if rows.isEmpty {
      ContentUnavailableView(
        "No Annotations", systemImage: "highlighter",
        description: Text("Select text in the document and choose Highlight."))
    } else {
      VStack(spacing: 0) {
        if statuses == nil {
          Text("The document is unavailable, so its highlights cannot be shown in it.")
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
    }
  }

  private func row(_ row: AnnotationList.Row) -> some View {
    Button {
      if case .placed(let anchor, _) = row.placement { select(anchor) }
    } label: {
      HStack(alignment: .firstTextBaseline, spacing: 8) {
        HighlightSwatch(color: row.color)
          .scaleEffect(0.6)
          .frame(width: 14, height: 14)
          .accessibilityHidden(true)
        VStack(alignment: .leading, spacing: 3) {
          Text(verbatim: row.quote)
            .lineLimit(4)
            .fixedSize(horizontal: false, vertical: true)
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
  }

  /// The section a placed highlight is in, or what is the matter with one drawn
  /// nowhere.
  private func caption(of row: AnnotationList.Row) -> String? {
    switch row.placement {
    case .placed(_, let section):
      guard let section else { return nil }
      if section == ModelText.abstractAnchor { return String(localized: "Abstract") }
      return sections.first { $0.anchor == section }?.displayTitle
    case .ambiguous:
      return String(localized: "In several places: choose one, or delete it.")
    case .detached:
      return String(localized: "This passage no longer exists in this document.")
    case .unplaced:
      return nil
    }
  }

  @ViewBuilder
  private func menu(for row: AnnotationList.Row) -> some View {
    if case .ambiguous(let places) = row.placement {
      ForEach(Array(places.enumerated()), id: \.offset) { index, place in
        Button("Place at Occurrence \(index + 1)") {
          library.placeHighlight(row.id, at: place, undoManager: undoManager)
        }
      }
      Divider()
    }
    Button("Delete Highlight", role: .destructive) {
      library.deleteHighlight(row.id, undoManager: undoManager)
    }
  }
}
