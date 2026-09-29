import RFCKit
import RFCReaderKit
import SwiftData
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
    @Binding var showsInspector: Bool

    // Here rather than on the reader, and on iOS only: on macOS the bookmark
    // button and the external links are the window's, and a `@Query` in the
    // reader ran a live fetch of every bookmark per open document that nothing
    // read.
    @Environment(\.openURL) private var systemOpenURL
    @Environment(\.undoManager) private var undoManager
    @Environment(\.modelContext) private var modelContext
    @Query private var bookmarks: [Bookmark]

    private var isBookmarked: Bool {
      let key = id.fileStem
      return bookmarks.contains { $0.documentKey == key }
    }

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
      // Read once: a linear scan of the bookmarks, and the label wants it twice.
      let bookmarked = isBookmarked
      // A tap bookmarks, as before; a long press adds to a collection (#349).
      return Menu {
        AddToCollectionItems(
          document: id, library: library, navigation: navigation, undoManager: undoManager)
      } label: {
        Label(
          bookmarked ? "Remove Bookmark" : "Bookmark",
          systemImage: bookmarked ? "bookmark.fill" : "bookmark")
      } primaryAction: {
        toggleBookmark()
      }
      .keyboardShortcut("d", modifiers: .command)
    }

    private var citeMenu: some View {
      Menu {
        ForEach(CitationStyle.allCases) { style in
          Button(style.displayName) { copyCitation(style) }
        }
        Divider()
        Button("Copy Link to Current Section") {
          Clipboard.copy(DocumentActions.sectionLink(id: id, section: reader.currentSection))
        }
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

    /// What is used least: the original text, and the document's pages elsewhere.
    private var moreMenu: some View {
      Menu {
        Section {
          Toggle("Original Text", isOn: Bindable(reader).showOriginal)
        }

        Section {
          Button("Open on rfc-editor.org") { systemOpenURL(RFCEditorEndpoints.infoPage(id)) }
          if let url = metadata?.errataURL {
            Button("Errata") { systemOpenURL(url) }
          }
          Button("Datatracker") { systemOpenURL(RFCEditorEndpoints.datatracker(id)) }
          if let draft = reader.precedingDraft {
            Button("Preceding Draft") { systemOpenURL(draft) }
          }
        }
      } label: {
        Label("More", systemImage: "ellipsis")
      }
    }

    private func shareLink(_ metadata: RFCMetadata) -> some View {
      ShareLink(
        item: RFCEditorEndpoints.infoPage(id),
        subject: Text("\(id.displayName): \(metadata.title)"))
    }

    private func toggleBookmark() {
      let title = DocumentActions.bookmarkTitle(
        metadata: metadata, documentTitle: reader.documentTitle, id: id)
      BookmarkStore.toggle(id, title: title, in: modelContext)
    }

    private func copyCitation(_ style: CitationStyle) {
      guard let metadata else { return }
      Clipboard.copy(
        DocumentActions.citation(metadata, section: reader.currentSection, style: style))
    }
  }
#endif
