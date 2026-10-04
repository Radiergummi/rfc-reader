import Foundation
import RFCKit
import Testing

@testable import RFCReaderKit

@Suite("Side-by-side pair")
struct SideBySidePairTests {
  private static func metadata(
    _ number: Int, obsoletes: [Int] = [], obsoletedBy: [Int] = []
  ) -> RFCMetadata {
    RFCMetadata(
      id: .rfc(number), title: "An Example", date: PublicationDate(year: 2020, month: 1),
      obsoletes: obsoletes.map(DocumentID.rfc), obsoletedBy: obsoletedBy.map(DocumentID.rfc))
  }

  @Test func `a document is offered beside its successors and then its predecessors`() {
    let offered = SideBySidePair.offered(
      for: Self.metadata(7230, obsoletes: [2616, 2145], obsoletedBy: [9110, 9112]))
    #expect(offered == [.rfc(9112), .rfc(9110), .rfc(2616), .rfc(2145)])
  }

  @Test func `a document naming itself is not offered beside itself`() {
    #expect(SideBySidePair.offered(for: Self.metadata(7230, obsoletes: [7230])).isEmpty)
  }

  @Test func `a document naming itself is no pair with itself`() {
    #expect(
      SideBySidePair(reading: Self.metadata(7230, obsoletedBy: [7230]), with: .rfc(7230)) == nil)
  }

  @Test func `the bar names the side that leads into a section with no counterpart`() {
    let pair = SideBySidePair(reading: Self.metadata(7231, obsoletedBy: [9110]), with: .rfc(9110))
    #expect(
      pair?.status(.aligned, holdingStill: .rfc(7231))
        == "This section of RFC 9110 has no counterpart in RFC 7231")
    #expect(
      pair?.status(.aligned, holdingStill: .rfc(9110))
        == "This section of RFC 7231 has no counterpart in RFC 9110")
    #expect(pair?.status(.aligned, holdingStill: nil) == "Scrolling with RFC 7231")
    #expect(pair?.status(.aligning, holdingStill: nil) == "Aligning sections with RFC 7231…")
  }

  @Test func `either document can be the one read`() {
    let fromOld = SideBySidePair(
      reading: Self.metadata(7231, obsoletedBy: [9110]), with: .rfc(9110))
    #expect(fromOld?.old == .rfc(7231))
    #expect(fromOld?.new == .rfc(9110))
    let fromNew = SideBySidePair(reading: Self.metadata(9110, obsoletes: [7231]), with: .rfc(7231))
    #expect(fromNew?.old == .rfc(7231))
    #expect(fromNew?.reading == .rfc(9110))
    #expect(fromNew?.other == .rfc(7231))
  }

  @Test func `documents without an obsoletes edge are no pair`() {
    #expect(SideBySidePair(reading: Self.metadata(7231), with: .rfc(3986)) == nil)
  }

  @Test func `the other edges of the two are aligned alongside where they are available`() {
    let pair = SideBySidePair(reading: Self.metadata(7230, obsoletedBy: [9110]), with: .rfc(9110))
    let among = pair?.alignedAmong(
      oldSuccessors: [.rfc(9110), .rfc(9112)],
      newPredecessors: [.rfc(7230), .rfc(7231), .rfc(2818)],
      available: [.rfc(9112), .rfc(7231)])
    #expect(among == [.rfc(7230), .rfc(9110), .rfc(7231), .rfc(9112)])
  }
}
