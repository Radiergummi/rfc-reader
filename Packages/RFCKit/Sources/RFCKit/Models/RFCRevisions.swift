import Foundation

/// `revisions.json`: the adopted Internet-Drafts that intend to obsolete or update an
/// RFC, by the RFC's number. `corpus-build revisions` writes it daily and the app reads
/// it (docs/superpowers/specs/2026-09-29-rfc-revisions-design.md). Both sides encode and
/// decode through `encoded()` and `decode(_:)`, so they agree on dates and keys.
public struct RFCRevisions: Codable, Sendable, Equatable {
  /// The only version this build reads. Bumped on any change a reader of an older
  /// version would misread.
  public static let currentVersion = 1

  public enum VersionError: Error, Equatable {
    case unknown(Int)
  }

  public var version: Int
  /// When the run that wrote the file started. A change made during the run may be in
  /// it or not, but never one from before this time.
  public var generatedAt: Date
  /// RFC number → the drafts that intend to obsolete or update it.
  public var revisions: [Int: [Revision]]

  public struct Revision: Codable, Sendable, Equatable {
    public var relation: RevisionRelation
    /// "draft-ietf-httpbis-rfc6265bis", without the revision.
    public var draft: String
    /// "22".
    public var revision: String
    /// When this revision was posted.
    public var published: Date
    /// "ietf", "irtf", "iab", "ise" or "editorial".
    public var stream: String
    /// "httpbis"; nil when the draft is in no group.
    public var group: String?
    /// "Proposed Standard".
    public var intendedStatus: String?
    public var stage: RevisionStage

    public init(
      relation: RevisionRelation, draft: String, revision: String, published: Date, stream: String,
      group: String?, intendedStatus: String?, stage: RevisionStage
    ) {
      self.relation = relation
      self.draft = draft
      self.revision = revision
      self.published = published
      self.stream = stream
      self.group = group
      self.intendedStatus = intendedStatus
      self.stage = stage
    }
  }

  public init(generatedAt: Date, revisions: [Int: [Revision]]) {
    self.version = Self.currentVersion
    self.generatedAt = generatedAt
    self.revisions = revisions
  }

  private enum CodingKeys: String, CodingKey {
    case version
    case generatedAt
    case revisions
  }

  /// Reads `version` first, and refuses a version this build does not know: a newer
  /// file may mean something an older reader would misread.
  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let version = try container.decode(Int.self, forKey: .version)
    guard version == Self.currentVersion else { throw VersionError.unknown(version) }
    self.version = version
    self.generatedAt = try container.decode(Date.self, forKey: .generatedAt)
    self.revisions = try container.decode([Int: [Revision]].self, forKey: .revisions)
  }

  public static func decode(_ data: Data) throws -> RFCRevisions {
    try decoder().decode(RFCRevisions.self, from: data)
  }

  public func encoded() throws -> Data {
    try Self.encoder().encode(self)
  }

  /// The coders of the revisions files, this one and the scanner's own record: ISO 8601
  /// dates, and sorted keys, so two runs over the same drafts write the same bytes.
  public static func encoder() -> JSONEncoder {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return encoder
  }

  public static func decoder() -> JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return decoder
  }
}

/// What a draft intends to do to an RFC. Top level rather than inside `Revision`,
/// which SwiftLint's nesting limit allows only one level deep.
public enum RevisionRelation: String, Codable, Sendable {
  case obsoletes
  case updates
}

/// How far along a draft is, from earliest to furthest. The scanner maps datatracker's
/// states onto it (`DraftStates` in RFCCorpusKit); the app words it
/// (`RevisionsSummary` in RFCReaderKit).
public enum RevisionStage: String, Codable, Sendable, CaseIterable, Comparable {
  case inGroup
  case lastCall
  case submitted
  case ietfLastCall
  case iesgReview
  case approved
  case rfcEditorQueue

  public static func < (lhs: RevisionStage, rhs: RevisionStage) -> Bool {
    allCases.firstIndex(of: lhs)! < allCases.firstIndex(of: rhs)!
  }
}
