import Foundation
import RFCKit

/// The pieces of datatracker's API the revisions scanner reads, and where. Measured
/// against the live API on 29 September 2026; none needs authentication.
public enum Datatracker {
  private static let base = RFCEditorEndpoints.datatrackerBase

  /// Every active draft in a stream, a hundred at a time. The rest follow `meta.next`.
  /// Ordered by ID: unordered, each page is a query of its own, and a draft could land
  /// on two pages or none. `name` does not allow ordering.
  public static let draftsFirstPage = base.appending(path: "api/v1/doc/document/")
    .appending(queryItems: [
      URLQueryItem(name: "format", value: "json"),
      URLQueryItem(name: "limit", value: "100"),
      URLQueryItem(name: "order_by", value: "id"),
      URLQueryItem(name: "type", value: "draft"),
      URLQueryItem(name: "states__type", value: "draft"),
      URLQueryItem(name: "states__slug", value: "active"),
      URLQueryItem(name: "stream__isnull", value: "false"),
    ])

  /// Every document state, about 180 of them: one or two pages.
  public static let statesFirstPage = base.appending(path: "api/v1/doc/state/")
    .appending(queryItems: [
      URLQueryItem(name: "format", value: "json"),
      URLQueryItem(name: "limit", value: "500"),
    ])

  /// The page after this one, from `meta.next`, which is a path and query.
  public static func next(_ next: String?) -> URL? {
    next.flatMap { URL(string: $0, relativeTo: base)?.absoluteURL }
  }

  /// A draft's record: group, intended status, and when each revision was posted.
  public static func record(_ name: String) -> URL {
    RFCEditorEndpoints.datatrackerDraft(name).appending(path: "doc.json")
  }

  /// A revision in the archive: `xml` where the draft was submitted as XML, `txt`
  /// always.
  public static func draft(_ name: String, rev: String, extension: String) -> URL {
    URL(string: "https://www.ietf.org/archive/id/\(name)-\(rev).\(`extension`)")!
  }

  /// Datatracker writes dates as `2025-12-01T18:27:41.095128+00:00`, and without
  /// the fraction for old revisions. The fraction is dropped: a second is precise
  /// enough to date a revision.
  public static func decoder() -> JSONDecoder {
    let decoder = JSONDecoder()
    // `intended_std_level`, `rev_history`.
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    decoder.dateDecodingStrategy = .custom { decoder in
      let container = try decoder.singleValueContainer()
      let string = try container.decode(String.self)
      let formatter = ISO8601DateFormatter()
      formatter.formatOptions = [.withInternetDateTime]
      guard let date = formatter.date(from: string.replacing(/\.\d+/, with: "")) else {
        throw DecodingError.dataCorruptedError(
          in: container, debugDescription: "not an ISO 8601 date: \(string)")
      }
      return date
    }
    return decoder
  }

  public struct Meta: Decodable, Sendable {
    public var next: String?
  }

  /// A page of a listing, which says where the next one is.
  public protocol Page: Decodable, Sendable {
    var meta: Meta { get }
  }

  public struct DraftPage: Page {
    public var meta: Meta
    public var objects: [ListedDraft]
  }

  /// A draft as the listing has it: enough to decide what to read again.
  public struct ListedDraft: Decodable, Sendable, Equatable {
    public var name: String
    public var rev: String
    /// Resource URIs, "/api/v1/doc/state/150/".
    public var states: [String]
    /// "/api/v1/name/streamname/ietf/".
    public var stream: String?

    public init(name: String, rev: String, states: [String], stream: String?) {
      self.name = name
      self.rev = rev
      self.states = states
      self.stream = stream
    }

    /// Sorted, so two listings of the same states compare equal.
    public var stateIDs: [Int] {
      states.compactMap { Int(Datatracker.lastComponent(of: $0)) }.sorted()
    }

    /// "ietf", "irtf", "iab", "ise" or "editorial".
    public var streamSlug: String? {
      stream.map(Datatracker.lastComponent(of:))
    }

    /// The states the table knows. One it does not know is left out, and the stage
    /// falls back as it would for any unknown state.
    public func states(in table: [Int: DraftState]) -> [DraftState] {
      stateIDs.compactMap { table[$0] }
    }
  }

  public struct StatePage: Page {
    public var meta: Meta
    public var objects: [State]
  }

  public struct State: Decodable, Sendable {
    public var id: Int
    /// "/api/v1/doc/statetype/draft-iesg/".
    public var type: String
    public var slug: String
  }

  public static func stateTable(_ pages: [StatePage]) -> [Int: DraftState] {
    var table: [Int: DraftState] = [:]
    for state in pages.flatMap(\.objects) {
      table[state.id] = DraftState(lastComponent(of: state.type), state.slug)
    }
    return table
  }

  /// `doc/<name>/doc.json`, the parts the scanner keeps.
  public struct DraftRecord: Decodable, Sendable {
    public var group: Group?
    /// `intended_std_level`, "Proposed Standard".
    public var intendedStdLevel: String?
    public var revHistory: [Posted]

    /// Nil for a draft in no group, which datatracker calls "none".
    public var groupAcronym: String? {
      group.flatMap { $0.acronym == "none" ? nil : $0.acronym }
    }

    public func published(rev: String) -> Date? {
      revHistory.last { $0.rev == rev }?.published
    }
  }

  public struct Group: Decodable, Sendable {
    public var acronym: String
  }

  /// One revision in a record's `rev_history`.
  public struct Posted: Decodable, Sendable {
    public var rev: String
    public var published: Date
  }

  /// "/api/v1/doc/state/150/" → "150".
  static func lastComponent(of uri: String) -> String {
    uri.split(separator: "/").last.map(String.init) ?? uri
  }
}
