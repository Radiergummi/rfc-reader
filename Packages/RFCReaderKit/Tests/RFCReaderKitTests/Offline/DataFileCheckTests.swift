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
}
