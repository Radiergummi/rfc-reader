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
      // honoured with no `WindowGroup` present, measured, which is what keeps the
      // whole menu from having to be rebuilt in AppKit. What it does not carry is
      // File ▸ New Window, which `WindowGroup` used to contribute — `WindowCommands`
      // puts it back.
      Settings {
        SettingsView()
      }
      .commands {
        WindowCommands()
        DocumentCommands()
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

/// Menu bar commands; also give every action a keyboard shortcut on iPad.
struct DocumentCommands: Commands {
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
  #else
    @FocusedValue(\.openDocumentAction) private var openDocument
    /// The focused scene's navigation, so Back and Forward act on the tab the reader
    /// is actually looking at rather than on whichever one registered last.
    @FocusedValue(\.navigationModel) private var navigation
  #endif

  var body: some Commands {
    CommandGroup(after: .newItem) {
      Button("Go to RFC…") { openDocument?() }
        .keyboardShortcut("l", modifiers: .command)
        .disabled(openDocument == nil)
      #if os(macOS)
        Button("New Collection…") { navigation?.collectionEditor = .create(adding: nil) }
          .keyboardShortcut("n", modifiers: [.command, .shift])
          .disabled(navigation == nil)
      #endif
    }
    #if os(macOS)
      // The toolbar's buttons are AppKit's now, so their keyboard shortcuts have to
      // be menu items: an `NSToolbarItem` carries no key equivalent of its own.
      CommandGroup(after: .pasteboard) {
        Section {
          // Static title: whether this RFC is bookmarked is a SwiftData fetch,
          // not something the menu observes, so a "Remove Bookmark" label would
          // go stale. The toolbar's filled glyph carries the state.
          Button("Bookmark") { active.controller?.toggleBookmark() }
            .keyboardShortcut("d", modifiers: .command)
            .disabled(navigation?.selection == nil)
          // The key window's undo manager, so Edit > Undo puts back a document
          // removed from here, as it does for a removal in the list (#349).
          if let navigation, let document = navigation.selection {
            Menu("Add to Collection") {
              AddToCollectionItems(
                document: document, library: .shared, navigation: navigation,
                undoManager: active.controller?.window?.undoManager)
            }
          }
        }
      }
    #endif
    #if os(macOS)
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
    #if os(macOS)
      // View > Sort By and Show Obsolete (#349): the Mac had no way to reach the
      // list's view options before.
      CommandGroup(after: .toolbar) {
        if let navigation {
          ListViewOptions(navigation: navigation)
        }
      }
    #endif
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
            // As the toolbar's button is: opened with no document, the panel is an
            // empty strip, and nothing closes it again until a document arrives.
            // Not `showsDocument`: clearing the selection leaves `hasDocument` set
            // and the panel open, and the chord has to be able to close it.
            .disabled(reader?.hasDocument != true)
          // ⌘I, Get Info in Finder and Preview.
          Button("Info") { active.controller?.press(.info) }
            .keyboardShortcut("i", modifiers: .command)
            .disabled(reader?.hasDocument != true)
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
  /// View > Sort By and View > Show Obsolete, for the key window's list (#349).
  private struct ListViewOptions: View {
    @Bindable var navigation: NavigationModel

    var body: some View {
      Section {
        if case .collection = navigation.filter {
          Picker("Sort By", selection: $navigation.listOptions.collectionSort) {
            ForEach(ListOptions.CollectionSort.allCases, id: \.self) { Text($0.title) }
          }
        } else {
          Picker("Sort By", selection: $navigation.listOptions.order) {
            ForEach(ListOptions.Order.allCases, id: \.self) { Text($0.title) }
          }
          .disabled(!ListOptions.canReorder(navigation.filter, query: navigation.searchText))
        }
        Toggle("Show Obsolete", isOn: $navigation.listOptions.showsObsolete)
      }
    }
  }

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

  extension FocusedValues {
    var openDocumentAction: OpenDocumentActionKey.Value? {
      get { self[OpenDocumentActionKey.self] }
      set { self[OpenDocumentActionKey.self] = newValue }
    }

    var navigationModel: NavigationModel? {
      get { self[NavigationModelKey.self] }
      set { self[NavigationModelKey.self] = newValue }
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
  @AppStorage("readingFontSize") private var fontSize = 17.0
  @AppStorage("readerMeasure") private var measure = MeasurePreference.recommended
  @AppStorage("underlineLinks") private var underlineLinks = false

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
      Slider(value: $fontSize, in: 12...28, step: 1) {
        Text("Reading font size: \(Int(fontSize))")
      }
      Toggle(isOn: usesFullWidth) {
        Text("Use the full window width for text")
        Text("Otherwise lines stop at a comfortable reading length, and the text is centred.")
      }
      Toggle("Underline links", isOn: $underlineLinks)
    }
    .formStyle(.grouped)
  }
}

private struct GeneralSettings: View {
  @AppStorage("preferOriginalText") private var preferOriginalText = false

  var body: some View {
    Form {
      Toggle("Show the original text rendering by default", isOn: $preferOriginalText)
    }
    .formStyle(.grouped)
  }
}
