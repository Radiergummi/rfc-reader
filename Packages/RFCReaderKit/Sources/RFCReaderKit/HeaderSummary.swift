import Foundation
import RFCKit

/// What a document's heading says about it, with the document's own header and
/// the RFC index's entry merged into one answer: the reader's header view shows
/// it, and a printed page's title block and running furniture say the same (#375).
///
/// The document wins where it says something. The index fills in what a legacy
/// header does not carry — most often the date, the working group and the authors.
public struct HeaderSummary: Equatable, Sendable {
  public let title: String
  /// `June 2022`, or the year alone when the month is unknown.
  public let date: String?
  public let workingGroup: String?
  public let authors: [Author]

  public init(header: DocumentHeader, metadata: RFCMetadata?) {
    title = header.title
    date = (header.date ?? metadata?.date)?.formatted
    workingGroup = header.workingGroup ?? metadata?.workingGroup
    authors = header.authors.isEmpty ? (metadata?.authors ?? []) : header.authors
  }
}
