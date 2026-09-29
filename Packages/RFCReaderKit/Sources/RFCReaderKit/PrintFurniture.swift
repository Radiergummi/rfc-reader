import Foundation
import RFCKit

/// What a printed page says around the document: the title block the text opens
/// with, and the running header and footer every page carries (#375).
///
/// Laid out the way a published RFC's own pages are — the RFC's number, short title
/// and date across the top, its authors and page number across the foot — because
/// that is what someone holding a printed RFC expects to find there.
public struct PrintFurniture: Equatable, Sendable {
  public let headerLeading: String
  public let headerCenter: String
  public let headerTrailing: String
  public let footerLeading: String
  public let footerCenter: String

  /// The title block the printed text opens with.
  public let titleBlock: DocumentTextBuilder.TitleBlock

  /// - Parameters:
  ///   - header: the document's own header, which wins where both say something.
  ///   - metadata: the RFC index's entry, for what a legacy header does not carry.
  ///     The two are merged as the reader's header view merges them
  ///     (`HeaderSummary`), so the page and the screen say the same.
  public init(header: DocumentHeader, metadata: RFCMetadata?) {
    let summary = HeaderSummary(header: header, metadata: metadata)
    let id = header.id ?? metadata?.id
    let status = metadata?.currentStatus.displayName ?? header.category?.name

    headerLeading = id?.displayName ?? ""
    headerCenter = header.abbreviatedTitle ?? summary.title
    headerTrailing = summary.date ?? ""
    footerLeading = Self.byline(summary.authors)
    footerCenter = status ?? ""

    let identity = [id?.displayName, status, summary.date, summary.workingGroup]
      .compactMap { $0 }
      .filter { !$0.isEmpty }
    titleBlock = DocumentTextBuilder.TitleBlock(
      title: summary.title,
      details: [
        identity.joined(separator: " · "),
        summary.authors.map(\.displayName).joined(separator: ", "),
      ]
    )
  }

  /// `RFC 9110: HTTP Semantics`: what a print job is called, which the print
  /// panel's Save as PDF sheet offers as the file's title. Either half alone when
  /// the other is unknown.
  public static func documentTitle(id: DocumentID?, title: String?) -> String {
    [id?.displayName, title]
      .compactMap { $0 }
      .filter { !$0.isEmpty }
      .joined(separator: ": ")
  }

  /// The trailing end of the footer, as an RFC numbers its pages.
  public static func pageLabel(_ number: Int) -> String {
    "[Page \(number)]"
  }

  /// The authors as a page footer names them: one surname, two joined, or the
  /// first and "et al.".
  static func byline(_ authors: [Author]) -> String {
    let surnames = authors.map(\.surname).filter { !$0.isEmpty }
    switch surnames.count {
    case 0: return ""
    case 1: return surnames[0]
    case 2: return "\(surnames[0]) & \(surnames[1])"
    default: return "\(surnames[0]), et al."
    }
  }
}
