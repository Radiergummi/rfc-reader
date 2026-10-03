import Foundation
import RFCKit

/// The abbreviations the parser collects, across the corpus (#211): each document's,
/// keyed by its file's stem, and totals that say how many there are and which short
/// forms mean different things in different documents.
///
/// A measure, not a pack: nothing in the app reads it. It is what a precision check
/// of `Abbreviations` samples from before the reader shows an expansion (#67).
public struct AbbreviationReport: Encodable, Sendable {
  /// Each document's abbreviations, ordered by short form. A document with none is
  /// counted in the totals and left out here.
  public private(set) var documents: [String: [Abbreviation]] = [:]
  private var documentsRead = 0

  /// Enough short forms to see which are common and which are ambiguous; the counts
  /// in the totals stay exact.
  public static let shortFormLimit = 200

  public struct Totals: Encodable, Sendable {
    public var documentsRead: Int
    public var documentsWithAny: Int
    public var abbreviations: Int
    /// The most common short forms, by how many documents expand them.
    public var shortForms: [ShortForm]
  }

  public struct ShortForm: Encodable, Sendable {
    public var short: String
    public var documents: Int
    /// How many different expansions it has, ignoring case and spacing.
    public var expansions: Int
  }

  public init() {}

  public mutating func add(_ found: [String: Abbreviation], document: String) {
    documentsRead += 1
    guard !found.isEmpty else { return }
    documents[document] = found.values.sorted { $0.short < $1.short }
  }

  public var totals: Totals {
    var documentCounts: [String: Int] = [:]
    var expansions: [String: Set<String>] = [:]
    for abbreviation in documents.values.joined() {
      documentCounts[abbreviation.short, default: 0] += 1
      expansions[abbreviation.short, default: []].insert(Self.normalized(abbreviation.expansion))
    }
    let shortForms = documentCounts.map { short, count in
      ShortForm(short: short, documents: count, expansions: expansions[short]?.count ?? 0)
    }
    .sorted { ($1.documents, $0.short) < ($0.documents, $1.short) }
    return Totals(
      documentsRead: documentsRead,
      documentsWithAny: documents.count,
      abbreviations: documents.values.map(\.count).reduce(0, +),
      shortForms: Array(shortForms.prefix(Self.shortFormLimit)))
  }

  /// One expansion however it is cased or spaced.
  private static func normalized(_ expansion: String) -> String {
    expansion.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ")
  }

  private enum CodingKeys: String, CodingKey {
    case documents, totals
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(documents, forKey: .documents)
    try container.encode(totals, forKey: .totals)
  }
}
