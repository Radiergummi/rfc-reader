import Foundation
import RFCKit

/// How a document got where it is (#364): the stream it came through, the working
/// group that wrote it, and the status it has, read as one path, each step opening
/// what it names. The inspector's first section after its header; the facts are the
/// index's, and only arranged here.
public struct Provenance: Equatable, Sendable {
  public enum Kind: Equatable, Sendable {
    case stream
    case workingGroup
    case status
  }

  /// What a step opens: a glossary entry (#362), or a working group's card (#363),
  /// by the group's acronym.
  public enum Target: Equatable, Sendable {
    case glossary(Glossary.Term)
    case workingGroup(String)
  }

  public struct Step: Equatable, Sendable {
    public let kind: Kind
    /// What the chain shows: "IETF", "httpbis", "Proposed Standard → Internet
    /// Standard".
    public let text: String
    /// What VoiceOver says for it, which names the step: "Stream: IETF".
    public let accessibilityLabel: String
    public let target: Target
  }

  /// Stream, then working group, then status; a document from no working group goes
  /// from its stream to its status, and one whose status the index does not know
  /// ends at its stream or group.
  public let steps: [Step]
  /// "Published June 2022", under the chain. What it obsoletes and updates, and what
  /// replaces or updates it, stay in Relationships, where each is a document to open.
  public let published: String

  /// The section's title.
  public let title: String

  public init(_ metadata: RFCMetadata, locale: Locale = .interface) {
    var steps: [Step] = []
    let stream = metadata.stream.displayName
    steps.append(
      Step(
        kind: .stream, text: stream,
        accessibilityLabel: String(kit: "Stream: \(stream)", locale: locale),
        target: .glossary(.stream(metadata.stream))))
    if let group = metadata.namedWorkingGroup {
      steps.append(
        Step(
          kind: .workingGroup, text: group,
          accessibilityLabel: String(kit: "Working group: \(group)", locale: locale),
          target: .workingGroup(group)))
    }
    let status = metadata.currentStatus
    if status != .unknown {
      let original = metadata.publicationStatus
      // The status it was published with only where it differs from today's: a
      // Proposed Standard since advanced, or a document since made historic.
      let changed = original != .unknown && original != status
      steps.append(
        Step(
          kind: .status,
          text: changed ? "\(original.displayName) → \(status.displayName)" : status.displayName,
          accessibilityLabel: changed
            ? String(
              kit: "Status: \(original.displayName), now \(status.displayName)", locale: locale)
            : String(kit: "Status: \(status.displayName)", locale: locale),
          target: .glossary(.status(status))))
    }
    self.steps = steps
    published = String(kit: "Published \(metadata.date.formatted(in: locale))", locale: locale)
    title = String(kit: "Provenance", locale: locale)
  }
}
