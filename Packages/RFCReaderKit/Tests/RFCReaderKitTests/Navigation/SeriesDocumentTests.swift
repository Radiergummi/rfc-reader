import Foundation
import RFCKit
import Testing

@testable import RFCReaderKit

/// A BCP, STD or FYI opened from its link keeps its identity, and its reader shows
/// its first member's text, titled with the series and its members (#656).
struct SeriesDocumentTests {
  private static let bcp14 = DocumentID(series: .bcp, number: 14)

  private let index = RFCIndex(
    rfcs: [Fixtures.metadata(2119), Fixtures.metadata(8174)],
    series: [
      SeriesEntry(id: bcp14, members: [.rfc(2119), .rfc(8174)]),
      SeriesEntry(id: DocumentID(series: .std, number: 99), members: []),
    ])

  @Test func `an RFC shows itself`() {
    #expect(index.documentShown(for: .rfc(2119)) == .rfc(2119))
  }

  @Test func `a series shows its first member`() {
    #expect(index.documentShown(for: Self.bcp14) == .rfc(2119))
  }

  /// One the index doesn't list, or lists with no members, has no document to show.
  @Test func `a series with no members shows nothing`() {
    #expect(index.documentShown(for: DocumentID(series: .std, number: 99)) == nil)
    #expect(index.documentShown(for: DocumentID(series: .fyi, number: 1)) == nil)
  }

  /// A bookmarked or open series keeps its members' bodies, offline and on disk: the
  /// series has none of its own.
  @Test func `a series stands for its members' bodies`() {
    #expect(
      index.withMembers(of: [Self.bcp14, .rfc(9110)])
        == [Self.bcp14, .rfc(2119), .rfc(8174), .rfc(9110)])
  }

  @Test func `a series' subtitle names its members`() {
    #expect(
      SeriesTitle.members(of: Self.bcp14, in: index, locale: .english) == "RFC 2119 and RFC 8174")
  }

  @Test func `an RFC has no members to name`() {
    #expect(SeriesTitle.members(of: .rfc(2119), in: index, locale: .english) == nil)
  }
}
