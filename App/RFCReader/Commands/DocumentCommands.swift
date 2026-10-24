import RFCKit
import RFCReaderKit
import SwiftUI

#if os(macOS)
  import AppKit
#else
  import UIKit
#endif

/// Menu bar commands; also give every action a keyboard shortcut on iPad.
struct DocumentCommands: Commands {
  @AppStorage(ReaderPreferences.fontSizeKey) private var fontSize = ReaderPreferences
    .defaultFontSize

  #if os(macOS)
    /// The key window's navigation, so Back and Forward act on the tab the reader is
    /// actually looking at. `@FocusedValue` cannot answer that any more: the views
    /// that published it are hosted outside the scene, and measured on this build the
    /// values never resolve — ⌘L opened nothing.
    @State private var active = ActiveReaderWindow.shared

    private var navigation: NavigationModel? { active.controller?.navigation }
    private var reader: ReaderState? { active.controller?.reader }
    /// A document is on screen, not just selected: a selection is also showing while
    /// it loads and when it failed to, and `hasDocument` stays true after the
    /// selection is cleared.
    private var showsDocument: Bool {
      navigation?.selection != nil && reader?.hasDocument == true
    }
    /// A document on screen that Print and Export offer: not one read as its PDF or
    /// PostScript original (#207).
    private var offersPrintAndExport: Bool {
      navigation?.selection != nil && reader?.offersPrintAndExport == true
    }
    private var openDocument: (() -> Void)? {
      guard let navigation else { return nil }
      return { navigation.isShowingGoToSheet = true }
    }
    private var isBookmarked: Bool { active.controller?.isBookmarked == true }
    private func toggleBookmark() { active.controller?.toggleBookmark() }

    /// Whether Use Selection for Find and Jump to Selection have a selection to act
    /// on: the reader's, the one beside a compared document's, or the original
    /// text's, which reports none and is let through.
    private var hasFindableSelection: Bool {
      reader?.showOriginal == true || reader?.hasSelection == true
        || reader?.sideBySide?.reader.hasSelection == true
    }

    /// Whether Copy as Quote and Highlight have a selection of the RFC's own words: in
    /// the reader's text or beside a compared document's, never the original text's
    /// or a translation's.
    private var hasQuotableSelection: Bool {
      showsDocument && reader?.showOriginal != true && reader?.readsTranslation != true
        && (reader?.hasSelection == true || reader?.sideBySide?.reader.hasSelection == true)
    }

    /// View ▸ Show or Hide Contents and Info: what the item will do (#761).
    private func paneTitle(_ pane: InspectorPane) -> String {
      InspectorPane.menuTitle(
        pane, isOpen: active.isPanelOpen, showing: active.controller?.reader.pane ?? .navigation)
    }

    /// What an item of the Document menu does, as the toolbar's Cite and More do it.
    private func perform(_ action: DocumentMenus.Action) {
      active.controller?.perform(action)
    }

    private var citedDocument: CitedDocument? { active.controller?.citedDocument }

    private func copyCitation() { active.controller?.copyCitation() }

    /// Whether Copy As has a selection to copy: the reader's, or the one beside a
    /// compared document's.
    private var hasSelection: Bool {
      reader?.hasSelection == true || reader?.sideBySide?.reader.hasSelection == true
    }
  #else
    let library: LibraryModel
    @FocusedValue(\.openDocumentAction) private var openDocument
    /// The focused scene's navigation, so Back and Forward act on the tab the reader
    /// is actually looking at rather than on whichever one registered last.
    @FocusedValue(\.navigationModel) private var navigation
    /// The focused scene's reader, for the title a new bookmark is filed under.
    @FocusedValue(\.readerState) private var reader

    private var isBookmarked: Bool {
      navigation?.selection.map { library.bookmarkedDocuments.contains($0) } ?? false
    }

    private func toggleBookmark() {
      guard let id = navigation?.selection else { return }
      library.toggleBookmark(id, documentTitle: reader?.documentTitle)
    }

    /// The document the tab opened, cited as itself, a series too (#656).
    private var citedDocument: CitedDocument? {
      navigation?.selection.flatMap(library.citedDocument)
    }

    /// Edit ▸ Copy Citation (#712): of the section the selection starts in, where the
    /// reader's text has the focus and a selection, as on the Mac, and otherwise of
    /// the section being read.
    private func copyCitation() {
      let request = CopyCitationRequest()
      _ = UIApplication.shared.sendAction(
        #selector(ReaderTextView.copyCitation(_:)), to: nil, from: request, for: nil)
      guard !request.handled, let shown = navigation?.shown, let reader else { return }
      DocumentActionPerformer(id: shown, cited: citedDocument, reader: reader, open: { _ in })
        .perform(.copyPreferredCitation)
    }
  #endif

  var body: some Commands {
    CommandGroup(after: .newItem) {
      Button("Go to RFC…") { openDocument?() }
        .keyboardShortcut(ReaderShortcut.goToRFC.keyboardShortcut)
        .disabled(openDocument == nil)
      #if os(macOS)
        Button("New Collection…") { active.controller?.newCollection() }
          .keyboardShortcut(ReaderShortcut.newCollection.keyboardShortcut)
          .disabled(navigation == nil)
        // The search on show, kept as a collection made from a query (#355).
        Button("Save as Collection…") { active.controller?.saveAsCollection() }
          .disabled(navigation?.savedQuery == nil)
      #endif
    }
    // The Mac's toolbar buttons are AppKit's, so their keyboard shortcuts have to be
    // menu items: an `NSToolbarItem` carries no key equivalent of its own. ⌘D is one
    // on the iPad too, rather than the toolbar button's, so its title in the menu bar
    // and the hold-⌘ overlay can follow the action as the Mac's does (#278).
    CommandGroup(after: .pasteboard) {
      #if os(macOS)
        // Every format, whichever Copy copies (#712). Handed to the reader's text view
        // (#186); see `ReaderWindowController.copyAsQuote()`. Grayed out without a
        // selection, as Copy is; the original text is not the reader's, and has no
        // quote to copy, and a translation's words are not the RFC's (#749).
        Menu("Copy As") {
          Button(CopyFormat.text.title()) {
            active.controller?.copyAsText()
          }
          .disabled(!showsDocument || reader?.showOriginal == true || !hasSelection)
          Button(CopyFormat.quote.title()) {
            active.controller?.copyAsQuote()
          }
          .keyboardShortcut(ReaderShortcut.copyAsQuote.keyboardShortcut)
          .disabled(!hasQuotableSelection)
        }
        // The selection, in the color last used (#522): Books' shortcut, and grayed out
        // where Copy as Quote is, for the same reasons.
        Button("Highlight") {
          active.controller?.highlightSelection()
        }
        .keyboardShortcut(ReaderShortcut.highlight.keyboardShortcut)
        .disabled(!hasQuotableSelection)
      #endif
      // ⇧⌘C (#712): of the selection's section, or else the one being read, in the
      // style Settings chose. A citation is made from the index's entry.
      Button("Copy Citation") { copyCitation() }
        .keyboardShortcut(ReaderShortcut.copyCitation.keyboardShortcut)
        .disabled(citedDocument == nil || navigation?.shown == nil)
      Section {
        // Says what it will do, as the toolbar's glyph does: both read the
        // library's set of bookmarked documents, which the menu observes.
        Button(DocumentActions.bookmarkCommand(isBookmarked: isBookmarked)) {
          toggleBookmark()
        }
        .keyboardShortcut(ReaderShortcut.bookmark.keyboardShortcut)
        .disabled(navigation?.selection == nil)
        #if os(macOS)
          // The key window's undo manager, so Edit > Undo puts back a document
          // removed from here, as it does for a removal in the list (#349).
          if let controller = active.controller, let document = controller.navigation.shown {
            Menu("Add to Collection") {
              AddToCollectionItems(
                document: document, library: controller.library,
                navigation: controller.navigation,
                undoManager: controller.window?.undoManager)
            }
          }
        #endif
      }
    }
    #if os(macOS)
      // File > Export… (#376), where a Mac app keeps it: after Save, before Print.
      CommandGroup(replacing: .importExport) {
        Button("Export…") { active.controller?.output.exportDocument() }
          .keyboardShortcut(ReaderShortcut.export.keyboardShortcut)
          .disabled(!offersPrintAndExport)
        // Chosen here, not in the save panel, which cannot rename the file (#386).
        Button("Export Current Section…") {
          active.controller?.output.exportCurrentSection()
        }
        .disabled(!offersPrintAndExport || reader?.exportableSection == nil)
        // The document as an EPUB, opened with Books, which imports it (#408).
        Button("Send to Books") { active.controller?.output.sendToBooks() }
          .disabled(!offersPrintAndExport)
        // The toolbar's Share, for a hidden toolbar or a reader who looks here (#761).
        Button("Share…") { active.controller?.share() }
          .disabled(!showsDocument)
      }
      // The document's own actions, the toolbar's Cite and More menus rendered from
      // the same sections, so the two cannot drift (#761): with the toolbar hidden or
      // in full screen they were nowhere else. One menu, as the toolbar keeps them
      // together, rather than spread over Edit, View and a Go menu.
      CommandMenu("Document") {
        Group {
          Menu("Cite") {
            // ⇧⌘C is Edit ▸ Copy Citation's, in the style Settings chose (#712).
            MenuSections(sections: DocumentMenus.cite(), perform: perform)
          }
          // A citation is made from the index's entry, as the References menu's is.
          .disabled(citedDocument == nil)
          Divider()
          // Disabled rather than gone with no reader window, as the other menus'
          // items are: an empty menu in the bar says nothing.
          MenuSections(
            sections: DocumentMenus.more(
              showsOriginal: reader?.showOriginal == true,
              showsTranslation: reader?.showTranslation == true,
              errata: navigation?.shown.flatMap { active.controller?.library.metadata($0) }?
                .errataURL,
              precedingDraft: reader?.precedingDraft),
            perform: perform)
        }
        .disabled(!showsDocument)
      }
      // File > Page Setup… and Print…, which a SwiftUI app has only for a document
      // scene (#375). Print is disabled unless a document is on screen.
      CommandGroup(replacing: .printItem) {
        Button("Page Setup…") { active.controller?.output.runPageSetup() }
          .keyboardShortcut(ReaderShortcut.pageSetup.keyboardShortcut)
          .disabled(active.controller == nil)
        Button("Print…") { active.controller?.output.printDocument() }
          .keyboardShortcut(ReaderShortcut.print.keyboardShortcut)
          .disabled(!offersPrintAndExport)
      }
    #endif
    CommandGroup(after: .toolbar) {
      // View > Bigger, Smaller and Actual Size (#153), the reader's own size on top
      // of the system's. A setting of the app's rather than the window's, as the
      // Settings slider it steps is, so it needs no reader to act on.
      //
      // Not in a `Section`: the group draws a separator before itself and a section
      // one at each end, so a section opening the group drew two lines -- measured,
      // as in the `.sidebar` group below.
      //
      // ⌘= is Bigger too, and not here: on the Mac, SwiftUI left a hidden item out
      // of the menu, shortcut and all -- measured. `ReaderWindow` answers it on the
      // Mac, an invisible button in `ContentView` on the iPad.
      Button("Bigger") { fontSize = ReaderPreferences.fontSize(steppingUp: fontSize) }
        .keyboardShortcut(ReaderShortcut.bigger.keyboardShortcut)
        .disabled(ReaderPreferences.fontSize(steppingUp: fontSize) == fontSize)
      Button("Smaller") { fontSize = ReaderPreferences.fontSize(steppingDown: fontSize) }
        .keyboardShortcut(ReaderShortcut.smaller.keyboardShortcut)
        .disabled(ReaderPreferences.fontSize(steppingDown: fontSize) == fontSize)
      Button("Actual Size") { fontSize = ReaderPreferences.defaultFontSize }
        .keyboardShortcut(ReaderShortcut.actualSize.keyboardShortcut)
        .disabled(fontSize == ReaderPreferences.defaultFontSize)
      #if os(macOS)
        // View > Sort By and Show Obsolete (#349): the Mac had no way to reach the
        // list's view options before.
        if let navigation {
          Section {
            ListViewOptions(navigation: navigation)
          }
        }
        // View > Reading Mode (#698): the window's, as the reader's place is.
        //
        // Not in a `Section`: the list options' section draws a line after itself and
        // the `.sidebar` group one before itself, which are the two around this, and a
        // section of its own drew a second line on each side.
        if let reader {
          ReadingModePicker(reader: reader)
            .disabled(!showsDocument)
          FocusSteps(reader: reader)
            .disabled(!showsDocument)
          OutlineSectionItems(reader: reader)
            .disabled(!showsDocument)
        }
        // View ▸ Compare Side by Side (#187), beside the other ways of reading it.
        if let controller = active.controller, let reader,
          let document = controller.navigation.shown, showsDocument
        {
          CompareItems(id: document, library: controller.library, reader: reader)
        }
      #endif
    }
    CommandGroup(before: .sidebar) {
      #if os(macOS)
        // View ▸ Show Sidebar (#157). Not `SidebarCommands()`: SwiftUI's item never
        // reads the state of a split view AppKit made, so its title stayed "Show
        // Sidebar" with the sidebar open, and its first click did nothing -- measured.
        // Here rather than replacing `.sidebar`, which a scene with no `WindowGroup`
        // does not have: the item never appeared.
        //
        // Outside the `Section`, first in the group: the group draws a separator
        // before itself and a section draws one at each end, so a section opening
        // the group drew two lines there -- measured.
        Button(active.isSidebarCollapsed ? "Show Sidebar" : "Hide Sidebar") {
          active.controller?.toggleSidebar()
        }
        .keyboardShortcut(ReaderShortcut.toggleSidebar.keyboardShortcut)
        .disabled(active.controller == nil)
      #endif
      Section {
        #if os(macOS)
          // ⌥⌘I, the inspector's chord in Pages, Keynote and Finder. It was ⌘⇧T,
          // which every tabbed Mac app gives to reopening the last closed tab
          // (#157).
          Button(paneTitle(.navigation)) { active.controller?.press(.navigation) }
            .keyboardShortcut(ReaderShortcut.contents.keyboardShortcut)
            // As the toolbar's button is: on whatever the index describes, a
            // document still loading or one that failed to included (#325), and
            // nothing else, where the panel is an empty strip. Not `showsDocument`,
            // which also needs a selection: the chord has to be able to close a
            // panel that is still open.
            .disabled(reader?.canDescribe != true)
          // ⌘I, Get Info in Finder and Preview.
          Button(paneTitle(.info)) { active.controller?.press(.info) }
            .keyboardShortcut(ReaderShortcut.info.keyboardShortcut)
            .disabled(reader?.canDescribe != true)
        #endif
        // On the Mac ⌘[ and ⌘], as Safari's and Finder's menus list them (#761). Not
        // the arrows: AppKit gives a menu item its key before a text field, and ⌘←
        // and ⌘→ are a field's line start and end. The reader window answers them
        // where no field is being edited (`HistoryArrowShortcut`). The iPad keeps
        // the arrows, which nothing else there answers.
        Button("Back") { navigation?.goBack() }
          .keyboardShortcut(ReaderShortcut.back.keyboardShortcut)
          .disabled(navigation?.canGoBack != true)
        Button("Forward") { navigation?.goForward() }
          .keyboardShortcut(ReaderShortcut.forward.keyboardShortcut)
          .disabled(navigation?.canGoForward != true)
      }
    }
    #if os(macOS)
      // `NSTextView.usesFindBar` puts a find bar in the scroll view, but nothing
      // opens it: AppKit's find bar is driven from the Edit > Find menu, and a
      // SwiftUI app has no such item, so Cmd+F reached nothing at all. These focus
      // the key window's text first, then send the action down the responder chain.
      CommandGroup(after: .textEditing) {
        // Disabled unless a document is on screen: there is nothing to search with
        // none, while one loads or failed to (#157). Original Text counts: on macOS
        // it is an `NSTextView` with a find bar of its own, which answers the same
        // action (#159).
        Section {
          Button("Find…") { FindCommand.showFindInterface.send() }
            .keyboardShortcut(ReaderShortcut.find.keyboardShortcut)
          Button("Find Next") { FindCommand.nextMatch.send() }
            .keyboardShortcut(ReaderShortcut.findNext.keyboardShortcut)
          Button("Find Previous") { FindCommand.previousMatch.send() }
            .keyboardShortcut(ReaderShortcut.findPrevious.keyboardShortcut)
          // As TextEdit's and Safari's Find menus have them (#761). Only over a
          // selection: they act on it.
          Group {
            Button("Use Selection for Find") { active.controller?.useSelectionForFind() }
              .keyboardShortcut(ReaderShortcut.useSelectionForFind.keyboardShortcut)
            Button("Jump to Selection") { active.controller?.jumpToSelection() }
              .keyboardShortcut(ReaderShortcut.jumpToSelection.keyboardShortcut)
          }
          .disabled(!hasFindableSelection)
        }
        .disabled(!showsDocument)
        // ⌥⌘F, the chord Mail and Notes give their search field. Enabled with any
        // reader window: the library is there to search with no document open.
        Section {
          Button("Search Library") { active.controller?.focusSearch() }
            .keyboardShortcut(ReaderShortcut.searchLibrary.keyboardShortcut)
            .disabled(active.controller == nil)
        }
      }
    #else
      // ⌘F on an iPad's keyboard, whatever has focus, as VISION promises (#763):
      // UIKit's own reached Find only with the text view first responder. In place
      // of UIKit's, so the menu bar has one Find and ⌘F one handler; with Find Next
      // and Find Previous, which went with UIKit's group, as the Mac's has them.
      CommandGroup(replacing: .textEditing) {
        Section {
          Button("Find…") { reader?.presentFind() }
            .keyboardShortcut(ReaderShortcut.find.keyboardShortcut)
          Button("Find Next") { reader?.findInteraction?.findNext() }
            .keyboardShortcut(ReaderShortcut.findNext.keyboardShortcut)
          Button("Find Previous") { reader?.findInteraction?.findPrevious() }
            .keyboardShortcut(ReaderShortcut.findPrevious.keyboardShortcut)
        }
        .disabled(navigation?.selection == nil || reader?.offersFind != true)
      }
    #endif
  }
}
