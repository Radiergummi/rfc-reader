import Foundation
import RFCKit
import Testing

@testable import RFCReaderKit

@Suite("Index check")
struct IndexCheckTests {
  private let checkedAt = Date(timeIntervalSince1970: 1_000_000)

  @Test func `an index checked within the day is not due`() {
    let now = checkedAt.addingTimeInterval(IndexCheck.interval - 60)
    #expect(!IndexCheck.isDue(checkedAt: checkedAt, now: now))
  }

  @Test func `an index checked more than a day ago is due`() {
    let now = checkedAt.addingTimeInterval(IndexCheck.interval + 60)
    #expect(IndexCheck.isDue(checkedAt: checkedAt, now: now))
  }

  @Test func `an index that was never checked is due`() {
    #expect(IndexCheck.isDue(checkedAt: .distantPast, now: checkedAt))
  }

  @Test func `a check survives a round trip through JSON`() throws {
    let check = IndexCheck(
      checkedAt: checkedAt,
      validators: CacheValidators(entityTag: #""abc""#, lastModified: nil))
    let decoded = try JSONDecoder().decode(IndexCheck.self, from: JSONEncoder().encode(check))
    #expect(decoded == check)
  }
}
