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
    // Routed rather than assigned: the intent has no scene of its own, so the
    // library decides which open tab answers it.
    LibraryModel.shared.route(RFCLink(id: .rfc(number), section: section))
    return .result()
  }
}

struct RFCReaderShortcuts: AppShortcutsProvider {
  static var appShortcuts: [AppShortcut] {
    AppShortcut(
      intent: OpenRFCIntent(),
      // Phrases may only interpolate AppEntity/AppEnum parameters, so the number
      // is asked for after the phrase matches. An RFC AppEntity would let Siri
      // hear it directly; that belongs with Spotlight indexing.
      phrases: [
        "Open an RFC in \(.applicationName)",
        "Show an RFC in \(.applicationName)",
      ],
      shortTitle: "Open RFC",
      systemImageName: "doc.text"
    )
  }
}
