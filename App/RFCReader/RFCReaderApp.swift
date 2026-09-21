import RFCKit
import SwiftData
import SwiftUI
#if os(macOS)
import AppKit
#endif

@main
struct RFCReaderApp: App {
    @State private var library = LibraryModel.shared

    var body: some Scene {
        // Deliberately plain: neither `WindowGroup(id:)` nor `WindowGroup(for:)`
        // opens a window at launch — measured, both leave the app running with no
        // interface at all — so this cannot carry the link for a new tab. The link
        // goes through `LibraryModel` and the tab itself comes from AppKit.
        WindowGroup {
            ContentView()
                .environment(library)
                .task { await library.bootstrap() }
                .onOpenURL { url in
                    // rfc://9110/section/4.2, plus rfc-editor.org and datatracker links
                    // handed over via the share sheet or Universal Links later on.
                    //
                    // Every open scene receives this, so the routing decision cannot be
                    // made here: `LibraryModel` holds the registry and picks exactly one
                    // scene to act on it.
                    if let link = RFCLink(url: url) {
                        library.route(link)
                    }
                }
        }
        .modelContainer(for: [Bookmark.self, ReadingPosition.self])
        .commands {
            DocumentCommands()
        }

        #if os(macOS)
        Settings {
            SettingsView()
        }
        #endif
    }
}

/// Menu bar commands; also give every action a keyboard shortcut on iPad.
struct DocumentCommands: Commands {
    @FocusedValue(\.openDocumentAction) private var openDocument
    /// The focused scene's navigation, so Back and Forward act on the tab the reader
    /// is actually looking at rather than on whichever one registered last.
    @FocusedValue(\.navigationModel) private var navigation

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("Go to RFC…") { openDocument?() }
                .keyboardShortcut("l", modifiers: .command)
        }
        CommandGroup(before: .sidebar) {
            Section {
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
