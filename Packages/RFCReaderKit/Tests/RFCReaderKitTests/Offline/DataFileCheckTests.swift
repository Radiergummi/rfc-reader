import Foundation
import Testing

@testable import RFCReaderKit

/// When the revisions, the working groups and the errata are fetched again (#314,
/// #363, #387).
@Suite("Data file check")
struct DataFileCheckTests {
  private let now = Date(timeIntervalSince1970: 1_800_000_000)

  @Test func `a file this launch has not fetched is due`() {
    #expect(DataFileCheck.isDue(fetchedAt: nil, now: now))
  }

  @Test func `a file fetched within the day is not due`() {
    #expect(!DataFileCheck.isDue(fetchedAt: now - IndexCheck.interval + 60, now: now))
  }

  @Test func `a file fetched a day ago is due`() {
    #expect(DataFileCheck.isDue(fetchedAt: now - IndexCheck.interval, now: now))
  }

  @Test func `errata never kept nor asked for are due`() {
    #expect(DataFileCheck.isErrataDue(keptCheckedAt: nil, askedAt: nil, now: now))
  }

  @Test func `errata kept and checked within the day are not due`() {
    #expect(!DataFileCheck.isErrataDue(keptCheckedAt: now - 60, askedAt: nil, now: now))
  }

  /// A feed that fails to decode or to be kept records no check, and would
  /// otherwise be downloaded again at every activation.
  @Test func `errata asked for within the day are not due, whatever was kept`() {
    let dayAgo = now - IndexCheck.interval - 60
    #expect(!DataFileCheck.isErrataDue(keptCheckedAt: dayAgo, askedAt: now - 60, now: now))
    #expect(!DataFileCheck.isErrataDue(keptCheckedAt: nil, askedAt: now - 60, now: now))
  }

  @Test func `errata kept and asked for over a day ago are due`() {
    let dayAgo = now - IndexCheck.interval - 60
    #expect(DataFileCheck.isErrataDue(keptCheckedAt: dayAgo, askedAt: dayAgo, now: now))
  }

  // MARK: - Revisions and working groups, by the copy kept (#758)

  /// Nothing to show without it, so a phone network will do.
  @Test func `a file never kept nor fetched is fetched on any network`() {
    #expect(DataFileCheck.fetch(keptAt: nil, fetchedAt: nil, now: now) == .anyNetwork)
  }

  /// A new launch has fetched nothing yet, and the copy kept still counts.
  @Test func `a file kept within the day is not fetched`() {
    #expect(DataFileCheck.fetch(keptAt: now - 60, fetchedAt: nil, now: now) == nil)
  }

  /// The copy kept answers meanwhile, so nobody is waiting for the refresh.
  @Test func `a file kept a day ago is refreshed on a cheap network`() {
    let dayAgo = now - IndexCheck.interval
    #expect(DataFileCheck.fetch(keptAt: dayAgo, fetchedAt: nil, now: now) == .cheapNetworks)
  }

  /// A fetch whose copy could not be kept: not fetched again at every activation.
  @Test func `a file fetched within the day is not fetched, whatever was kept`() {
    let dayAgo = now - IndexCheck.interval - 60
    #expect(DataFileCheck.fetch(keptAt: dayAgo, fetchedAt: now - 60, now: now) == nil)
    #expect(DataFileCheck.fetch(keptAt: nil, fetchedAt: now - 60, now: now) == nil)
  }

  @Test func `a file neither kept nor fetched within the day is fetched`() {
    let dayAgo = now - IndexCheck.interval - 60
    #expect(DataFileCheck.fetch(keptAt: nil, fetchedAt: dayAgo, now: now) == .anyNetwork)
    #expect(DataFileCheck.fetch(keptAt: dayAgo, fetchedAt: dayAgo, now: now) == .cheapNetworks)
  }
}
