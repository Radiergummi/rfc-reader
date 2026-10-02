import Foundation

/// `groups.json` (#363): the groups the RFC index names, as datatracker describes them
/// — name, type, state, area, current chairs and where their mail is archived.
/// `corpus-build groups` writes it daily beside `revisions.json`, and the app reads it
/// for a working group's card. Both sides encode and decode through `encoded()` and
/// `decode(_:)`, the revisions file's coders, so they agree on dates and keys.
public struct WorkingGroups: Codable, Sendable, Equatable {
  /// The only version this build reads. Bumped on any change a reader of an older
  /// version would misread.
  public static let currentVersion = 1

  public enum VersionError: Error, Equatable {
    case unknown(Int)
  }

  public var version: Int
  /// When the run that wrote the file started.
  public var generatedAt: Date
  /// By acronym, in lower case, as datatracker keeps it.
  public var groups: [String: Group]

  public struct Group: Codable, Sendable, Equatable {
    /// "httpbis".
    public var acronym: String
    /// "HTTP".
    public var name: String
    /// Datatracker's type slug: "wg", "rg", "ag", "team"…
    public var type: String
    /// Datatracker's state slug: "active", "conclude", "bof-conc"…
    public var state: String
    /// The area's name, "Web and Internet Transport", for a group in one.
    public var area: String?
    /// The current chairs, by name. None for a group that has concluded.
    public var chairs: [String]
    /// Where the group's mailing list is archived.
    public var listArchive: URL?
    /// The charter's document name, "charter-ietf-httpbis".
    public var charter: String?

    public init(
      acronym: String, name: String, type: String, state: String, area: String?,
      chairs: [String], listArchive: URL?, charter: String?
    ) {
      self.acronym = acronym
      self.name = name
      self.type = type
      self.state = state
      self.area = area
      self.chairs = chairs
      self.listArchive = listArchive
      self.charter = charter
    }

    /// The group's page on datatracker, which works for every type of group.
    public var datatracker: URL {
      RFCEditorEndpoints.datatrackerBase.appending(path: "group/\(acronym)/about/")
    }

    /// The charter's page on datatracker; nil for a group without one.
    public var charterPage: URL? {
      charter.map { RFCEditorEndpoints.datatrackerDraft($0) }
    }
  }

  /// Keyed by each group's acronym in lower case; of two with one acronym, the last.
  public init(generatedAt: Date, groups: [Group]) {
    self.version = Self.currentVersion
    self.generatedAt = generatedAt
    self.groups = Dictionary(
      groups.map { ($0.acronym.lowercased(), $0) }, uniquingKeysWith: { $1 })
  }

  /// The group the index names `acronym`, in whatever case it writes it.
  public func group(_ acronym: String) -> Group? {
    groups[acronym.lowercased()]
  }

  private enum CodingKeys: String, CodingKey {
    case version
    case generatedAt
    case groups
  }

  /// Reads `version` first, and refuses a version this build does not know.
  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let version = try container.decode(Int.self, forKey: .version)
    guard version == Self.currentVersion else { throw VersionError.unknown(version) }
    self.version = version
    self.generatedAt = try container.decode(Date.self, forKey: .generatedAt)
    self.groups = try container.decode([String: Group].self, forKey: .groups)
  }

  public static func decode(_ data: Data) throws -> WorkingGroups {
    try RFCRevisions.decoder().decode(WorkingGroups.self, from: data)
  }

  public func encoded() throws -> Data {
    try RFCRevisions.encoder().encode(self)
  }
}
