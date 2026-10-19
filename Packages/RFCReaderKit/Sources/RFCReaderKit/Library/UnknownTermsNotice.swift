import Foundation
import RFCKit

/// What an empty list says when its query names something unknown (#355): a dynamic
/// collection whose query uses a term this version or this index doesn't know, or a
/// search typed with one. Each term, as written, and why, so the reader can tell a
/// query that matches nothing from one that can't be read.
public struct UnknownTermsNotice: Equatable, Sendable {
  public let title: String
  /// A sentence per term, in the query's order.
  public let description: String

  /// Nil when `terms` is empty: the list is empty for another reason.
  public init?(_ terms: [UnknownSearchTerm], locale: Locale = .interface) {
    guard !terms.isEmpty else { return nil }
    title =
      terms.count == 1
      ? String(kit: "Unknown Search Term", locale: locale)
      : String(kit: "Unknown Search Terms", locale: locale)
    description = terms.map { Self.sentence(for: $0, locale: locale) }.joined(separator: " ")
  }

  private static func sentence(for term: UnknownSearchTerm, locale: Locale) -> String {
    let word = term.word
    return switch term.reason {
    case .qualifier:
      String(kit: "This version doesn’t know “\(word)”.", locale: locale)
    case .value:
      String(kit: "“\(word)” isn’t a value this version knows.", locale: locale)
    case .workingGroup:
      String(kit: "No working group in the index is named by “\(word)”.", locale: locale)
    case .collection:
      String(kit: "No collection is named by “\(word)”.", locale: locale)
    case .dynamicCollection:
      String(
        kit:
          "“\(word)” names a collection made from a query, which has no documents of its own to search in.",
        locale: locale)
    }
  }
}
