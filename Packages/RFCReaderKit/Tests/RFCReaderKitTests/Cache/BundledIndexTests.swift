import Foundation
import Testing

@testable import RFCReaderKit

/// The index a Release build bundles (#770), read until the app has one of its own.
@Suite("Bundled index")
struct BundledIndexTests {
  private let sandbox = DocumentStoreTests.Sandbox()

  /// A file standing in for the bundled index, written `age` ago.
  private func bundled(age: TimeInterval) throws -> URL {
    try FileManager.default.createDirectory(at: sandbox.root, withIntermediateDirectories: true)
    let url = sandbox.root.appending(path: "bundled-rfc-index.xml")
    try Data("<rfc-index/>".utf8).write(to: url)
    try FileManager.default.setAttributes(
      [.modificationDate: Date.now.addingTimeInterval(-age)], ofItemAtPath: url.path)
    return url
  }

  /// As current as when it was fetched, so the list does not say it was updated
  /// never, and the daily check replaces it once it is a day old.
  @Test func `with no index kept, the bundled one is read, dated when it was fetched`()
    throws
  {
    let bundled = try bundled(age: 3 * 86_400)
    let cached = try #require(sandbox.store().cachedIndexLocation(bundled: bundled))
    #expect(cached.url == bundled)
    let fetchedAt = try #require(
      bundled.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
    #expect(cached.updatedAt == fetchedAt)
    #expect(IndexCheck.isDue(checkedAt: cached.updatedAt, now: .now))
  }

  @Test func `an index kept is read rather than the bundled one`() throws {
    let bundled = try bundled(age: 0)
    try FileManager.default.createDirectory(
      at: sandbox.directory, withIntermediateDirectories: true)
    let kept = sandbox.directory.appending(path: "rfc-index.xml")
    try Data("<rfc-index/>".utf8).write(to: kept)
    let cached = try #require(sandbox.store().cachedIndexLocation(bundled: bundled))
    #expect(cached.url.standardizedFileURL == kept.standardizedFileURL)
  }

  @Test func `with neither, there is no index`() {
    #expect(sandbox.store().cachedIndexLocation(bundled: nil) == nil)
  }
}
