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
    @Environment(\.openURL) private var openURL
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

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

          TextSizeButton()
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
        ReadingModePicker(reader: reader)
        FocusSteps(reader: reader)
        if SideBySide.isOffered(in: horizontalSizeClass) {
          CompareItems(id: id, library: library, reader: reader)
        }
        Divider()
        Menu("Export", systemImage: "square.and.arrow.down") {
          ForEach(reader.exportFormats) { format in
            Button(format.name()) { exportDocument(format) }
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
    /// `CollectionActionPerformer`'s.
    private func perform(_ action: DocumentMenus.Action) {
      DocumentActionPerformer(
        id: id, metadata: metadata, reader: reader, open: { openURL($0) }
      ).perform(action)
    }

    private func shareLink(_ metadata: RFCMetadata) -> some View {
      ShareLink(
        item: RFCEditorEndpoints.infoPage(id),
        subject: Text(verbatim: "\(id.displayName): \(metadata.title)"))
    }

    private func toggleBookmark() {
      library.toggleBookmark(id, documentTitle: reader.documentTitle)
    }
  }

  /// The reader's own text size on iOS, which has no Settings scene to put the
  /// slider in (#153), and how diagrams are shown: "Aa" opens a menu, as Safari's
  /// page menu does. Its first row is a small "A", the size as a percentage of the
  /// system's, and a large "A", and stays open while the size is stepped; below it
  /// are Use System Size and Draw diagrams. The platform's own menu rather than a
  /// popover: a compact control group is the small-element row of a `UIMenu`. The
  /// keyboard's ⌘+, ⌘− and ⌘0 are `DocumentCommands`'.
  private struct TextSizeButton: View {
    @AppStorage(ReaderPreferences.fontSizeKey) private var fontSize = ReaderPreferences
      .defaultFontSize
    @AppStorage(ReaderPreferences.drawDiagramsKey) private var drawDiagrams =
      ReaderPreferences.defaultDrawDiagrams

    var body: some View {
      Menu {
        ControlGroup {
          Button {
            fontSize = ReaderPreferences.fontSize(steppingDown: fontSize)
          } label: {
            Label("Smaller", systemImage: "textformat.size.smaller")
          }
          .disabled(ReaderPreferences.fontSize(steppingDown: fontSize) == fontSize)

          // The size the steps reached, between them. A tap on it goes back to the
          // system's size, as one on Safari's does.
          Button(ReaderPreferences.percentage(of: fontSize)) {
            fontSize = ReaderPreferences.defaultFontSize
          }
          .accessibilityLabel("Text Size")
          .accessibilityValue(ReaderPreferences.percentage(of: fontSize))
          // Its label says what it shows; what a tap does, which loses the size, is
          // said here, or VoiceOver would announce a reset as a reading of the size.
          .accessibilityHint("Goes back to the system's size")

          Button {
            fontSize = ReaderPreferences.fontSize(steppingUp: fontSize)
          } label: {
            Label("Bigger", systemImage: "textformat.size.larger")
          }
          .disabled(ReaderPreferences.fontSize(steppingUp: fontSize) == fontSize)
        }
        .controlGroupStyle(.compactMenu)
        // Open while the size is stepped, so the text behind it can be watched.
        .menuActionDismissBehavior(.disabled)

        Button("Use System Size", systemImage: "arrow.counterclockwise") {
          fontSize = ReaderPreferences.defaultFontSize
        }
        .disabled(fontSize == ReaderPreferences.defaultFontSize)

        Toggle("Draw Diagrams", systemImage: "square.grid.3x3", isOn: $drawDiagrams)
      } label: {
        Label("Text Size", systemImage: "textformat.size")
      }
    }
  }
#endif
