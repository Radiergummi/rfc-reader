import RFCKit

/// Which documents the RFC index says to fetch, in one of the corpus's two formats.
///
///   text  the 8,457 RFCs published before RFCXML, which `convert` then turns into
///         synthetic XML
///   xml   the 1,378 that were authored in RFCXML and need no conversion at all, so
///         they land straight in the XML directory beside the converted ones
///
/// `hasXMLSource` partitions the index, so the two never name the same document and
/// `manifest --dir xml.noindex` sees the union without being told.
public enum FetchPlan {
  /// The documents to fetch in `format`, in index order, at most `limit` of them. A few
  /// early RFCs exist only as PDF scans; there is nothing to fetch for them.
  public static func wanted(in index: RFCIndex, format: FileFormat, limit: Int?) -> [DocumentID] {
    let wanted = index.rfcs
      .filter {
        format == .xml ? $0.hasXMLSource : (!$0.hasXMLSource && $0.formats.contains(.text))
      }
      .map(\.id)
    guard let limit else { return wanted }
    return Array(wanted.prefix(limit))
  }

  /// The RFCs with XML whose text the RFC Editor also publishes, which xml2rfc
  /// generated from that XML: the ground truth `score` measures the legacy parser
  /// against (#42). `wanted(format: .text)` skips them on purpose, because they need
  /// no conversion, so they are fetched into a directory of their own.
  public static func pairedText(in index: RFCIndex, limit: Int?) -> [DocumentID] {
    let wanted = index.rfcs.filter { $0.hasXMLSource && $0.formats.contains(.text) }.map(\.id)
    guard let limit else { return wanted }
    return Array(wanted.prefix(limit))
  }
}
