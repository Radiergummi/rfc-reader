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
  public init(header: DocumentHeader, metadata: RFCMetadata?) {
    let id = header.id ?? metadata?.id
    let date = (header.date ?? metadata?.date)?.formatted
    let authors = header.authors.isEmpty ? (metadata?.authors ?? []) : header.authors
    let status = metadata?.currentStatus.displayName ?? header.category

    headerLeading = id?.displayName ?? ""
    headerCenter = header.abbreviatedTitle ?? header.title
    headerTrailing = date ?? ""
    footerLeading = Self.byline(authors)
    footerCenter = status ?? ""

    let identity = [
      id?.displayName, status, date, header.workingGroup ?? metadata?.workingGroup,
    ]
    .compactMap { $0 }
    .filter { !$0.isEmpty }
    titleBlock = DocumentTextBuilder.TitleBlock(
      title: header.title,
      details: [
        identity.joined(separator: " · "),
        authors.map(\.name).joined(separator: ", "),
      ]
    )
  }

  /// The trailing end of the footer, as an RFC numbers its pages.
  public static func pageLabel(_ number: Int) -> String {
    "[Page \(number)]"
  }

  /// The authors as a page footer names them: one surname, two joined, or the
  /// first and "et al.".
  static func byline(_ authors: [Author]) -> String {
    let surnames = authors.map { surname(of: $0.name) }.filter { !$0.isEmpty }
    switch surnames.count {
    case 0: return ""
    case 1: return surnames[0]
    case 2: return "\(surnames[0]) & \(surnames[1])"
    default: return "\(surnames[0]), et al."
    }
  }

  /// The last word of a name, leaving out a trailing role: "R. Fielding, Ed." is
  /// "Fielding".
  static func surname(of name: String) -> String {
    let withoutRole = name.split(separator: ",").first.map(String.init) ?? name
    return withoutRole.split(separator: " ").last.map(String.init) ?? ""
  }
}
