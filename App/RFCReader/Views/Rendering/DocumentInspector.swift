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
      #if os(macOS)
        InspectorTabBar(tab: $tab)
          .padding(.horizontal, 10)
          .padding(.vertical, 8)
      #else
        // The system's segmented control, inside the panel it switches (#247).
        //
        // Not in a toolbar: `.inspector` lifts its content's toolbar items into the
        // reader's own bar, even through a `NavigationStack` of the panel's own, so
        // the tabs ended up above the reader, apart from the sheet they switch and
        // in the place of the reader's title. The insets are the sheet's rather
        // than the inspector column's: 10 and 8 left the control against the
        // sheet's top edge, its capsule ends inside the sheet's rounded corners.
        Picker("Panel", selection: $tab) {
          Text("Contents").tag(InspectorTab.contents)
          Text("References").tag(InspectorTab.references)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 8)
      #endif

      selectedTab
    }
  }

  @ViewBuilder
  private var selectedTab: some View {
    switch tab {
    case .contents:
      // Opened at the section being read rather than at the top: from §15 of a long
      // RFC, the top of the list is a long way from where the reader is.
      ScrollViewReader { proxy in
        TableOfContentsView(sections: sections, current: current, select: selectSection)
          .task {
            // A turn later, once the list has rows to scroll to: a timing guess,
            // since `List` offers no initial scroll position to declare instead.
            await Task.yield()
            if let current { proxy.scrollTo(current, anchor: .center) }
          }
      }
    case .references:
      // A document with no bibliography says so here rather than being steered
      // away from the tab.
      ReferencesView(groups: groups, open: openDocument)
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
  /// Called after a choice in the panel has navigated, which is when iOS closes the
  /// panel's sheet. Nothing on macOS, where the panel is a split item beside the
  /// text and collapses through AppKit, not through a SwiftUI presentation.
  var didNavigate: () -> Void = {}

  var body: some View {
    @Bindable var reader = reader
    if reader.hasDocument {
      DocumentInspector(
        sections: reader.sections,
        groups: reader.groups,
        tab: $reader.tab,
        current: reader.currentAnchor,
        selectSection: {
          navigation.jump(toSection: $0)
          didNavigate()
        },
        openDocument: {
          library.open($0, activation: .current, in: navigation)
          didNavigate()
        }
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
///
/// macOS only: in an iPhone's sheet the system's own segmented control sits in the
/// panel's bar instead (#247).
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
      entryDescription
        .contentShape(Rectangle())
        .onTapGesture { if let id = entry.documentID { open(id) } }
      // What the author added after the entry, most often the commit a living
      // standard was cited at; its link opens in the browser like any other.
      // Outside the tap gesture, which would otherwise take the link's click.
      if let annotation = entry.annotationText {
        Text(annotation)
          .font(.caption)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
    #if os(macOS)
      .padding(.vertical, 2)
    #else
      // Entries of three lines each, in an inset list, need more room between them
      // than the denser macOS inspector gives them (#248).
      .padding(.vertical, 8)
    #endif
  }

  private var entryDescription: some View {
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
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}
