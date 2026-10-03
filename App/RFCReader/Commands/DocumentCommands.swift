import RFCKit
import RFCReaderKit
import SwiftUI

#if os(macOS)
  import AppKit
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
  #endif

  var body: some Commands {
    CommandGroup(after: .newItem) {
      Button("Go to RFC…") { openDocument?() }
        .keyboardShortcut("l", modifiers: .command)
        .disabled(openDocument == nil)
      #if os(macOS)
        Button("New Collection…") { active.controller?.newCollection() }
          .keyboardShortcut("n", modifiers: [.command, .shift])
          .disabled(navigation == nil)
      #endif
    }
    // The Mac's toolbar buttons are AppKit's, so their keyboard shortcuts have to be
    // menu items: an `NSToolbarItem` carries no key equivalent of its own. ⌘D is one
    // on the iPad too, rather than the toolbar button's, so its title in the menu bar
    // and the hold-⌘ overlay can follow the action as the Mac's does (#278).
    CommandGroup(after: .pasteboard) {
      #if os(macOS)
        // Handed to the reader's text view (#186); see
        // `ReaderWindowController.copyAsQuote()`. Grayed out without a selection, as
        // Copy is; the original text is not the reader's, and has no quote to copy.
        Button("Copy as Quote") {
          active.controller?.copyAsQuote()
        }
        .keyboardShortcut("c", modifiers: [.command, .option, .shift])
        .disabled(
          !showsDocument || reader?.showOriginal == true || reader?.hasSelection != true)
      #endif
      Section {
        // Says what it will do, as the toolbar's glyph does: both read the
        // library's set of bookmarked documents, which the menu observes.
        Button(DocumentActions.bookmarkCommand(isBookmarked: isBookmarked)) {
          toggleBookmark()
        }
        .keyboardShortcut("d", modifiers: .command)
        .disabled(navigation?.selection == nil)
        #if os(macOS)
          // The key window's undo manager, so Edit > Undo puts back a document
          // removed from here, as it does for a removal in the list (#349).
          if let controller = active.controller, let document = controller.navigation.selection {
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
        Button("Export…") { active.controller?.exportDocument() }
          .keyboardShortcut("e", modifiers: [.command, .shift])
          .disabled(!offersPrintAndExport)
      }
      // File > Page Setup… and Print…, which a SwiftUI app has only for a document
      // scene (#375). Print is disabled unless a document is on screen.
      CommandGroup(replacing: .printItem) {
        Button("Page Setup…") { active.controller?.runPageSetup() }
          .keyboardShortcut("p", modifiers: [.command, .shift])
          .disabled(active.controller == nil)
        Button("Print…") { active.controller?.printDocument() }
          .keyboardShortcut("p", modifiers: .command)
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
        .keyboardShortcut("+", modifiers: .command)
        .disabled(ReaderPreferences.fontSize(steppingUp: fontSize) == fontSize)
      Button("Smaller") { fontSize = ReaderPreferences.fontSize(steppingDown: fontSize) }
        .keyboardShortcut("-", modifiers: .command)
        .disabled(ReaderPreferences.fontSize(steppingDown: fontSize) == fontSize)
      Button("Actual Size") { fontSize = ReaderPreferences.defaultFontSize }
        .keyboardShortcut("0", modifiers: .command)
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
        if let reader {
          Section {
            ReadingModePicker(reader: reader)
              .disabled(!showsDocument)
          }
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
        .keyboardShortcut("s", modifiers: [.command, .control])
        .disabled(active.controller == nil)
      #endif
      Section {
        #if os(macOS)
          // ⌥⌘I, the inspector's chord in Pages, Keynote and Finder. It was ⌘⇧T,
          // which every tabbed Mac app gives to reopening the last closed tab
          // (#157).
          Button("Contents") { active.controller?.press(.navigation) }
            .keyboardShortcut("i", modifiers: [.command, .option])
            // As the toolbar's button is: on whatever the index describes, a
            // document still loading or one that failed to included (#325), and
            // nothing else, where the panel is an empty strip. Not `showsDocument`,
            // which also needs a selection: the chord has to be able to close a
            // panel that is still open.
            .disabled(reader?.canDescribe != true)
          // ⌘I, Get Info in Finder and Preview.
          Button("Info") { active.controller?.press(.info) }
            .keyboardShortcut("i", modifiers: .command)
            .disabled(reader?.canDescribe != true)
        #endif
        // Cmd+arrow, as Safari and Finder bind it.
        Button("Back") { navigation?.goBack() }
          .keyboardShortcut(.leftArrow, modifiers: .command)
          .disabled(navigation?.canGoBack != true)
        Button("Forward") { navigation?.goForward() }
          .keyboardShortcut(.rightArrow, modifiers: .command)
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
            .keyboardShortcut("f", modifiers: .command)
          Button("Find Next") { FindCommand.nextMatch.send() }
            .keyboardShortcut("g", modifiers: .command)
          Button("Find Previous") { FindCommand.previousMatch.send() }
            .keyboardShortcut("g", modifiers: [.command, .shift])
        }
        .disabled(!showsDocument)
        // ⌥⌘F, the chord Mail and Notes give their search field. Enabled with any
        // reader window: the library is there to search with no document open.
        Section {
          Button("Search Library") { active.controller?.focusSearch() }
            .keyboardShortcut("f", modifiers: [.command, .option])
            .disabled(active.controller == nil)
        }
      }
    #endif
  }
}
