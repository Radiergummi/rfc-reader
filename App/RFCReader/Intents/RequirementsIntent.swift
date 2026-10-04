import AppIntents
import RFCKit
import RFCReaderKit
import SwiftUI

/// "Find the requirements in Section 4 of RFC 9110" (#192): the BCP 14 sentences a
/// section and its subsections state, or the whole RFC, as text a shortcut can pass
/// on, one per requirement with its section's number (`Requirement.line`). The
/// result's button shows them in the Requirements tab (#180).
struct RequirementsIntent: AppIntent {
  static let title: LocalizedStringResource = "Find Requirements"
  static let description = IntentDescription(
    "Lists the BCP 14 requirements an RFC states, in one section and its subsections or in the whole RFC, each with its section's number."
  )

  /// Asked for first: the sections offered are this RFC's (`SectionEntityQuery`).
  @Parameter(title: "RFC")
  var document: RFCEntity

  /// Nil for the whole RFC.
  @Parameter(title: "Section", default: nil)
  var section: SectionEntity?

  static var parameterSummary: some ParameterSummary {
    Summary("Find the requirements in \(\.$document)") {
      \.$section
    }
  }

  @MainActor
  func perform() async throws
    -> some IntentResult & ReturnsValue<[String]> & ProvidesDialog & ShowsSnippetView
  {
    let id = document.documentID
    let loaded = try await IntentDocuments.load(id)
    var scope: RFCKit.Section?
    if let section {
      // A section of another RFC, handed over by a shortcut, is not one of this one.
      guard section.document == id, let found = loaded.section(anchor: section.anchor) else {
        throw IntentFailure.noSuchSection(SectionIdentifier(document: id, anchor: section.anchor))
      }
      scope = found
    }
    let lines = await Self.requirements(in: loaded, within: scope).map(\.line)
    let place =
      section.map { String(localized: "\($0.title) of \(id.displayName)") } ?? id.displayName
    let answer = IntentAnswer.requirements(lines.count, in: place)
    return .result(
      value: lines, dialog: IntentDialog(.verbatim(answer)),
      view: RequirementsSnippet(lines: lines, document: document, section: section))
  }

  /// Off the main actor: extracting them reads every sentence of the document.
  @concurrent
  private static func requirements(in document: RFCDocument, within section: RFCKit.Section?) async
    -> [Requirement]
  {
    let all = Requirements.extract(from: document)
    return section.map { Requirements.within($0, all) } ?? all
  }
}

/// Shows an RFC's Requirements tab, at a section if one is given: the button of Find
/// Requirements' result, and not offered as an action of its own.
struct ShowRequirementsIntent: AppIntent {
  static let title: LocalizedStringResource = "Show Requirements"
  static let openAppWhenRun = true
  static let isDiscoverable = false

  @Parameter(title: "RFC")
  var document: RFCEntity

  @Parameter(title: "Section", default: nil)
  var section: SectionEntity?

  init() {}

  init(document: RFCEntity, section: SectionEntity?) {
    self.document = document
    self.section = section
  }

  @MainActor
  func perform() async throws -> some IntentResult {
    let link = section?.link ?? RFCLink(id: document.documentID)
    LibraryModel.shared.route(link, showing: .requirements)
    return .result()
  }
}

/// What Find Requirements shows: the first few requirements, how many more there
/// are, and a button to the Requirements tab.
private struct RequirementsSnippet: View {
  /// As many as a glance takes in; the rest are in the result and the tab.
  private static let shown = 5

  let lines: [String]
  let document: RFCEntity
  let section: SectionEntity?

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      ForEach(Array(lines.prefix(Self.shown).enumerated()), id: \.offset) { _, line in
        Text(line).lineLimit(3)
      }
      if lines.count > Self.shown {
        Text("and \(lines.count - Self.shown) more").foregroundStyle(.secondary)
      }
      Button(intent: ShowRequirementsIntent(document: document, section: section)) {
        Label("Show in RFC Reader", systemImage: "checklist")
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding()
  }
}
