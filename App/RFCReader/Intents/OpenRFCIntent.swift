import AppIntents
import RFCKit

/// "Open RFC 9110 in RFC Reader" from Siri, Spotlight, Shortcuts and the Action
/// button. An open intent, so a Spotlight result, which is an `RFCEntity`, opens
/// through it too.
struct OpenRFCIntent: OpenIntent {
  static let title: LocalizedStringResource = "Open RFC"
  static let description = IntentDescription("Opens an RFC, at a section if one is given.")
  static let openAppWhenRun = true

  @Parameter(title: "RFC")
  var target: RFCEntity

  /// A section's number, `4.2`, or an anchor.
  @Parameter(title: "Section", default: nil)
  var section: String?

  static var parameterSummary: some ParameterSummary {
    Summary("Open \(\.$target)") {
      \.$section
    }
  }

  @MainActor
  func perform() async throws -> some IntentResult {
    // Routed rather than assigned: the intent has no scene of its own, so the
    // library decides which open tab answers it. `.shared`, because App Intents
    // makes the intent and has no way to hand it anything.
    LibraryModel.shared.route(RFCLink(id: target.documentID, section: section))
    return .result()
  }
}

/// Opens a section of an RFC (#192), chosen from the document's contents.
struct OpenSectionIntent: OpenIntent {
  static let title: LocalizedStringResource = "Open Section"
  static let description = IntentDescription("Opens a section of an RFC.")
  static let openAppWhenRun = true

  /// The sections offered are this RFC's (`SectionEntityQuery`). Optional: a
  /// section handed over already names its RFC, and opens without one.
  @Parameter(title: "RFC", default: nil)
  var document: RFCEntity?

  @Parameter(title: "Section")
  var target: SectionEntity

  static var parameterSummary: some ParameterSummary {
    Summary("Open \(\.$target) of \(\.$document)")
  }

  @MainActor
  func perform() async throws -> some IntentResult {
    LibraryModel.shared.route(target.link)
    return .result()
  }
}

struct RFCReaderShortcuts: AppShortcutsProvider {
  static var appShortcuts: [AppShortcut] {
    AppShortcut(
      intent: OpenRFCIntent(),
      // A phrase can name only the RFCs `RFCEntityQuery` suggests, the ones read
      // recently; any other is asked for after a phrase without one matches.
      phrases: [
        "Open \(\.$target) in \(.applicationName)",
        "Show \(\.$target) in \(.applicationName)",
        "Open an RFC in \(.applicationName)",
        "Show an RFC in \(.applicationName)",
      ],
      shortTitle: "Open RFC",
      systemImageName: "doc.text"
    )
    AppShortcut(
      intent: OpenSectionIntent(),
      phrases: [
        "Open a section of an RFC in \(.applicationName)"
      ],
      shortTitle: "Open Section",
      systemImageName: "text.line.first.and.arrowtriangle.forward"
    )
    AppShortcut(
      intent: LookUpIdentifierIntent(),
      phrases: [
        "Look up an identifier in \(.applicationName)",
        "Look up a protocol identifier in \(.applicationName)",
      ],
      shortTitle: "Look Up Identifier",
      systemImageName: "number"
    )
    AppShortcut(
      intent: RequirementsIntent(),
      phrases: [
        "Find the requirements in \(\.$document) with \(.applicationName)",
        "Find requirements in an RFC with \(.applicationName)",
      ],
      shortTitle: "Find Requirements",
      systemImageName: "checklist"
    )
  }

  /// Tells the system the RFCs a phrase can name have changed: once the index has
  /// loaded, since the suggestions are looked up in it. A wrapper, so the library
  /// does not import App Intents for one call.
  static func refreshParameters() {
    updateAppShortcutParameters()
  }
}
