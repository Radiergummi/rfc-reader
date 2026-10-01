import Foundation
import RFCKit

/// What a working group's card says (#363): the group as `groups.json` describes it,
/// and what the index has of its RFCs. Pure, so the view is only layout.
///
/// A group the file does not have — it has never been fetched, or datatracker does not
/// know the acronym — is shown by what the index has, its acronym and its RFCs, and
/// nothing more.
public struct WorkingGroupSummary: Sendable, Equatable {
  /// "HTTP"; the acronym in capitals when the file has no name for the group.
  public let title: String
  /// "HTTPBIS", under a title that is the group's name; nil when the title is it.
  public let acronym: String?
  /// What kind of group, its area and its state: "Working Group", "Web and Internet
  /// Transport", "Active".
  public let facts: [String]
  /// The current chairs, by name. None for a group that has concluded.
  public let chairs: [String]
  /// "93 RFCs, 1997–2026"; nil when the index has none.
  public let publications: String?
  public let links: [Link]

  public struct Link: Sendable, Equatable, Hashable {
    public let title: String
    public let url: URL
    /// An SF Symbol.
    public let symbol: String
  }

  /// - Parameter rfcs: the group's RFCs, as the list for its filter has them.
  public init(acronym: String, group: WorkingGroups.Group?, rfcs: [RFCMetadata]) {
    let capitals = acronym.uppercased()
    title = group?.name ?? capitals
    // Not said twice, for a group whose name is its acronym ("IAB").
    self.acronym = title.uppercased() == capitals ? nil : capitals
    facts =
      group.map {
        [Self.typeName($0.type), $0.area, Self.stateName($0.state)].compactMap { $0 }
      } ?? []
    chairs = group?.chairs ?? []
    publications = Self.publications(rfcs)
    links =
      group.map { group in
        [
          Link(title: "Datatracker", url: group.datatracker, symbol: "chart.bar.doc.horizontal"),
          group.charterPage.map { Link(title: "Charter", url: $0, symbol: "doc.text") },
          group.listArchive.map {
            Link(title: "Mailing List Archive", url: $0, symbol: "envelope")
          },
        ].compactMap { $0 }
      } ?? []
  }

  private static func publications(_ rfcs: [RFCMetadata]) -> String? {
    let years = rfcs.map(\.date.year)
    guard let first = years.min(), let latest = years.max() else { return nil }
    let count = rfcs.count == 1 ? "1 RFC" : "\(rfcs.count) RFCs"
    return first == latest ? "\(count), \(first)" : "\(count), \(first)–\(latest)"
  }

  /// Datatracker's name for a group type, for the slugs the index's groups have; any
  /// other, capitalized.
  private static func typeName(_ slug: String) -> String {
    switch slug {
    case "wg": "Working Group"
    case "rg": "Research Group"
    case "ag": "Area Group"
    case "area": "Area"
    case "team": "Team"
    case "dir": "Directorate"
    case "program": "IAB Program"
    case "iab": "IAB"
    case "irtf": "IRTF"
    case "ise": "Independent Submissions"
    default: slug.capitalized
    }
  }

  /// Datatracker's state, worded; "unknown" says nothing and is left out.
  private static func stateName(_ slug: String) -> String? {
    switch slug {
    case "active": "Active"
    case "conclude": "Concluded"
    case "bof": "BoF"
    case "bof-conc": "Concluded BoF"
    case "proposed": "Proposed"
    case "dormant": "Dormant"
    case "replaced": "Replaced"
    case "abandon": "Abandoned"
    case "unknown": nil
    default: slug.capitalized
    }
  }
}
