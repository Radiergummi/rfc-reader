import CoreSpotlight
import RFCKit
import RFCReaderKit
import SwiftData
import SwiftUI

#if os(macOS)
  import AppKit
#endif

@main
struct RFCReaderApp: App {
  #if !os(macOS)
    @State private var library = LibraryModel.shared
  #else
    /// Windows are made by the delegate. macOS has no `WindowGroup` at all: the
    /// contents panel has to be a real `NSSplitViewItem` in the window's own split
    /// view controller for the tab bar and the toolbar to be confined by it, and a
    /// window `WindowGroup` made cannot be given one — see `ReaderWindowController`.
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
  #endif

  var body: some Scene {
    #if os(macOS)
      // The only scene, and still enough to carry the menu bar: `.commands` are
      // honored with no `WindowGroup` present, measured, which is what keeps the
      // whole menu from having to be rebuilt in AppKit. What it does not carry is
      // File ▸ New Window, which `WindowGroup` used to contribute — `WindowCommands`
      // puts it back.
      Settings {
        SettingsView()
      }
      .commands {
        WindowCommands()
        DocumentCommands()
        #if DEBUG
          DeveloperCommands()
        #endif
      }
    #else
      // Deliberately plain: neither `WindowGroup(id:)` nor `WindowGroup(for:)`
      // opens a window at launch — measured, both leave the app running with no
      // interface at all — so this cannot carry the link for a new tab.
      WindowGroup {
        ContentView()
          .environment(library)
          .task { await library.bootstrap() }
          .onOpenURL { url in
            // rfc://9110#section-4.2, plus rfc-editor.org and datatracker
            // links handed over via the share sheet or Universal Links later.
            //
            // Every open scene receives this, so the routing decision cannot
            // be made here: `LibraryModel` holds the registry and picks
            // exactly one scene to act on it.
            if let link = RFCLink(url: url) {
              library.route(link)
            }
          }
          // An RFC chosen in Spotlight (#178), routed the same way.
          .onContinueUserActivity(CSSearchableItemActionType) { activity in
            if let id = SpotlightEntry.documentID(from: activity) {
              library.route(RFCLink(id: id))
            }
          }
      }
      .modelContainer(AppData.container)
      .commands {
        DocumentCommands()
      }
    #endif
  }
}

#if os(macOS)
  /// What `WindowGroup` used to contribute to the File menu.
  struct WindowCommands: Commands {
    var body: some Commands {
      CommandGroup(replacing: .newItem) {
        Button("New Window") {
          AppDelegate.shared?.openWindow(tabbedWith: nil, inBackground: false)
        }
        .keyboardShortcut("n", modifiers: .command)

        Button("New Tab") {
          AppDelegate.shared?.openTab(inBackground: false)
        }
        .keyboardShortcut("t", modifiers: .command)
      }
    }
  }
#endif

#if os(macOS) && DEBUG
  /// A developer's way in until packs have a Settings ▸ Offline of their own (#36):
  /// install the legacy XML pack from an `.aar` or an unpacked folder.
  struct DeveloperCommands: Commands {
    var body: some Commands {
      CommandMenu("Developer") {
        Button("Install Data Pack…") { Self.chooseAndInstall() }
      }
    }

    private static func chooseAndInstall() {
      let panel = NSOpenPanel()
      panel.message = "Choose a legacy XML pack: an .aar archive, or a folder with its manifest."
      panel.canChooseFiles = true
      panel.canChooseDirectories = true
      panel.allowsMultipleSelection = false
      guard panel.runModal() == .OK, let source = panel.url else { return }
      Task {
        let alert = NSAlert()
        do {
          let pack = try await LibraryModel.shared.installLegacyPack(from: source)
          alert.messageText = "Installed Data Pack \(pack.manifest.version)"
          alert.informativeText = "\(pack.manifest.files.count) documents."
        } catch {
          alert.alertStyle = .warning
          alert.messageText = "Couldn’t Install the Data Pack"
          alert.informativeText = String(describing: error)
        }
        alert.runModal()
      }
    }
  }
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
    private var openDocument: (() -> Void)? {
      guard let navigation else { return nil }
      return { navigation.isShowingGoToSheet = true }
    }
    private var isBookmarked: Bool { active.controller?.isBookmarked == true }
    private func toggleBookmark() { active.controller?.toggleBookmark() }
  #else
    @FocusedValue(\.openDocumentAction) private var openDocument
    /// The focused scene's navigation, so Back and Forward act on the tab the reader
    /// is actually looking at rather than on whichever one registered last.
    @FocusedValue(\.navigationModel) private var navigation
    /// The focused scene's reader, for the title a new bookmark is filed under.
    @FocusedValue(\.readerState) private var reader
    @State private var library = LibraryModel.shared

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
          if let navigation, let document = navigation.selection {
            Menu("Add to Collection") {
              AddToCollectionItems(
                document: document, library: .shared, navigation: navigation,
                undoManager: active.controller?.window?.undoManager)
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
          .disabled(!showsDocument)
      }
      // File > Page Setup… and Print…, which a SwiftUI app has only for a document
      // scene (#375). Print is disabled unless a document is on screen.
      CommandGroup(replacing: .printItem) {
        Button("Page Setup…") { active.controller?.runPageSetup() }
          .keyboardShortcut("p", modifiers: [.command, .shift])
          .disabled(active.controller == nil)
        Button("Print…") { active.controller?.printDocument() }
          .keyboardShortcut("p", modifiers: .command)
          .disabled(!showsDocument)
      }
    #endif
    CommandGroup(after: .toolbar) {
      // View > Bigger, Smaller and Actual Size (#153), the reader's own size on top
      // of the system's. A setting of the app's rather than the window's, as the
      // Settings slider it steps is, so it needs no reader to act on.
      Section {
        Button("Bigger") { fontSize = ReaderPreferences.fontSize(steppingUp: fontSize) }
          .keyboardShortcut("+", modifiers: .command)
          .disabled(fontSize >= ReaderPreferences.fontSizes.upperBound)
        Button("Smaller") { fontSize = ReaderPreferences.fontSize(steppingDown: fontSize) }
          .keyboardShortcut("-", modifiers: .command)
          .disabled(fontSize <= ReaderPreferences.fontSizes.lowerBound)
        Button("Actual Size") { fontSize = ReaderPreferences.defaultFontSize }
          .keyboardShortcut("0", modifiers: .command)
          .disabled(fontSize == ReaderPreferences.defaultFontSize)
      }
      #if os(macOS)
        // View > Sort By and Show Obsolete (#349): the Mac had no way to reach the
        // list's view options before.
        if let navigation {
          Section {
            ListViewOptions(navigation: navigation)
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

#if os(macOS)
  /// One find-bar action, sent to the first responder that can perform it.
  ///
  /// `performTextFinderAction(_:)` decides *which* action it is by reading `tag` off
  /// its sender, which is why the sender is this tiny object rather than nil: the
  /// selector alone carries no way to say "show the bar" versus "find next".
  final class FindCommand: NSObject {
    static let showFindInterface = FindCommand(.showFindInterface)
    static let nextMatch = FindCommand(.nextMatch)
    static let previousMatch = FindCommand(.previousMatch)

    @objc let tag: Int

    private init(_ action: NSTextFinder.Action) {
      self.tag = action.rawValue
    }

    func send() {
      ActiveReaderWindow.shared.controller?.focusSearchableText()
      NSApp.sendAction(#selector(NSTextView.performTextFinderAction(_:)), to: nil, from: self)
    }
  }
#endif

// Published by `ContentView` and read by `DocumentCommands`, both of which are
// iOS-only now: on macOS the menu finds its target through `ActiveReaderWindow`,
// because focused values do not resolve out of a hosted root.
#if !os(macOS)
  struct OpenDocumentActionKey: FocusedValueKey {
    typealias Value = () -> Void
  }

  struct NavigationModelKey: FocusedValueKey {
    typealias Value = NavigationModel
  }

  struct ReaderStateKey: FocusedValueKey {
    typealias Value = ReaderState
  }

  extension FocusedValues {
    var openDocumentAction: OpenDocumentActionKey.Value? {
      get { self[OpenDocumentActionKey.self] }
      set { self[OpenDocumentActionKey.self] = newValue }
    }

    var navigationModel: NavigationModel? {
      get { self[NavigationModelKey.self] }
      set { self[NavigationModelKey.self] = newValue }
    }

    var readerState: ReaderState? {
      get { self[ReaderStateKey.self] }
      set { self[ReaderStateKey.self] = newValue }
    }
  }
#endif

/// The app's settings, tabbed the way a Mac app's are. A tab joins as a feature
/// arrives that has something worth configuring, rather than ahead of it.
struct SettingsView: View {
  var body: some View {
    TabView {
      Tab("Reading", systemImage: "textformat.size") {
        ReadingSettings()
      }
      Tab("General", systemImage: "gearshape") {
        GeneralSettings()
      }
    }
    // A grouped form is scroll-backed and has no height of its own to offer, so
    // the window is told to size to it rather than left to guess.
    .frame(width: 460)
    .fixedSize(horizontal: false, vertical: true)
  }
}

private struct ReadingSettings: View {
  @AppStorage(ReaderPreferences.fontSizeKey) private var fontSize = ReaderPreferences
    .defaultFontSize
  @AppStorage(ReaderPreferences.measureKey) private var measure = ReaderPreferences.defaultMeasure
  @AppStorage(ReaderPreferences.underlineLinksKey) private var underlineLinks =
    ReaderPreferences.defaultUnderlineLinks

  /// A toggle over the preference rather than a picker: there are two choices,
  /// and one of them is the default the reader opts out of.
  private var usesFullWidth: Binding<Bool> {
    Binding(
      get: { measure == .fullWidth },
      set: { measure = $0 ? .fullWidth : .recommended }
    )
  }

  var body: some View {
    Form {
      Slider(
        value: $fontSize, in: ReaderPreferences.fontSizes, step: ReaderPreferences.fontSizeStep
      ) {
        Text("Reading font size: \(Int(fontSize))")
      }
      Toggle(isOn: usesFullWidth) {
        Text("Use the full window width for text")
        Text("Otherwise lines stop at a comfortable reading length, and the text is centered.")
      }
      Toggle("Underline links", isOn: $underlineLinks)
    }
    .formStyle(.grouped)
  }
}

private struct GeneralSettings: View {
  @AppStorage(ReaderPreferences.preferOriginalTextKey) private var preferOriginalText =
    ReaderPreferences.defaultPreferOriginalText

  var body: some View {
    Form {
      Toggle("Show the original text rendering by default", isOn: $preferOriginalText)
    }
    .formStyle(.grouped)
  }
}
