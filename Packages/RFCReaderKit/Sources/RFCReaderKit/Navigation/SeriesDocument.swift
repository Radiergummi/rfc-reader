import Foundation
import RFCKit

extension RFCIndex {
  /// The RFC whose text the reader shows for `id` (#656): an RFC itself, a BCP, STD
  /// or FYI its first member. The tab keeps the series as what it has open, so it is
  /// bookmarked and recorded as itself. Nil for a series this index doesn't list, or
  /// lists with no members.
  public func documentShown(for id: DocumentID) -> DocumentID? {
    guard id.series != .rfc else { return id }
    return series(id)?.members.first
  }

  /// `documents`, each series with its members beside it: the bodies a bookmark kept
  /// offline, or a series open in a window, stands for (#656). A series has no body of
  /// its own.
  public func withMembers(of documents: Set<DocumentID>) -> Set<DocumentID> {
    documents.union(
      documents.filter { $0.series != .rfc }.flatMap { series($0)?.members ?? [] })
  }
}

/// How a series' reader is titled (#656): "BCP 14", over the RFCs it names.
public enum SeriesTitle {
  /// "RFC 2119 and RFC 8174": the RFCs `id` names, for its reader's subtitle. Nil for
  /// an RFC, and for a series `index` doesn't list.
  public static func members(
    of id: DocumentID, in index: RFCIndex, locale: Locale = .interface
  ) -> String? {
    guard id.series != .rfc, let members = index.series(id)?.members, !members.isEmpty else {
      return nil
    }
    return members.map(\.displayName).formatted(.list(type: .and).locale(locale))
  }
}
