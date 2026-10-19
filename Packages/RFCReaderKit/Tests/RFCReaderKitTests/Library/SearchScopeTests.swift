import Foundation
import RFCKit
import Testing

@testable import RFCReaderKit

/// The scope a search starts in, as Settings sets it (#713).
@Suite("Search scope")
struct SearchScopeTests {
  private let current = Fixtures.metadata(9110, currentStatus: .internetStandard, stream: .ietf)
  private let obsolete = Fixtures.metadata(
    2616, obsoletedBy: [.rfc(9110)], currentStatus: .draftStandard, stream: .ietf)
  private let historic = Fixtures.metadata(1945, currentStatus: .historic, stream: .ietf)
  private let independent = Fixtures.metadata(
    8962, currentStatus: .informational, stream: .independent)

  private func filters(_ query: String) -> SearchFilters {
    IndexSearch.parseQuery(query).filters
  }

  @Test func `everything is the default`() {
    #expect(SearchScope().isEverything)
    #expect(SearchScope().includes(.rfc(obsolete)))
  }

  @Test func `current only leaves out the obsoleted and the historic`() {
    let scope = SearchScope(currentOnly: true)
    #expect(scope.includes(.rfc(current)))
    #expect(scope.includes(.rfc(independent)))
    #expect(!scope.includes(.rfc(obsolete)))
    #expect(!scope.includes(.rfc(historic)))
  }

  @Test func `a stream leaves out the other streams`() {
    let scope = SearchScope(stream: .ietf)
    #expect(scope.includes(.rfc(current)))
    #expect(!scope.includes(.rfc(independent)))
  }

  /// A series row is the reader's own, a BCP bookmarked as itself: its members
  /// have statuses and streams, and it has none to leave out by.
  @Test func `a series row is always in scope`() {
    let row = LibraryRow.series(DocumentID(series: .bcp, number: 14), members: [obsolete])
    #expect(SearchScope(currentOnly: true, stream: .irtf).includes(row))
  }

  @Test func `a query naming its own status or stream wins`() {
    let scope = SearchScope(currentOnly: true, stream: .ietf)
    #expect(scope.leaving(filters("http")) == scope)
    #expect(scope.leaving(filters("status:historic http")) == SearchScope(stream: .ietf))
    // `status:current` leaves out the obsoleted only, so it widens nothing.
    #expect(scope.leaving(filters("status:current")) == scope)
    #expect(scope.leaving(filters("stream:irtf")) == SearchScope(currentOnly: true))
    #expect(scope.leaving(filters("status:info stream:iab")).isEverything)
  }

  @Test func `each part of a scope is a token of its own`() {
    let scope = SearchScope(currentOnly: true, stream: .ietf)
    #expect(scope.tokens(locale: .english).map(\.label) == ["Current Only", "Stream: IETF"])
    #expect(SearchScope().tokens(locale: .english).isEmpty)
  }

  @Test func `removing a token leaves the other part`() {
    let scope = SearchScope(currentOnly: true, stream: .ietf)
    #expect(scope.removing(.currentOnly) == SearchScope(stream: .ietf))
    #expect(scope.removing(.stream) == SearchScope(currentOnly: true))
  }
}
