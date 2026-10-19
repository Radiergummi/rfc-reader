import Foundation
import Testing

@testable import RFCKit

/// The RFCs published on 1 April as jokes, which Settings ▸ Advanced can hide
/// (#713): a list curated by hand, so each entry is checked against the index
/// rather than the list being derived from it.
@Suite("April 1st RFCs")
struct AprilFirstRFCsTests {
  /// Whether `rfc` is the kind of document the list may hold: published on 1 April,
  /// Informational or Experimental. Some real RFCs were published on 1 April too,
  /// which is why the list is curated rather than this rule.
  static func isAprilFirstJoke(_ rfc: RFCMetadata) -> Bool {
    rfc.date.month == 4 && rfc.date.day == 1
      && [.informational, .experimental].contains(rfc.currentStatus)
  }

  @Test func `every listed RFC the sample index holds was published on 1 April`() throws {
    let index = try Fixtures.sampleIndex()
    let listed = AprilFirstRFCs.numbers.compactMap { index[$0] }

    // RFC 1149 is in the sample, so the check is not empty.
    #expect(!listed.isEmpty)
    for rfc in listed {
      #expect(Self.isAprilFirstJoke(rfc), "\(rfc.id.displayName)")
    }
  }

  @Test func `the classic examples are listed`() {
    for number in [1149, 2324, 2549] {
      #expect(AprilFirstRFCs.contains(.rfc(number)))
    }
  }

  @Test func `a series is never an April 1st RFC`() {
    #expect(!AprilFirstRFCs.contains(DocumentID(series: .bcp, number: 1149)))
  }
}

/// The whole list against the whole index, of which the sample holds one.
@Suite("Corpus-backed: April 1st RFCs", .enabled(if: CorpusIndex.isAvailable))
struct CorpusBackedAprilFirstRFCsTests {
  @Test func `every listed RFC was published on 1 April`() throws {
    let index = try CorpusIndex.index()
    for number in AprilFirstRFCs.numbers.sorted() {
      let rfc = try #require(index[number], "RFC \(number) is not in the index")
      #expect(AprilFirstRFCsTests.isAprilFirstJoke(rfc), "\(rfc.id.displayName)")
    }
  }
}
