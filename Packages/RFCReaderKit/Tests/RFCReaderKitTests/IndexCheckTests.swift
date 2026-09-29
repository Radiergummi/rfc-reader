import Foundation
import RFCKit
import Testing

@testable import RFCReaderKit

@Suite("Index check")
struct IndexCheckTests {
  private let checkedAt = Date(timeIntervalSince1970: 1_000_000)
  private let validators = CacheValidators(entityTag: #""abc""#, lastModified: nil)

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

  @Test func `validators of an index fetched within the week are sent`() {
    let check = IndexCheck(checkedAt: checkedAt, fetchedAt: checkedAt, validators: validators)
    let now = checkedAt.addingTimeInterval(IndexCheck.validatorLifetime - 60)
    #expect(check.validators(at: now) == validators)
  }

  @Test func `validators of an index fetched over a week ago are dropped`() {
    let check = IndexCheck(checkedAt: checkedAt, fetchedAt: checkedAt, validators: validators)
    let now = checkedAt.addingTimeInterval(IndexCheck.validatorLifetime + 60)
    #expect(check.validators(at: now) == nil)
  }

  @Test func `a recent check does not keep old validators alive`() {
    let now = checkedAt.addingTimeInterval(IndexCheck.validatorLifetime + 60)
    let check = IndexCheck(checkedAt: now, fetchedAt: checkedAt, validators: validators)
    #expect(check.validators(at: now) == nil)
  }

  @Test func `a check survives a round trip through JSON`() throws {
    let check = IndexCheck(checkedAt: checkedAt, fetchedAt: checkedAt, validators: validators)
    let decoded = try JSONDecoder().decode(IndexCheck.self, from: JSONEncoder().encode(check))
    #expect(decoded == check)
  }
}
