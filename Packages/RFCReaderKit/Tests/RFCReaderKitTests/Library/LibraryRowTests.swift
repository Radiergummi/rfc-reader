import RFCKit
import Testing

@testable import RFCReaderKit

/// What a row of a library list says about its document, an RFC or a BCP, STD or
/// FYI bookmarked or read as itself (#321).
@Suite("Library row")
struct LibraryRowTests {
  private let bcp14 = DocumentID(series: .bcp, number: 14)
  private let older = Fixtures.metadata(
    2119, title: "Requirement Levels", year: 1997, month: 3, currentStatus: .bestCurrentPractice)
  private let newer = Fixtures.metadata(
    8174, title: "Uppercase Key Words", year: 2017, month: 5, currentStatus: .bestCurrentPractice)

  private var series: LibraryRow { .series(bcp14, members: [older, newer]) }

  @Test func `a series row is titled by its first member and names every member`() {
    #expect(series.title == "Requirement Levels")
    #expect(series.memberList == "RFC 2119, RFC 8174")
  }

  @Test func `a series row is dated by its newest member`() {
    #expect(series.date == PublicationDate(year: 2017, month: 5))
  }

  /// Obsolescence belongs to a member, not to the series.
  @Test func `a series row is never obsolete`() {
    let obsolete = Fixtures.metadata(2119, year: 1997, obsoletedBy: [.rfc(8174)])
    #expect(!LibraryRow.series(bcp14, members: [obsolete]).isObsolete)
  }

  @Test func `a series is a row only while the index knows a member of it`() {
    let index = RFCIndex(
      rfcs: [older],
      series: [
        SeriesEntry(id: bcp14, members: [.rfc(2119), .rfc(8174)]),
        SeriesEntry(id: DocumentID(series: .std, number: 99), members: [.rfc(9999)]),
      ])

    #expect(LibraryRow(bcp14, in: index)?.members.map(\.number) == [2119])
    #expect(LibraryRow(DocumentID(series: .std, number: 99), in: index) == nil)
    #expect(LibraryRow(.rfc(2119), in: index) == .rfc(older))
    #expect(LibraryRow(.rfc(1), in: index) == nil)
  }

  @Test func `an RFC row is its RFC`() {
    let row = LibraryRow.rfc(older)
    #expect(row.id == .rfc(2119))
    #expect(row.title == "Requirement Levels")
    #expect(row.memberList == nil)
    #expect(row.members == [older])
    #expect(row.rfc == older)
    #expect(series.rfc == nil)
  }

  @Test func `a series row is spoken with its members and no status`() {
    #expect(
      series.accessibilityLabel(isBookmarked: true, locale: .english)
        == "BCP 14, Requirement Levels, RFC 2119, RFC 8174, 2017, Bookmarked")
  }
}
