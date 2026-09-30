import RFCKit
import RFCReaderKit
import SwiftUI

#if !os(macOS)
  /// The reader's toolbar on iOS, out of `DocumentView` (#135). On macOS the
  /// toolbar is the window's (`ReaderToolbar`).
  struct DocumentToolbar: ToolbarContent {
    let id: DocumentID
    let metadata: RFCMetadata?
    let library: LibraryModel
    let navigation: NavigationModel
    let reader: ReaderState
    let isBookmarked: Bool
    /// The system's, handed over by the reader: inside it, `openURL` is the reader's
    /// own, which follows links in the app.
    let openURL: OpenURLAction
    @Binding var showsInspector: Bool
    /// Save to Files and the print sheet, which are the reader's: their state and
    /// the `.fileExporter` are view state, and `ToolbarContent` has none (#375, #376).
    let exportDocument: (ExportFormat) -> Void
    let printDocument: () -> Void

    @Environment(\.undoManager) private var undoManager

    /// Share and More at the top; Contents and Cite leading the bottom bar, and
    /// Bookmark trailing it as the view's primary action, the way Notes puts
    /// Compose there (#342).
    ///
    /// The inline title has the lowest priority in the top bar, which is why only
    /// two actions stay up there: five beside the back button left an iPhone's bar
    /// no room for it, and it collapsed to "…" (#245).
    var body: some ToolbarContent {
      if let metadata {
        ToolbarItem(placement: .primaryAction) {
          shareLink(metadata)
        }
      }

      ToolbarItem(placement: .primaryAction) {
        moreMenu
      }

      ToolbarItemGroup(placement: .bottomBar) {
        Button {
          press(.navigation)
        } label: {
          Label("Contents", systemImage: "list.bullet.rectangle.portrait")
        }
        // The same chord as the Mac's (#157).
        .keyboardShortcut("i", modifiers: [.command, .option])

        Button {
          press(.info)
        } label: {
          Label("Info", systemImage: "info.circle")
        }
        .keyboardShortcut("i", modifiers: .command)

        citeMenu
      }

      ToolbarSpacer(.flexible, placement: .bottomBar)

      ToolbarItem(placement: .bottomBar) {
        bookmarkButton
      }
    }

    private var bookmarkButton: some View {
      // A tap bookmarks, as before; a long press adds to a collection (#349).
      Menu {
        AddToCollectionItems(
          document: id, library: library, navigation: navigation, undoManager: undoManager)
      } label: {
        Label("Bookmark", systemImage: isBookmarked ? "bookmark.fill" : "bookmark")
      } primaryAction: {
        toggleBookmark()
      }
      // A fixed label, and the state as its value, which the glyph alone never told
      // VoiceOver (#278).
      .accessibilityValue(DocumentActions.bookmarkState(isBookmarked: isBookmarked))
      .keyboardShortcut("d", modifiers: .command)
    }

    private var citeMenu: some View {
      Menu {
        MenuSections(sections: DocumentMenus.cite(), perform: perform)
      } label: {
        Label("Cite", systemImage: "quote.opening")
      }
    }

    /// A pane's button: opens the inspector on that pane, swaps an open one to it,
    /// or closes the one showing it, as on the Mac (`InspectorPane.pressing`).
    private func press(_ pane: InspectorPane) {
      let result = InspectorPane.pressing(
        pane, isOpen: showsInspector, showing: reader.pane)
      reader.pane = result.pane
      withAnimation(.snappy) { showsInspector = result.isOpen }
    }

    /// What is used least: the original text, the document's pages elsewhere, and
    /// Export and Print, which are iOS's own: the formats listed, and the print sheet.
    private var moreMenu: some View {
      Menu {
        MenuSections(
          sections: DocumentMenus.more(
            showsOriginal: reader.showOriginal, errata: metadata?.errataURL,
            precedingDraft: reader.precedingDraft),
          perform: perform)
        Divider()
        Menu("Export", systemImage: "square.and.arrow.down") {
          ForEach(ExportFormat.allCases) { format in
            Button(format.name) { exportDocument(format) }
          }
        }
        Button("Print…", systemImage: "printer") { printDocument() }
      } label: {
        Label("More", systemImage: "ellipsis")
      }
    }

    /// What an item of Cite or More does. Add to Collection's are
    /// `AddToCollectionItems`' own.
    private func perform(_ action: DocumentMenus.Action) {
      switch action {
      case .copyCitation(let style): copyCitation(style)
      case .copySectionLink:
        Clipboard.copy(DocumentActions.sectionLink(id: id, section: reader.currentSection))
      case .toggleOriginalText: reader.showOriginal.toggle()
      case .openInfoPage: openURL(RFCEditorEndpoints.infoPage(id))
      case .openErrata(let url), .openPrecedingDraft(let url): openURL(url)
      case .openDatatracker: openURL(RFCEditorEndpoints.datatracker(id))
      case .toggleCollection, .newCollection: break
      }
    }

    private func shareLink(_ metadata: RFCMetadata) -> some View {
      ShareLink(
        item: RFCEditorEndpoints.infoPage(id),
        subject: Text("\(id.displayName): \(metadata.title)"))
    }

    private func toggleBookmark() {
      library.toggleBookmark(id, documentTitle: reader.documentTitle)
    }

    private func copyCitation(_ style: CitationStyle) {
      guard let metadata else { return }
      Clipboard.copy(
        DocumentActions.citation(metadata, section: reader.currentSection, style: style))
    }
  }
#endif
