import RFCKit
import Testing

@testable import RFCReaderKit

@Suite("List row label")
struct ListRowLabelTests {
  @Test func `the document comes first and the year last`() {
    let metadata = RFCMetadata(
      id: DocumentID(series: .rfc, number: 9110),
      title: "HTTP Semantics",
      date: PublicationDate(year: 2022, month: 6),
      currentStatus: .internetStandard
    )
    #expect(
      metadata.accessibilityLabel(isBookmarked: false)
        == "RFC 9110, HTTP Semantics, Internet Standard, 2022")
  }

  /// What the row shows only as a badge, a group name or a glyph is spoken too.
  @Test func `obsolescence the group and the bookmark are spoken`() {
    let metadata = RFCMetadata(
      id: DocumentID(series: .rfc, number: 2616),
      title: "Hypertext Transfer Protocol -- HTTP/1.1",
      date: PublicationDate(year: 1999, month: 6),
      obsoletedBy: [DocumentID(series: .rfc, number: 7230)],
      currentStatus: .draftStandard,
      workingGroup: "http"
    )
    #expect(
      metadata.accessibilityLabel(isBookmarked: true)
        == "RFC 2616, Hypertext Transfer Protocol -- HTTP/1.1, Draft Standard, Obsolete, Working group http, 1999, Bookmarked"
    )
  }

  /// The index's placeholder for "no group" is not a group's name.
  @Test func `the index placeholder for no group is not spoken as a group`() {
    let metadata = RFCMetadata(
      id: DocumentID(series: .rfc, number: 2119),
      title: "Key words for use in RFCs to Indicate Requirement Levels",
      date: PublicationDate(year: 1997, month: 3),
      currentStatus: .bestCurrentPractice,
      workingGroup: "NON WORKING GROUP"
    )
    #expect(
      metadata.accessibilityLabel(isBookmarked: false)
        == "RFC 2119, Key words for use in RFCs to Indicate Requirement Levels, Best Current Practice, 1997"
    )
  }
}
