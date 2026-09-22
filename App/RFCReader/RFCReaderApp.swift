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
                AppDelegate.shared?.openWindow(tabbedWith: AppDelegate.shared?.activeController, inBackground: false)
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
            Section {
                #if os(macOS)
                Button("Contents") { active.controller?.togglePanel() }
                    .keyboardShortcut("t", modifiers: [.command, .shift])
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
        // SwiftUI app has no such item, so Cmd+F reached nothing at all. These send
        // the action down the responder chain to whichever text view is focused.
        CommandGroup(after: .textEditing) {
            Section {
                Button("Find…") { FindCommand.showFindInterface.send() }
                    .keyboardShortcut("f", modifiers: .command)
                Button("Find Next") { FindCommand.nextMatch.send() }
                    .keyboardShortcut("g", modifiers: .command)
                Button("Find Previous") { FindCommand.previousMatch.send() }
                    .keyboardShortcut("g", modifiers: [.command, .shift])
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
        NSApp.sendAction(#selector(NSTextView.performTextFinderAction(_:)), to: nil, from: self)
    }
}
#endif

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
