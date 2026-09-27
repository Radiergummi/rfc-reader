import Foundation
import RFCKit

/// Everything the library derives from the RFC index, built together so it can be
/// built off the main actor.
///
/// Parsing the 14 MB index takes about a second, building its search about 50 ms,
/// and counting the working groups a few more. All three ran on the main actor
/// whenever the index was downloaded (#124). They are pure functions of the parsed
/// index and every part is `Sendable`, so they are made in one place, in a detached
/// task, and the main actor only assigns the result.
public struct PreparedIndex: Sendable {
  public let index: RFCIndex
  public let search: IndexSearch
  /// The working groups with the most RFCs, most first and equal counts by name, for
  /// the sidebar.
  public let topWorkingGroups: [String]

  public init(index: RFCIndex) {
    self.index = index
    self.search = IndexSearch(index: index)
    self.topWorkingGroups = Self.workingGroups(in: index)
  }

  /// Parses the index as the RFC Editor serves it, and prepares it.
  public static func parse(_ data: Data) throws -> PreparedIndex {
    PreparedIndex(index: try RFCIndexParser.parse(data))
  }

  private static func workingGroups(in index: RFCIndex) -> [String] {
    var counts: [String: Int] = [:]
    for rfc in index.rfcs {
      if let group = rfc.workingGroup { counts[group, default: 0] += 1 }
    }
    // By name within a count: dictionary order is randomized per process, so by
    // count alone the sidebar reordered its tied groups from launch to launch.
    let ranked = counts.sorted { lhs, rhs in
      lhs.value != rhs.value ? lhs.value > rhs.value : lhs.key < rhs.key
    }
    return ranked.prefix(12).map(\.key)
  }
}
