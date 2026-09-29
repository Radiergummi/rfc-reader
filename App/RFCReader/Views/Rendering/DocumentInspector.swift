import RFCKit
import RFCReaderKit
import SwiftUI

enum InspectorTab: CaseIterable {
  case contents
  case references
  /// Every BCP 14 requirement the document states (#180).
  case requirements

  /// Named once, for both platforms' tab bars (#258).
  var title: String {
    switch self {
    case .contents: "Contents"
    case .references: "References"
    case .requirements: "Requirements"
    }
  }
}

/// The inspector beside the reader: the document's two navigational views, or what
/// is known about it (#25), whichever `pane` says.
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
  let requirements: [Requirement]?
  let info: DocumentInfo?
  /// For the Info pane's offline copy, which is the store's rather than derived.
  let document: DocumentID?
  let library: LibraryModel
  let pane: InspectorPane
  @Binding var tab: InspectorTab
  let current: String?
  /// The bibliography entry a citation asked to see, if any.
  let revealed: ReaderState.RevealedReference?
  let selectSection: (String) -> Void
  let openDocument: (DocumentID) -> Void
  /// Searches the library, for a keyword chosen in the Info pane.
  let search: (String) -> Void

  var body: some View {
    switch pane {
    case .navigation: navigation
    case .info:
      InfoView(
        info: info, document: document, library: library, open: openDocument, search: search)
    }
  }

  private var navigation: some View {
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
          ForEach(InspectorTab.allCases, id: \.self) { tab in
            Text(tab.title).tag(tab)
          }
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
      ReferencesView(
        groups: groups, revealed: revealed, open: openDocument,
        openInNewWindow: openInNewWindow)
    case .requirements:
      RequirementsView(requirements: requirements, document: document, select: selectSection)
    }
  }

  /// Offered on iPad, where a reference can open in a window of its own (#158).
  private var openInNewWindow: ((DocumentID) -> Void)? {
    #if os(macOS)
      nil
    #else
      library.opensNewWindows ? { library.openWindow(for: $0) } : nil
    #endif
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
  #if !os(macOS)
    /// The panel's presentation. None on macOS, where the panel is a split item
    /// that collapses through AppKit.
    ///
    /// A binding and a flag rather than a closure, because both compare equal to
    /// themselves and a closure never does: with a closure, every pass of the
    /// reader's body drew the panel and its whole table of contents again (#259).
    @Binding var isPresented: Bool
    /// Whether a choice that navigates closes the panel: when it is a sheet over
    /// the text, and what was chosen is behind it (#249). Beside the text, as a
    /// column, it stays open. The reader decides, from its own width: the size
    /// class inside the panel is the panel's, which as a narrow column may be
    /// compact while the reader is not.
    let closesAfterChoice: Bool
  #endif

  var body: some View {
    @Bindable var reader = reader
    if reader.hasDocument {
      DocumentInspector(
        sections: reader.sections,
        groups: reader.groups,
        requirements: reader.requirements,
        info: reader.info,
        document: navigation.selection,
        library: library,
        pane: reader.pane,
        tab: $reader.tab,
        // Read only while the navigation pane shows: it changes on every section
        // crossing, and read under the Info pane it re-rendered that pane each time.
        current: reader.pane == .navigation ? reader.currentAnchor : nil,
        revealed: reader.revealedReference,
        selectSection: {
          navigation.jump(toSection: $0)
          didNavigate()
        },
        openDocument: { id in
          leave { library.open(id, activation: .current, in: navigation) }
        },
        search: { text in
          leave {
            navigation.search(text)
            #if !os(macOS)
              // An iPhone shows the list or the reader, not both: the results are
              // the list's, so the reader steps back to it.
              if closesAfterChoice { navigation.selection = nil }
            #endif
          }
        }
      )
    } else {
      Color.clear
    }
  }

  private func didNavigate() {
    #if !os(macOS)
      if closesAfterChoice { isPresented = false }
    #endif
  }

  /// A choice that leaves this document: another RFC, or the list. The sheet is
  /// closed first and the choice made a turn later (#298). Made at once, it replaced
  /// the reader, whose view owns the sheet, before the sheet heard it should close,
  /// so the sheet stayed up with nothing in it.
  private func leave(_ choice: @escaping () -> Void) {
    #if !os(macOS)
      if closesAfterChoice {
        isPresented = false
        Task { choice() }
        return
      }
    #endif
    choice()
  }
}

/// The navigation pane's tabs, drawn the way an inspector's are rather than as a segmented
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
    // No rule between them: Pages draws one only between labels that are both
    // unselected, and the pill sits between any two of these.
    HStack(spacing: 0) {
      ForEach(InspectorTab.allCases, id: \.self) { tab in
        segment(tab, tab.title)
      }
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
      // A text style rather than a fixed 13 pt, so the tabs follow the text size;
      // on macOS `.body` is the same 13 pt.
      Text(title)
        .font(.body.weight(isSelected ? .semibold : .regular))
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
    // The pill shows which tab is chosen; this says so to VoiceOver (#156).
    .accessibilityAddTraits(isSelected ? .isSelected : [])
  }
}

struct ReferencesView: View {
  let groups: [ReferenceGroup]
  let revealed: ReaderState.RevealedReference?
  let open: (DocumentID) -> Void
  let openInNewWindow: ((DocumentID) -> Void)?

  /// The revealed entry, marked for a moment so the eye finds it in the list.
  @State private var highlighted: String?

  var body: some View {
    if groups.isEmpty {
      ContentUnavailableView("No References", systemImage: "book.closed")
    } else {
      ScrollViewReader { proxy in
        List {
          ForEach(groups) { group in
            Section(group.title) {
              ForEach(group.entries) { entry in
                // Identified by its anchor already (`Reference.id`), which is
                // what the reveal scrolls to.
                ReferenceRow(entry: entry, open: open, openInNewWindow: openInNewWindow)
                  .listRowBackground(
                    highlighted == entry.anchor
                      ? RoundedRectangle(cornerRadius: 6).fill(.tint.opacity(0.2)) : nil)
              }
            }
          }
        }
        .listStyle(.sidebar)
        // A sidebar list is announced as "Sidebar", which is the window's own (#300).
        .accessibilityLabel("References")
        // Initial as well: a citation usually switches the panel to this tab, and
        // the list is new when the request arrives.
        .task(id: revealed) {
          guard let revealed else { return }
          // A turn later, once the list has rows to scroll to; see the contents
          // tab, which waits for the same reason.
          await Task.yield()
          withAnimation { proxy.scrollTo(revealed.anchor, anchor: .center) }
          highlighted = revealed.anchor
          try? await Task.sleep(for: .seconds(1.5))
          guard !Task.isCancelled else { return }
          withAnimation(.easeOut(duration: 0.6)) { highlighted = nil }
        }
      }
    }
  }
}

/// One entry, as a row rather than the four stacked indented paragraphs the body
/// used to render: what it is, then who wrote it and when.
struct ReferenceRow: View {
  let entry: Reference
  let open: (DocumentID) -> Void
  /// Nil where a reference cannot open in a window of its own.
  let openInNewWindow: ((DocumentID) -> Void)?

  var body: some View {
    VStack(alignment: .leading, spacing: 3) {
      // A button, not a tap gesture: a gesture is no control, so VoiceOver did
      // not announce the row as one and Full Keyboard Access could not press it
      // (#156). An entry that names no RFC opens nothing and stays plain text.
      if let id = entry.documentID {
        Button {
          open(id)
        } label: {
          entryDescription.contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        #if !os(macOS)
          .contextMenu {
            if let openInNewWindow {
              Button {
                openInNewWindow(id)
              } label: {
                Label("Open in New Window", systemImage: "macwindow.badge.plus")
              }
            }
          }
        #endif
      } else {
        entryDescription
        // An entry that names no RFC opens nothing in the reader, so where it
        // lives is the one way on from it — and what a citation of it reveals the
        // row for.
        if let url = entry.url {
          Link(destination: url) {
            Text(url.absoluteString).lineLimit(1).truncationMode(.middle)
          }
          .font(.caption)
        }
      }
      // What the author added after the entry, most often the commit a living
      // standard was cited at; its link opens in the browser like any other.
      // Outside the button, which would otherwise take the link's click.
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
          // Decoration: inside the button it would otherwise open the button's
          // spoken name with the symbol's own.
          Image(systemName: "doc.text").foregroundStyle(.tint).imageScale(.small)
            .accessibilityHidden(true)
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
        let byline = entry.authors.map(\.displayName).joined(separator: ", ")
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
    // One stop, whether or not the entry names an RFC: its tag, title and byline
    // were three for an entry that is no button (#300).
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(entry.accessibilityLabel)
  }
}
