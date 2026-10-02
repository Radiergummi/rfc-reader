import Foundation
import RFCKit

/// The iOS list's sections by year of publication, as Notes sections its lists by
/// date (#347).
public enum YearSections {
  public struct Section: Identifiable, Sendable {
    public let year: Int
    public let rows: [LibraryRow]

    public var id: Int { year }
  }

  /// Whether a list is sectioned: one the index decides, unsearched. Recently Read
  /// is in reading order and a search in order of relevance; Bookmarks, Available
  /// Offline and a series are the reader's own lists or short ones, and stay
  /// unsectioned for now.
  public static func apply(to filter: LibraryFilter, query: String) -> Bool {
    guard query.isUnsearchedQuery else { return false }
    switch filter {
    case .all, .standards, .bestCurrentPractice, .stream, .workingGroup: return true
    case .recent, .bookmarks, .downloaded, .series, .collection: return false
    }
  }

  /// `rows` by year, the years in the order they first appear and each year's rows
  /// in the order given.
  ///
  /// By year rather than in runs: numbers are assigned before publication, so a list
  /// in number order can put a year out of place, and a second header for it would
  /// read as a bug.
  public static func sections(of rows: some Sequence<LibraryRow>) -> [Section] {
    var years: [Int] = []
    var rowsByYear: [Int: [LibraryRow]] = [:]
    for row in rows {
      let year = row.date.year
      if rowsByYear[year] == nil { years.append(year) }
      rowsByYear[year, default: []].append(row)
    }
    return years.map { Section(year: $0, rows: rowsByYear[$0] ?? []) }
  }
}
