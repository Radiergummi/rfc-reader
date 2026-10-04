import Foundation

/// The RFCs an App Intent's RFC entity stands for (#192): what Siri heard or a
/// Shortcut was given, and the identifiers Spotlight and Shortcuts hand back.
///
/// Pure functions of the index, so an intent answers offline, and is tested here
/// rather than in the app.
public enum DocumentLookup {
  /// The RFCs `query` names. A number in any spelling `DocumentID(parsing:)` reads
  /// names that RFC alone, and a series its members: Siri asking which of RFC 9110
  /// and RFC 91100 was meant would be asking for nothing. Anything else, a number
  /// the index lacks included, is searched as the sidebar searches it.
  public static func rfcs(matching query: String, in search: IndexSearch, limit: Int = 20)
    -> [RFCMetadata]
  {
    let index = search.index
    if let id = DocumentID(parsing: query) {
      if let rfc = index[id] { return [rfc] }
      if let series = index.series(id) { return series.members.compactMap { index[$0] } }
    }
    return search.search(query, limit: limit).map(\.rfc)
  }

  /// The RFCs `identifiers` name, each a file stem (`rfc9110`), in the order given.
  /// One the index lacks, or that is no RFC's stem, is left out.
  public static func rfcs(identifiedBy identifiers: [String], in index: RFCIndex) -> [RFCMetadata] {
    identifiers.compactMap { DocumentID(fileStem: $0).flatMap { index[$0] } }
  }
}

extension RFCMetadata {
  /// `Obsoleted by RFC 9110`, or nil for an RFC that is current.
  public var obsoletionNote: String? {
    guard isObsolete else { return nil }
    return "Obsoleted by \(obsoletedBy.map(\.displayName).joined(separator: ", "))"
  }
}
