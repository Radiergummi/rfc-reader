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
    /// False while reading on has put the bars away (`ReaderChrome`). The bottom
    /// bar goes by losing its items, which dissolve in place, rather than by
    /// `.toolbarVisibility`, which slides it off the screen; the top bar cannot, as
    /// hiding its back button would also turn off swiping back.
    let showsBottomBar: Bool

    @Environment(\.undoManager) private var undoManager

    /// Share and More at the top; Contents and Info leading the bottom bar, and
    /// Bookmark trailing it as the view's primary action, the way Notes puts
    /// Compose there (#342). Cite is in More: on a phone it is rarely what the
    /// reader is after.
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

      if showsBottomBar {
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
        }

        ToolbarSpacer(.flexible, placement: .bottomBar)

        ToolbarItem(placement: .bottomBar) {
          bookmarkButton
        }
      }
    }

    private var bookmarkButton: some View {
      // A tap bookmarks, as before; a long press adds to a collection (#349). ⌘D is
      // not this button's but `DocumentCommands`', whose title says what it will do
      // (#278).
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
    }

    /// A pane's button: opens the inspector on that pane, swaps an open one to it,
    /// or closes the one showing it, as on the Mac (`InspectorPane.pressing`).
    private func press(_ pane: InspectorPane) {
      let result = InspectorPane.pressing(
        pane, isOpen: showsInspector, showing: reader.pane)
      reader.pane = result.pane
      withAnimation(.snappy) { showsInspector = result.isOpen }
    }

    /// What is used least: citing, the original text, the document's pages
    /// elsewhere, and Export and Print, which are iOS's own: the formats listed, and
    /// the print sheet.
    private var moreMenu: some View {
      Menu {
        Menu("Cite", systemImage: "quote.opening") {
          MenuSections(sections: DocumentMenus.cite(), perform: perform)
        }
        Divider()
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
        // Not for a document read as its PDF or PostScript original (#207).
        .disabled(!reader.offersPrintAndExport)
        Button("Print…", systemImage: "printer") { printDocument() }
          .disabled(!reader.offersPrintAndExport)
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
