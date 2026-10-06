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

  /// - Parameter locale: what the date is written in: the interface's language for
  ///   the reader's header, English for print and PDF, which frame the English body.
  public init(header: DocumentHeader, metadata: RFCMetadata?, locale: Locale = .interface) {
    title = header.title
    date = (header.date ?? metadata?.date)?.formatted(in: locale)
    workingGroup = header.workingGroup ?? metadata?.workingGroup
    authors = header.authors.isEmpty ? (metadata?.authors ?? []) : header.authors
  }
}
