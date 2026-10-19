import Foundation

/// What Datatracker says of an Internet-Draft (#728): its title, its revisions, and
/// the RFC it became, read from the draft's `doc.json`.
public struct DraftInfo: Hashable, Sendable, Codable {
  /// One revision of the draft, as Datatracker lists it.
  public struct Revision: Hashable, Sendable, Codable {
    /// Two digits, from `00`.
    public let revision: String
    public let published: Date?

    public init(revision: String, published: Date?) {
      self.revision = revision
      self.published = published
    }
  }

  /// The draft's name, without a revision.
  public let name: String
  public let title: String
  /// The newest revision, which the IETF's archive serves.
  public let newestRevision: String
  /// Datatracker's state: `Active`, `Expired`, `Replaced`, `RFC`, and others.
  public let state: String?
  /// The draft's own revisions, oldest first. Not those of a draft it replaced,
  /// which Datatracker lists in the same history under that draft's name.
  public let revisions: [Revision]
  /// The RFC the draft was published as, once it was.
  public let publishedAs: DocumentID?

  public init(
    name: String, title: String, newestRevision: String, state: String?, revisions: [Revision],
    publishedAs: DocumentID?
  ) {
    self.name = name
    self.title = title
    self.newestRevision = newestRevision
    self.state = state
    self.revisions = revisions
    self.publishedAs = publishedAs
  }

  /// The newest revision's identity.
  public var newest: DraftID? { DraftID(name: name, revision: newestRevision) }

  /// Decodes Datatracker's `doc.json` for a draft.
  public static func decode(_ data: Data) throws -> DraftInfo {
    let document = try JSONDecoder().decode(DraftDocumentJSON.self, from: data)
    // Datatracker writes the seconds' fraction whenever the time has one, which a
    // formatter reads only when told to, and then only when it is there.
    let whole = ISO8601DateFormatter()
    let fractional = ISO8601DateFormatter()
    fractional.formatOptions.insert(.withFractionalSeconds)
    let date = { (string: String) in whole.date(from: string) ?? fractional.date(from: string) }
    let revisions = document.revHistory.filter { $0.name == document.name }.map {
      Revision(revision: $0.rev, published: $0.published.flatMap(date))
    }
    // The history ends with the RFC, named `rfc9110` with that as its revision too.
    let publishedAs = document.revHistory.lazy.compactMap { DocumentID(fileStem: $0.name) }
      .first
    return DraftInfo(
      name: document.name, title: document.title, newestRevision: document.rev,
      state: document.state, revisions: revisions, publishedAs: publishedAs)
  }
}

/// The parts of Datatracker's `doc.json` that `DraftInfo` reads.
private struct DraftDocumentJSON: Decodable {
  /// One entry of the history: a revision of this draft, of one it replaced, or
  /// the RFC it became.
  struct Entry: Decodable {
    let name: String
    let rev: String
    let published: String?
  }

  let name: String
  let rev: String
  let title: String
  let state: String?
  let revHistory: [Entry]

  enum CodingKeys: String, CodingKey {
    case name, rev, title, state
    case revHistory = "rev_history"
  }
}
