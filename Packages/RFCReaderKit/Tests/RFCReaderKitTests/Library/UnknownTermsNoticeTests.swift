import Foundation
import RFCKit
import Testing

@testable import RFCReaderKit

/// What an empty list says when its query names something unknown (#355): which term,
/// and why, rather than "No Results".
@Suite("Unknown terms notice")
struct UnknownTermsNoticeTests {
  @Test(arguments: [
    (UnknownSearchTerm.Reason.qualifier, "published:2024", "This version doesn’t know “published:2024”."),
    (.value, "status:nonsense", "“status:nonsense” isn’t a value this version knows."),
    (.workingGroup, "wg:gone", "No working group in the index is named by “wg:gone”."),
    (.collection, #"in:"Gone""#, "No collection is named by “in:\"Gone\"”."),
    (
      .dynamicCollection, #"in:"QUIC""#,
      "“in:\"QUIC\"” names a collection made from a query, which has no documents of its own to search in."
    ),
  ])
  func `each reason says why`(reason: UnknownSearchTerm.Reason, word: String, sentence: String) {
    let notice = UnknownTermsNotice(
      [UnknownSearchTerm(word: word, reason: reason)], locale: .english)
    #expect(notice?.title == "Unknown Search Term")
    #expect(notice?.description == sentence)
  }

  @Test func `several terms are a sentence each`() {
    let notice = UnknownTermsNotice(
      [
        UnknownSearchTerm(word: "released:2024", reason: .qualifier),
        UnknownSearchTerm(word: "wg:gone", reason: .workingGroup),
      ], locale: .english)
    #expect(notice?.title == "Unknown Search Terms")
    #expect(
      notice?.description
        == "This version doesn’t know “released:2024”. No working group in the index is named by “wg:gone”."
    )
  }

  @Test func `no unknown term is no notice`() {
    #expect(UnknownTermsNotice([], locale: .english) == nil)
  }
}
