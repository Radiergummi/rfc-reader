import Foundation
import RFCKit
import Testing

@testable import RFCReaderKit

/// What a filter already says about every row it lists, which the row then leaves
/// out: PPPEXT's rows need not each say "pppext".
@Suite("Library filter: fixed fields")
struct LibraryFilterTests {
  @Test func `a working group's list fixes the group`() {
    #expect(LibraryFilter.workingGroup("pppext").fixesWorkingGroup)
    #expect(!LibraryFilter.workingGroup("pppext").fixesStatus)
  }

  @Test func `the standards and best current practices fix the status`() {
    #expect(LibraryFilter.standards.fixesStatus)
    #expect(LibraryFilter.bestCurrentPractice.fixesStatus)
    #expect(!LibraryFilter.standards.fixesWorkingGroup)
  }

  /// A stream holds many statuses and many groups, and the other lists any at all.
  @Test func `other lists fix nothing`() {
    for filter in [LibraryFilter.all, .recent, .bookmarks, .downloaded, .stream(.ietf)] {
      #expect(!filter.fixesStatus)
      #expect(!filter.fixesWorkingGroup)
    }
  }

  /// Everything in a collection is there because the reader put it there: it fixes
  /// no field, and the index cannot decide it.
  @Test func `a collection fixes nothing and the index cannot decide it`() {
    let filter = LibraryFilter.collection(UUID())
    #expect(!filter.fixesStatus)
    #expect(!filter.fixesWorkingGroup)
    let rfc = RFCMetadata(id: .rfc(9000), title: "QUIC", date: PublicationDate(year: 2021))
    #expect(filter.includes(rfc) == nil)
    #expect(!YearSections.apply(to: filter, query: ""))
  }
}
