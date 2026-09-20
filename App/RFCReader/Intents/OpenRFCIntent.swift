import AppIntents
import RFCKit

/// "Open RFC 9110 in RFC Reader" from Siri, Spotlight, Shortcuts and the Action button.
struct OpenRFCIntent: AppIntent {
    static let title: LocalizedStringResource = "Open RFC"
    static let description = IntentDescription("Opens an RFC by number.")
    static let openAppWhenRun = true

    @Parameter(title: "RFC number")
    var number: Int

    @Parameter(title: "Section", default: nil)
    var section: String?

    static var parameterSummary: some ParameterSummary {
        Summary("Open RFC \(\.$number)") {
            \.$section
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        LibraryModel.shared.open(.rfc(number), section: section)
        return .result()
    }
}

struct RFCReaderShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OpenRFCIntent(),
            phrases: [
                "Open RFC \(\.$number) in \(.applicationName)",
                "Show RFC \(\.$number) in \(.applicationName)",
            ],
            shortTitle: "Open RFC",
            systemImageName: "doc.text"
        )
    }
}
