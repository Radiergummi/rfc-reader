import Foundation
import RFCKit
import Testing

@testable import RFCReaderKit

/// The errata feed kept beside the index (#387), with what identifies it, so the
/// daily check of an unchanged feed is a `304`.
@Suite("Errata store")
struct ErrataStoreTests {
  private let sandbox = DocumentStoreTests.Sandbox()
  private let validators = CacheValidators(entityTag: #""feed-1""#, lastModified: nil)

  @Test func `nothing is kept at first`() {
    let store = sandbox.store()
    #expect(store.cachedErrata() == nil)
    #expect(store.errataCheck() == nil)
  }

  @Test func `a stored feed is kept with its validators`() async throws {
    let store = sandbox.store()
    try FileManager.default.createDirectory(
      at: sandbox.directory, withIntermediateDirectories: true)
    try await store.storeErrata(Data("[]".utf8), validators: validators)
    #expect(store.cachedErrata() == Data("[]".utf8))
    let check = try #require(store.errataCheck())
    #expect(check.validators == validators)
  }

  /// An unchanged feed moves when it was checked, never when it was fetched, nor
  /// its validators.
  @Test func `an unchanged feed records only the check`() async throws {
    let store = sandbox.store()
    try FileManager.default.createDirectory(
      at: sandbox.directory, withIntermediateDirectories: true)
    try await store.storeErrata(Data("[]".utf8), validators: validators)
    let kept = try #require(store.errataCheck())
    try await Task.sleep(for: .milliseconds(20))
    try await store.recordUnchangedErrata(kept)
    let checked = try #require(store.errataCheck())
    #expect(checked.checkedAt > kept.checkedAt)
    #expect(checked.fetchedAt == kept.fetchedAt)
    #expect(checked.validators == validators)
  }
}
