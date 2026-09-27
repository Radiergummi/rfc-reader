import RFCKit
import Testing

@testable import RFCReaderKit

@Suite("List row label")
struct ListRowLabelTests {
  @Test func theDocumentComesFirstAndTheYearLast() {
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
  @Test func obsolescenceTheGroupAndTheBookmarkAreSpoken() {
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
}
