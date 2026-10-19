import RFCKit
import RFCReaderKit
import SwiftUI

/// Named by its raw value in a tab's `SceneSnapshot`, so a case keeps its name.
enum InspectorTab: String, CaseIterable {
  case contents
  case references
  /// Every BCP 14 requirement the document states (#180).
  case requirements
  /// The reader's highlights in the document (#522).
  case annotations

  /// Named once, for both platforms' tab bars (#258).
  var title: String {
    switch self {
    case .contents: String(localized: "Contents")
    case .references: String(localized: "References")
    case .requirements: String(localized: "Requirements")
    case .annotations: String(localized: "Annotations")
    }
  }

  /// What the tab says when it has nothing to list.
  var emptyTitle: String {
    switch self {
    case .contents: String(localized: "No Contents")
    case .references: String(localized: "No References")
    case .requirements: String(localized: "No Requirements")
    case .annotations: String(localized: "No Annotations")
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
  /// Where the build on screen placed each highlight (#522).
  let highlightStatuses: [UUID: HighlightPlacement.Status]?
  let info: DocumentInfo?
  /// Whether the body is here. Without it, a document the index describes still has
  /// its Info, and the navigation pane's lists say why they are empty (#325).
  let hasBody: Bool
  /// Whether the body is on its way, so the lists show progress rather than say it
  /// has not loaded.
  let isLoading: Bool
  /// Why the RFC is read as its original, if it is (#207), which the lists say in
  /// their place.
  let publishedOriginal: PublishedOriginalPage.Status?
  /// For the Info pane's offline copy, which is the store's rather than derived.
  let document: DocumentID?
  let library: LibraryModel
  /// The window's tab, beside which a reference opens in a new one (#761).
  @Environment(NavigationModel.self) private var scene
  let pane: InspectorPane
  /// Whether the panel is a sheet of its own, in a `NavigationStack` whose bar the
  /// tabs take as its title (#301), rather than a column beside the reader. Never
  /// on macOS, where the panel is a split item.
  let isSheet: Bool
  @Binding var tab: InspectorTab
  let current: String?
  /// The bibliography entry a citation asked to see, if any.
  let revealed: ReaderState.RevealedReference?
  let selectSection: (String) -> Void
  let openDocument: (DocumentID) -> Void
  /// Searches the library, for a keyword chosen in the Info pane.
  let search: (String) -> Void
  /// Shows the document's reading path (#189), from the Info pane.
  let showReadingPath: (DocumentID) -> Void

  var body: some View {
    switch pane {
    case .navigation: navigation
    case .info:
      let infoView = InfoView(
        info: info, document: document, library: library, open: openDocument, search: search,
        showReadingPath: showReadingPath, sections: sections, selectSection: selectSection)
      #if os(macOS)
        infoView
      #else
        if isSheet {
          // No tabs to title the sheet with, and an empty bar would only push the
          // pane down. Only in the sheet: beside the reader, `.inspector` lifts the
          // column's toolbar into the reader's bar (#247), so a visibility set there
          // could reach the reader's bar too (not measured on an iPad).
          infoView.toolbarVisibility(.hidden, for: .navigationBar)
        } else {
          infoView
        }
      #endif
    }
  }

  @ViewBuilder
  private var navigation: some View {
    #if os(macOS)
      VStack(spacing: 0) {
        InspectorTabBar(tab: $tab)
          .padding(.horizontal, 10)
          .padding(.vertical, 8)
        selectedTab
      }
    #else
      if isSheet {
        // The tabs as the sheet's title, under its grabber, as a sheet of the
        // system's own has its title (#301): the bar gives them the system's top
        // margin, where 20 pt of inset of our own still read as cramped.
        selectedTab
          .navigationBarTitleDisplayMode(.inline)
          .toolbar {
            ToolbarItem(placement: .principal) { tabPicker }
          }
      } else {
        // Not in a toolbar beside the reader: `.inspector` lifts its content's
        // toolbar items into the reader's own bar, even through a `NavigationStack`
        // of the panel's own, so the tabs ended up above the reader, apart from the
        // panel they switch and in the place of the reader's title. The insets
        // are those the sheet had before the tabs went into its bar (#247).
        VStack(spacing: 0) {
          tabPicker
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 8)
          selectedTab
        }
      }
    #endif
  }

  #if !os(macOS)
    /// The system's segmented control, in the panel it switches (#247).
    private var tabPicker: some View {
      Picker("Panel", selection: $tab) {
        ForEach(InspectorTab.allCases, id: \.self) { tab in
          Text(tab.title).tag(tab)
        }
      }
      .pickerStyle(.segmented)
      .labelsHidden()
    }
  #endif

  @ViewBuilder
  private var selectedTab: some View {
    let content = InspectorPane.navigationContent(
      hasBody: hasBody, isLoading: isLoading, readsAsOriginal: publishedOriginal != nil)
    // The highlights are the reader's, not the document's: listed by their quotes
    // whether or not the document is here to place them in.
    if tab == .annotations, content != .loading {
      annotations()
    } else {
      selectedTab(content)
    }
  }

  /// Placed where the reader's text has placed them; otherwise their stored quotes,
  /// and why they are not placed: the document is not here, or what is shown is not
  /// its own text but the original or a translation.
  private func annotations() -> some View {
    let highlights = document.map { library.annotations.highlights(of: $0) } ?? []
    let note: String? =
      highlightStatuses != nil
      ? nil
      : hasBody && publishedOriginal == nil
        ? String(localized: "Highlights are shown in the document's own text.")
        : String(localized: "The document is unavailable, so its highlights cannot be shown in it.")
    return AnnotationsView(
      highlights: highlights, statuses: highlightStatuses, note: note, sections: sections,
      library: library, select: selectSection)
  }

  @ViewBuilder
  private func selectedTab(_ content: InspectorPane.NavigationContent) -> some View {
    switch content {
    case .lists:
      loadedTab
    case .loading:
      // As the requirements tab shows its own extraction.
      ProgressView()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    case .notLoaded:
      // An empty list beside a failure reads as a second failure; this says why.
      ContentUnavailableView(
        tab.emptyTitle, systemImage: "doc.text.magnifyingglass",
        description: Text(
          verbatim: document.map { String(localized: "\($0.displayName) hasn't loaded.") }
            ?? String(localized: "The document hasn't loaded.")))
    case .publishedOriginal:
      ContentUnavailableView(
        tab.emptyTitle, systemImage: "doc.richtext",
        description: Text(verbatim: publishedOriginal?.panelExplanation() ?? ""))
    }
  }

  @ViewBuilder
  private var loadedTab: some View {
    switch tab {
    case .contents:
      // Opened at the section being read rather than at the top: from §15 of a long
      // RFC, the top of the list is a long way from where the reader is.
      ScrollViewReader { proxy in
        TableOfContentsView(sections: sections, current: current, select: selectSection)
          // A filter typed for one document is not carried to the next, which the
          // panel stays open for (#325).
          .id(document)
          // Again when a place first arrives, not on every crossing: a panel left
          // open from the previous document shows this list before the new one
          // has reported where it is (#325).
          .task(id: current != nil) {
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
        groups: groups, revealed: revealed, open: openDocument, menu: referenceMenu)
    case .requirements:
      RequirementsView(requirements: requirements, document: document, select: selectSection)
    case .annotations:
      annotations()
    }
  }

  /// What a reference's row offers beyond a click (#761): a tab and a window of its
  /// own on the Mac, a window on an iPad (#158), and its link and citation.
  private var referenceMenu: ReferenceMenu {
    #if os(macOS)
      ReferenceMenu(
        library: library,
        openInNewTab: { [library, scene] in
          library.openTab(RFCLink(id: $0), beside: scene)
        },
        openInNewWindow: { [library] in library.open(RFCLink(id: $0), placement: .newWindow) })
    #else
      ReferenceMenu(
        library: library, openInNewTab: nil,
        openInNewWindow: library.opensNewWindows
          ? { [library] in library.openWindow(for: $0) } : nil)
    #endif
  }
}

/// `DocumentInspector` wired to the window's `ReaderState`, and the one place that
/// wiring is written.
///
/// macOS hosts this in the window's own split item; iOS presents it with
/// `.inspector` beside the reader, or in a sheet of its own in compact width; the
/// six inputs are the same either way, so the next one added to `DocumentInspector`
/// is added once.
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
    /// A reading path asked for while the panel is a sheet, which the reader
    /// presents once the panel's sheet is gone: UIKit presents nothing while a
    /// dismissal is under way, and a request it refused would stay set.
    @Binding var readingPathAfterClosing: ReadingPathRequest?
  #endif

  /// Whether the panel is a sheet, whose bar of its own the tabs take as its title
  /// (#301): the one panel that closes after a choice.
  private var isSheet: Bool {
    #if os(macOS)
      false
    #else
      closesAfterChoice
    #endif
  }

  var body: some View {
    // The stack is made here, beside the flag that puts the tabs in its bar, so
    // that neither is without the other.
    if isSheet {
      NavigationStack { panel }
    } else {
      panel
    }
  }

  @ViewBuilder
  private var panel: some View {
    @Bindable var reader = reader
    // On what the index describes, not only the body: a document still loading, or
    // one that failed to or was offline, has its Info (#325).
    if reader.canDescribe {
      DocumentInspector(
        sections: reader.sections,
        // In Focus, what the focused section cites, pinned beside it (#699); the whole
        // bibliography for an entry asked for that the section does not cite.
        groups: FocusCitations.shown(
          reader.focusGroups, revealing: reader.revealedReference?.anchor) ?? reader.groups,
        requirements: reader.requirements,
        highlightStatuses: reader.highlightStatuses,
        info: reader.info,
        hasBody: reader.hasDocument,
        isLoading: reader.isLoading,
        publishedOriginal: reader.publishedOriginal,
        document: navigation.shown,
        library: library,
        pane: reader.pane,
        isSheet: isSheet,
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
          leave {
            library.open(id, activation: .current, in: navigation, arrival: .citation)
          }
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
        },
        showReadingPath: { id in
          let request = ReadingPathRequest(root: id)
          #if !os(macOS)
            if closesAfterChoice {
              readingPathAfterClosing = request
              isPresented = false
              return
            }
          #endif
          navigation.readingPath = request
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

#if os(macOS)
  /// The navigation pane's tabs, drawn the way an inspector's are rather than as a segmented
  /// control.
  ///
  /// `.pickerStyle(.segmented)` draws a bordered control sized to its labels, which
  /// reads as a form field sitting on the panel rather than as the panel's own
  /// navigation. Pages, Numbers and Keynote all use this shape instead: the full width
  /// of the inspector, no enclosing border, the selected tab a filled pill, and a hair
  /// divider only between two unselected labels.
  ///
  /// macOS only, and compiled for macOS only (#258): on iOS the system's own
  /// segmented control is the tabs, in the sheet's bar or the inspector column's
  /// content (#247, #301).
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
      // Three buttons to look at, one control with three choices to VoiceOver, as
      // a segmented control is (#760).
      .accessibilityRepresentation {
        Picker("Tab", selection: $tab) {
          ForEach(InspectorTab.allCases, id: \.self) { tab in
            Text(verbatim: tab.title).tag(tab)
          }
        }
        .pickerStyle(.segmented)
      }
    }

    /// The accent, darkened in each appearance until the white label on it clears the
    /// minimum contrast: macOS 27's blue carries white at 3.52:1, yellow at 1.51:1
    /// (#317). Resolved when drawn, so it follows the accent the user picks.
    private static let selectedFill = Color(
      nsColor: NSColor(name: nil) { appearance in
        var accent = SRGBColor(hex: 0x00_7AFF)
        appearance.performAsCurrentDrawingAppearance {
          if let resolved = SRGBColor(resolving: .controlAccentColor) { accent = resolved }
        }
        return NSColor(AccentContrast.selectedTabFill(accent: accent))
      })

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
              Capsule().fill(Self.selectedFill)
            }
          }
          .contentShape(.rect)
      }
      .buttonStyle(.plain)
    }
  }
#endif

struct ReferencesView: View {
  let groups: [ReferenceGroup]
  let revealed: ReaderState.RevealedReference?
  let open: (DocumentID) -> Void
  let menu: ReferenceMenu

  /// The revealed entry, marked for a moment so the eye finds it in the list. The
  /// reveal rather than its anchor, so revealing the same entry again marks it anew.
  @State private var highlighted: ReaderState.RevealedReference?
  #if canImport(UIKit)
    /// The window, which a row's long-press preview is measured against.
    @State private var window = WindowSizeReader()
  #endif

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
                ReferenceRow(
                  entry: entry, open: open, menu: menu, previewSize: previewSize
                )
                .listRowBackground(
                  highlighted?.anchor == entry.anchor
                    ? RoundedRectangle(cornerRadius: 6).fill(.tint.opacity(0.2)) : nil)
              }
            }
          }
        }
        .listStyle(.sidebar)
        #if canImport(UIKit)
          .reading(window)
        #endif
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
          highlighted = revealed
        }
        .resets($highlighted, to: nil, after: .seconds(1.5), animation: .easeOut(duration: 0.6))
      }
    }
  }

  /// A row's document preview, at the press: a context menu's on iOS, fitted to the
  /// window as the reader's are, and the popover's full size on the Mac.
  private func previewSize() -> CGSize {
    #if canImport(UIKit)
      window.size.map(LinkPreview.documentSize(fitting:)) ?? LinkPreview.documentSize
    #else
      LinkPreview.documentSize
    #endif
  }
}

/// A References panel row's preview of its RFC (#580). A view of its own, so that what
/// it resolves and the size it asks for are worked out when the preview shows, at the
/// press: iOS's context menu builds its preview's view with the row, before the row
/// is in a window to be measured against.
private struct ReferenceRowPreview: View {
  let entry: Reference
  let library: LibraryModel
  let size: () -> CGSize
  let commit: () -> Void

  var body: some View {
    if case .document(let id, let place)? = LinkPreview.resolve(entry, in: library.index) {
      DocumentPreview(library: library, id: id, place: place, size: size(), commit: commit)
    }
  }
}

/// One entry, as a row rather than the four stacked indented paragraphs the body
/// used to render: what it is, then who wrote it and when.
struct ReferenceRow: View {
  let entry: Reference
  let open: (DocumentID) -> Void
  /// What the row offers on a right click or a long press, and the preview of its
  /// RFC on a long press or a force click; nil for neither.
  let menu: ReferenceMenu?
  /// The size of that preview of the RFC, asked at the press.
  var previewSize: () -> CGSize = { LinkPreview.documentSize }

  #if os(macOS)
    /// Whether the click under way pressed through to the preview, so its release
    /// does not open the RFC as well (`ForceClickReader`).
    @State private var isForceClick = false
    @State private var isPreviewing = false
  #endif

  var body: some View {
    VStack(alignment: .leading, spacing: 3) {
      // A button, not a tap gesture: a gesture is no control, so VoiceOver did
      // not announce the row as one and Full Keyboard Access could not press it
      // (#156). An entry that names no RFC opens nothing and stays plain text.
      if let id = entry.documentID {
        let button = Button {
          #if os(macOS)
            // The release of the click that pressed through to the preview.
            if isForceClick {
              isForceClick = false
              return
            }
          #endif
          open(id)
        } label: {
          entryDescription.contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        if let menu {
          #if os(macOS)
            button
              .contextMenu { menu.items(for: id) }
              .background(
                ForceClickReader {
                  isForceClick = true
                  isPreviewing = true
                }
              )
              .popover(isPresented: $isPreviewing, arrowEdge: .leading) {
                // A click in it opens what the row does, as the prose's opens what
                // its reference does.
                documentPreview(library: menu.library) {
                  isPreviewing = false
                  open(id)
                }
              }
              // Whatever ended the preview, the next press of the button is its own.
              .onChange(of: isPreviewing) {
                if !isPreviewing { isForceClick = false }
              }
          #else
            // UIKit's tap on a SwiftUI menu's preview closes it and commits nothing:
            // the row's own tap opens the RFC.
            button.contextMenu {
              menu.items(for: id)
            } preview: {
              // Opaque, as the reader's own previews are: the preview has no
              // background of its own, the Mac's popover supplying one.
              documentPreview(library: menu.library) {}
                .background(Color(uiColor: .systemBackground))
            }
          #endif
        } else {
          button
        }
      } else {
        // Not a button, so the combined element needs a role of its own, or macOS
        // exposes it as AXUnknown (#300).
        entryDescription.accessibilityAddTraits(.isStaticText)
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

  /// What a citation of the entry previews in the prose (#580): the RFC it names.
  private func documentPreview(library: LibraryModel, commit: @escaping () -> Void)
    -> some View
  {
    ReferenceRowPreview(entry: entry, library: library, size: previewSize, commit: commit)
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

/// A References panel row's menu (#761): `DocumentMenus.referenceActions`, one list
/// for the Mac and iOS. Opening in a tab or a window is the platform's, and nil
/// where it cannot.
struct ReferenceMenu {
  let library: LibraryModel
  let openInNewTab: ((DocumentID) -> Void)?
  let openInNewWindow: ((DocumentID) -> Void)?

  @ViewBuilder
  func items(for id: DocumentID) -> some View {
    let sections = DocumentMenus.referenceActions(
      opensTabs: openInNewTab != nil, opensWindows: openInNewWindow != nil,
      describes: library.metadata(id) != nil)
    DividedSections(sections: sections) { item($0, for: id) }
  }

  @ViewBuilder
  private func item(_ action: DocumentMenus.ReferenceAction, for id: DocumentID) -> some View {
    switch action {
    case .openInNewTab:
      Button {
        openInNewTab?(id)
      } label: {
        Label("Open in New Tab", systemImage: "plus.square.on.square")
      }
      .labelStyle(.titleAndIcon)
    case .openInNewWindow:
      Button {
        openInNewWindow?(id)
      } label: {
        Label("Open in New Window", systemImage: "macwindow.badge.plus")
      }
      .labelStyle(.titleAndIcon)
    case .copyLink:
      Button {
        perform(.copySectionLink, for: id)
      } label: {
        Label("Copy Link", systemImage: "link")
      }
      .labelStyle(.titleAndIcon)
    case .cite:
      // The styles alone: the link to the reader's section is the reader's own.
      Menu("Cite") {
        MenuSections(sections: Array(DocumentMenus.cite().prefix(1))) { perform($0, for: id) }
      }
    }
  }

  /// A copy, of the referenced document as a whole: no section of it is being read.
  private func perform(_ action: DocumentMenus.Action, for id: DocumentID) {
    guard
      case .copy(let text, let feedback) = action.effect(
        for: id, metadata: library.metadata(id), section: nil)
    else { return }
    Clipboard.copy(text, announcing: feedback)
  }
}
