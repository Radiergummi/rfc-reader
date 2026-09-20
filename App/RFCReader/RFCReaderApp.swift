import SwiftData
import SwiftUI

@main
struct RFCReaderApp: App {
    @State private var library = LibraryModel.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(library)
                .task { await library.bootstrap() }
                .onOpenURL { url in
                    // rfc://9110/section/4.2, plus rfc-editor.org and datatracker links
                    // handed over via the share sheet or Universal Links later on.
                    if let link = RFCLink(url: url) {
                        library.open(link)
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

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("Go to RFC…") { openDocument?() }
                .keyboardShortcut("l", modifiers: .command)
        }
    }
}

struct OpenDocumentActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

extension FocusedValues {
    var openDocumentAction: OpenDocumentActionKey.Value? {
        get { self[OpenDocumentActionKey.self] }
        set { self[OpenDocumentActionKey.self] = newValue }
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
