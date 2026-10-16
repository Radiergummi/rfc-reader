import Foundation
import RFCKit
import Testing

@testable import RFCReaderKit

/// What a refresh of the index does with the RFC Editor's answer (#314).
@Suite("Index refresh outcome")
struct IndexRefreshOutcomeTests {
  private let validators = CacheValidators(entityTag: #""abc""#, lastModified: nil)
  private var kept: IndexCheck {
    IndexCheck(
      checkedAt: Date(timeIntervalSince1970: 0), fetchedAt: Date(timeIntervalSince1970: 0),
      validators: validators)
  }

  @Test func `an unchanged index that is kept is recorded as checked`() {
    #expect(IndexRefreshOutcome(.unchanged, kept: kept) == .recordUnchanged(kept))
  }

  /// A `304` answers only a request that sent validators, which come from the index
  /// kept: one that answers none leaves no index to wait for.
  @Test func `an unchanged answer with nothing kept settles`() {
    #expect(IndexRefreshOutcome(.unchanged, kept: nil) == .settle)
  }

  @Test func `a changed index is installed, kept or not`() {
    let data = Data("index".utf8)
    #expect(
      IndexRefreshOutcome(.changed(data, validators), kept: kept)
        == .install(data, validators: validators))
    #expect(
      IndexRefreshOutcome(.changed(data, nil), kept: nil) == .install(data, validators: nil))
  }
}
