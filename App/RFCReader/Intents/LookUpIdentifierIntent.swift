import AppIntents
import RFCKit
import SwiftUI

/// "Look up TLS alert 70" (#192): a protocol identifier in the IANA registries the
/// Go to RFC palette reads (#175), returned with what defines it, and a button that
/// opens the defining section.
struct LookUpIdentifierIntent: AppIntent {
  static let title: LocalizedStringResource = "Look Up Identifier"
  static let description = IntentDescription(
    "Looks up a protocol identifier, such as HTTP status 425, TLS alert 70 or the Retry-After field, and finds the RFC section that defines it."
  )

  @Parameter(title: "Identifier")
  var entry: RegistryEntryEntity

  static var parameterSummary: some ParameterSummary {
    Summary("Look up \(\.$entry)")
  }

  @MainActor
  func perform() async throws
    -> some IntentResult & ReturnsValue<RegistryEntryEntity> & ProvidesDialog & ShowsSnippetView
  {
    .result(value: entry, dialog: Self.dialog(for: entry), view: RegistryEntrySnippet(entry: entry))
  }

  /// `TLS alert 70, protocol_version, is defined in RFC 8446, Section 6.2.`
  private static func dialog(for entry: RegistryEntryEntity) -> IntentDialog {
    let named = entry.name.map { "\(entry.heading), \($0)," } ?? entry.heading
    guard let definedIn = entry.definedIn else {
      return "\(named) is in IANA's registry, which names no RFC for it."
    }
    return "\(named) is defined in \(definedIn)."
  }
}

/// Opens the section that defines an identifier: the button of Look Up Identifier's
/// result, and not offered as an action of its own.
struct OpenDefinitionIntent: AppIntent {
  static let title: LocalizedStringResource = "Open Definition"
  static let openAppWhenRun = true
  static let isDiscoverable = false

  @Parameter(title: "Identifier")
  var entry: RegistryEntryEntity

  init() {}

  init(entry: RegistryEntryEntity) {
    self.entry = entry
  }

  @MainActor
  func perform() async throws -> some IntentResult {
    if let reference = entry.reference { LibraryModel.shared.route(reference) }
    return .result()
  }
}

/// What Look Up Identifier shows: the identifier, its name, where it is defined, and
/// a button that opens that.
private struct RegistryEntrySnippet: View {
  let entry: RegistryEntryEntity

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(entry.heading).font(.headline)
      if let name = entry.name { Text(name).font(.body.monospaced()) }
      if let definedIn = entry.definedIn {
        Text("Defined in \(definedIn)").foregroundStyle(.secondary)
        Button(intent: OpenDefinitionIntent(entry: entry)) {
          Label("Open in RFC Reader", systemImage: "doc.text")
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding()
  }
}
