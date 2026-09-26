import RFCKit
import RFCReaderKit
import SwiftUI

enum InspectorTab {
  case contents
  case references
}

/// The document's two navigational views, sharing one panel.
///
/// The bibliography is here rather than in the reading flow: every citation in the
/// prose already links straight to the document it names, so the section was several
/// screens of rows nobody reads in order. As a panel it can be consulted beside the
/// text instead of interrupting it.
struct DocumentInspector: View {
  /// The sections the body actually contains, and the bibliography it does not.
  /// Both are derived once per document by `DocumentView` rather than here, where
  /// every section crossing re-evaluates this body.
  let sections: [RFCKit.Section]
  let groups: [ReferenceGroup]
  @Binding var tab: InspectorTab
  let current: String?
  let selectSection: (String) -> Void
  let openDocument: (DocumentID) -> Void

  var body: some View {
    VStack(spacing: 0) {
      InspectorTabBar(tab: $tab)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)

      switch tab {
      case .contents:
        TableOfContentsView(sections: sections, current: current, select: selectSection)
      case .references:
        // A document with no bibliography says so here rather than being
        // steered away from the tab.
        ReferencesView(groups: groups, open: openDocument)
      }
    }
  }
}

/// `DocumentInspector` wired to the window's `ReaderState`, and the one place that
/// wiring is written.
///
/// macOS hosts this in the window's own split item and iOS presents it with
/// `.inspector`; the six inputs are the same either way, so the next one added to
/// `DocumentInspector` is added once.
struct PanelHost: View {
  @Environment(LibraryModel.self) private var library
  @Environment(NavigationModel.self) private var navigation
  @Environment(ReaderState.self) private var reader

  var body: some View {
    @Bindable var reader = reader
    if reader.hasDocument {
      DocumentInspector(
        sections: reader.sections,
        groups: reader.groups,
        tab: $reader.tab,
        current: reader.currentAnchor,
        selectSection: { navigation.jump(toSection: $0) },
        openDocument: { library.open($0, activation: .current, in: navigation) }
      )
    } else {
      Color.clear
    }
  }
}

/// The panel's two tabs, drawn the way an inspector's are rather than as a segmented
/// control.
///
/// `.pickerStyle(.segmented)` draws a bordered control sized to its labels, which
/// reads as a form field sitting on the panel rather than as the panel's own
/// navigation. Pages, Numbers and Keynote all use this shape instead: the full width
/// of the inspector, no enclosing border, the selected tab a filled pill, and a hair
/// divider only between two unselected labels.
private struct InspectorTabBar: View {
  @Binding var tab: InspectorTab

  var body: some View {
    // No rule between the two: Pages draws one only between labels that are both
    // unselected, and with two tabs one of them always is the pill.
    HStack(spacing: 0) {
      segment(.contents, "Contents")
      segment(.references, "References")
    }
    // The track the segments sit in, and the inset that keeps the selected pill
    // inside it rather than flush with its edge.
    .padding(2)
    .background(.quaternary.opacity(0.7), in: .capsule)
  }

  private func segment(_ value: InspectorTab, _ title: String) -> some View {
    let isSelected = tab == value
    return Button {
      tab = value
    } label: {
      Text(title)
        .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
        .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
        .lineLimit(1)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 5)
        .background {
          if isSelected {
            // Fully rounded, not a rounded rectangle: the selected tab in
            // an inspector is a capsule, and at this height the difference
            // between a 7 pt radius and a capsule is the whole look.
            Capsule().fill(Color.accentColor)
          }
        }
        .contentShape(.rect)
    }
    .buttonStyle(.plain)
  }
}

struct ReferencesView: View {
  let groups: [ReferenceGroup]
  let open: (DocumentID) -> Void

  var body: some View {
    if groups.isEmpty {
      ContentUnavailableView("No References", systemImage: "book.closed")
    } else {
      List {
        ForEach(groups) { group in
          Section(group.title) {
            ForEach(group.entries) { entry in
              ReferenceRow(entry: entry, open: open)
            }
          }
        }
      }
      .listStyle(.sidebar)
    }
  }
}

/// One entry, as a row rather than the four stacked indented paragraphs the body
/// used to render: what it is, then who wrote it and when.
struct ReferenceRow: View {
  let entry: Reference
  let open: (DocumentID) -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 3) {
      HStack(alignment: .firstTextBaseline, spacing: 6) {
        if entry.documentID != nil {
          Image(systemName: "doc.text").foregroundStyle(.tint).imageScale(.small)
        }
        Text(entry.displayAnchor)
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(entry.documentID != nil ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
      }
      if entry.title.isEmpty {
        // A legacy-text entry that could not be structured keeps its own words.
        if let raw = entry.rawText {
          Text(raw).font(.caption).foregroundStyle(.secondary)
        }
      } else {
        Text(entry.title).font(.callout).fixedSize(horizontal: false, vertical: true)
        let byline = entry.authors.joined(separator: ", ")
        let detail = [byline, entry.provenance].filter { !$0.isEmpty }.joined(separator: " · ")
        if !detail.isEmpty {
          Text(detail)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
      // What the author added after the entry, most often the commit a living
      // standard was cited at; its link opens in the browser like any other.
      if let annotation = entry.annotationText {
        Text(annotation)
          .font(.caption)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
    .padding(.vertical, 2)
    .contentShape(Rectangle())
    .onTapGesture { if let id = entry.documentID { open(id) } }
  }
}
