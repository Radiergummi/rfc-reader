import Foundation
import RFCKit
import Testing

@testable import RFCReaderKit

@Suite("Index snapshot")
struct IndexSnapshotTests {
  private let index = Date(timeIntervalSince1970: 1_000)

  @Test func `a snapshot decodes to the index it was made from`() throws {
    let parsed = try RFCIndexParser.parse(Fixtures.rfcKitData("rfc-index-sample.xml"))
    let decoded = try IndexSnapshot.decode(IndexSnapshot.encode(parsed))
    #expect(decoded.rfcs == parsed.rfcs)
    #expect(decoded.series == parsed.series)
  }

  @Test func `a snapshot written after the index is current`() {
    let written = Date(timeIntervalSince1970: 3_000)
    #expect(IndexSnapshot.isCurrent(written: written, index: index))
  }

  @Test func `a snapshot older than the index is stale`() {
    let written = Date(timeIntervalSince1970: 500)
    #expect(!IndexSnapshot.isCurrent(written: written, index: index))
  }

  @Test func `no snapshot is not current`() {
    #expect(!IndexSnapshot.isCurrent(written: nil, index: index))
  }

  // MARK: - The build that wrote it (#758)

  @Test func `each build names its snapshot differently`() {
    let first = IndexSnapshot.fileName(build: "1 783456789.123456")
    #expect(first == IndexSnapshot.fileName(build: "1 783456789.123456"))
    #expect(first != IndexSnapshot.fileName(build: "1 783456790.5"))
    #expect(first != IndexSnapshot.fileName(build: "2 783456789.123456"))
    #expect(IndexSnapshot.isSnapshot(fileName: first))
  }

  @Test func `a build's snapshot name is one file name`() {
    let name = IndexSnapshot.fileName(build: "1 783456789.123456/..")
    #expect(!name.contains("/"))
    #expect(!name.contains(" "))
  }

  @Test func `the snapshot of before builds were named is one, and nothing else in Caches is`() {
    #expect(IndexSnapshot.isSnapshot(fileName: "rfc-index.json"))
    #expect(!IndexSnapshot.isSnapshot(fileName: "rfc-index.xml"))
    #expect(!IndexSnapshot.isSnapshot(fileName: "rfc-index-check.json"))
    #expect(!IndexSnapshot.isSnapshot(fileName: "Documents"))
  }

  /// A store whose `build` wrote a snapshot of the index kept, an hour older.
  private func storeWithSnapshot(
    in sandbox: DocumentStoreTests.Sandbox, build: String
  ) async throws -> DocumentStore {
    let store = sandbox.store(build: build)
    let kept = RFCIndex(rfcs: [
      RFCMetadata(id: .rfc(8999), title: "An Example", date: PublicationDate(year: 2021))
    ])
    try await store.storeIndex(Data("<rfc-index/>".utf8), parsed: kept, validators: nil)
    await store.untilSnapshotWritten()
    let xml = sandbox.directory.appending(path: "rfc-index.xml")
    try FileManager.default.setAttributes(
      [.modificationDate: Date.now.addingTimeInterval(-3_600)], ofItemAtPath: xml.path)
    return store
  }

  @Test func `the build that wrote the snapshot reads it`() async throws {
    let sandbox = DocumentStoreTests.Sandbox()
    defer { sandbox.remove() }
    let store = try await storeWithSnapshot(in: sandbox, build: "1 100")
    let snapshot = try #require(store.cachedIndexLocation(bundled: nil)?.snapshot)
    #expect(snapshot.lastPathComponent == IndexSnapshot.fileName(build: "1 100"))
  }

  /// Whatever the dates: an executable that keeps an older build date than the
  /// snapshot's must not read a snapshot another build wrote.
  @Test func `another build parses the index rather than read the snapshot`() async throws {
    let sandbox = DocumentStoreTests.Sandbox()
    defer { sandbox.remove() }
    _ = try await storeWithSnapshot(in: sandbox, build: "1 200")
    let cached = try #require(sandbox.store(build: "1 100").cachedIndexLocation(bundled: nil))
    #expect(cached.snapshot == nil)
  }

  @Test func `a store without a build reads and writes no snapshot`() async throws {
    let sandbox = DocumentStoreTests.Sandbox()
    defer { sandbox.remove() }
    _ = try await storeWithSnapshot(in: sandbox, build: "1 100")
    let store = sandbox.store()
    #expect(store.cachedIndexLocation(bundled: nil)?.snapshot == nil)
  }

  @Test func `a build's snapshot replaces the ones other builds wrote`() async throws {
    let sandbox = DocumentStoreTests.Sandbox()
    defer { sandbox.remove() }
    _ = try await storeWithSnapshot(in: sandbox, build: "1 100")
    try Data("{}".utf8).write(to: sandbox.caches.appending(path: "rfc-index.json"))
    _ = try await storeWithSnapshot(in: sandbox, build: "1 200")
    let names = try FileManager.default.contentsOfDirectory(atPath: sandbox.caches.path)
      .filter { IndexSnapshot.isSnapshot(fileName: $0) }
    #expect(names == [IndexSnapshot.fileName(build: "1 200")])
  }
}
