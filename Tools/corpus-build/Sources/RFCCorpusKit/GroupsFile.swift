import Foundation
import RFCKit

/// What `corpus-build groups` makes of datatracker's groups (#363): `groups.json`, the
/// groups the RFC index names, each with its area and current chairs. Pure, so the
/// mapping is tested apart from the requests.
public enum GroupsFile {
  /// Each group's chairs, as person URIs, in the order the roles are listed.
  public static func chairs(_ roles: [Datatracker.Role]) -> [Int: [String]] {
    var chairs: [Int: [String]] = [:]
    for role in roles {
      guard let group = role.groupID else { continue }
      chairs[group, default: []].append(role.person)
    }
    return chairs
  }

  /// The people whose names the file needs: the chairs of the active groups the index
  /// names, each once, sorted so that two runs ask in the same order.
  public static func peopleToFetch(
    groups: [Datatracker.ListedGroup], named: Set<String>, chairs: [Int: [String]]
  ) -> [String] {
    let kept = Self.kept(groups, named: named).filter { $0.stateSlug == "active" }
    return Set(kept.flatMap { chairs[$0.id] ?? [] }).sorted()
  }

  /// The file: every group `named` names, in any case, with the name of its parent
  /// when that is an area, and the names of its chairs when it is active. A chair whose
  /// name could not be fetched is left out rather than shown as a URI.
  public static func build(
    groups: [Datatracker.ListedGroup], named: Set<String>, chairs: [Int: [String]],
    people: [String: String], generatedAt: Date
  ) -> WorkingGroups {
    let byID = Dictionary(groups.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    let file = kept(groups, named: named).map { group in
      let parent = group.parentID.flatMap { byID[$0] }
      let isActive = group.stateSlug == "active"
      return WorkingGroups.Group(
        acronym: group.acronym, name: group.name, type: group.typeSlug, state: group.stateSlug,
        area: parent?.typeSlug == "area" ? parent?.name : nil,
        chairs: isActive ? (chairs[group.id] ?? []).compactMap { people[$0] }.sorted() : [],
        listArchive: group.archive, charter: group.charterName)
    }
    return WorkingGroups(generatedAt: generatedAt, groups: file)
  }

  /// False when `next` has lost more than half the groups of a `previous` that had at
  /// least ten: the groups the index names only grow, and a broken query loses them.
  public static func mayPublish(
    _ next: WorkingGroups, replacing previous: WorkingGroups?, allowShrink: Bool
  ) -> Bool {
    guard let previous, !allowShrink, previous.groups.count >= 10 else { return true }
    return next.groups.count * 2 >= previous.groups.count
  }

  private static func kept(_ groups: [Datatracker.ListedGroup], named: Set<String>)
    -> [Datatracker.ListedGroup]
  {
    let wanted = Set(named.map { $0.lowercased() })
    return groups.filter { wanted.contains($0.acronym.lowercased()) }
  }
}
