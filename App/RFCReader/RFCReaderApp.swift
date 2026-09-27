import RFCKit
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
        // View ▸ Show Sidebar. It sends `toggleSidebar:` down the responder chain,
        // which the window's own `NSSplitViewController` answers (#157).
        SidebarCommands()
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
            // rfc://9110/section/4.2, plus rfc-editor.org and datatracker
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
          Button("Contents") { active.controller?.togglePanel() }
            .keyboardShortcut("i", modifiers: [.command, .option])
            // As the toolbar's button is: opened with no document, the panel is an
            // empty strip, and nothing closes it again until a document arrives.
            // Not `showsDocument`: clearing the selection leaves `hasDocument` set
            // and the panel open, and the chord has to be able to close it.
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
  @MainActor
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

struct SettingsView: View {
  @AppStorage("readingFontSize") private var fontSize = 17.0
  @AppStorage("preferOriginalText") private var preferOriginalText = false

  var body: some View {
    Form {
      Slider(value: $fontSize, in: 12...28, step: 1) {
        Text("Reading font size: \(Int(fontSize))")
      }
      Toggle("Show the original text rendering by default", isOn: $preferOriginalText)
    }
    .padding()
    .frame(width: 420)
  }
}
