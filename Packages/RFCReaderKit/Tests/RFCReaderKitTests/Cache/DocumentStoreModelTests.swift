import Foundation
import RFCKit
import Synchronization
import Testing

@testable import RFCReaderKit

/// A parsed document kept encoded beside its body (#606): an open the in-memory
/// cache misses decodes it rather than parsing the body again, as after a relaunch,
/// unless it was written under another build or for another body. A body that the
/// store reads back in place, its bytes replaced but not its file, shows which: the
/// model decodes to the document, and a parse of the bytes fails and fetches it.
extension DocumentStoreTests {
  /// Replaces the bytes of the file at `url` without replacing the file, so its
  /// creation date stays, as the model's key does.
  static func overwriteInPlace(_ url: URL) throws {
    let handle = try FileHandle(forWritingTo: url)
    defer { try? handle.close() }
    try handle.truncate(atOffset: 0)
    try handle.write(contentsOf: Data("not a document".utf8))
  }

  /// A fetcher whose fetches are not held.
  static func openFetcher() async -> GatedFetcher {
    let fetcher = GatedFetcher()
    await fetcher.gate.open()
    return fetcher
  }

  @Test func `a reopen after a relaunch decodes the model rather than parsing the body`()
    async throws
  {
    let sandbox = Sandbox()
    defer { sandbox.remove() }
    let id = DocumentID.rfc(8999)
    let first = sandbox.store(build: "1")
    _ = try await first.document(id, formats: [.xml], client: Self.openFetcher())
    await first.untilModelsWritten()
    #expect(FileManager.default.fileExists(atPath: sandbox.model(id).path))
    try Self.overwriteInPlace(sandbox.file(id, format: .xml))

    let fetcher = await Self.openFetcher()
    let reopened = try await sandbox.store(build: "1")
      .document(id, formats: [.xml], client: fetcher)

    #expect(reopened == (try Fixtures.rfc8999()))
    #expect(fetcher.documentFetches == 0)
  }

  /// A body read from the disk is parsed once, then decoded: the model is written
  /// after a parse, not only after a fetch. A legacy text keeps the index entry its
  /// parse was given.
  @Test func `a cached body parsed once is decoded after`() async throws {
    let sandbox = Sandbox()
    defer { sandbox.remove() }
    let id = DocumentID.rfc(2119)
    let first = sandbox.store(build: "1")
    try Fixtures.data("rfc2119.txt").write(to: sandbox.file(id, format: .text))
    let parsed = try await first.document(id, formats: [.text], client: Self.openFetcher())
    await first.untilModelsWritten()
    try Self.overwriteInPlace(sandbox.file(id, format: .text))

    let fetcher = await Self.openFetcher()
    let reopened = try await sandbox.store(build: "1")
      .document(id, formats: [.text], client: fetcher)

    #expect(reopened == parsed)
    #expect(fetcher.textFetches == 0)
  }

  /// A text parsed before the index arrived is parsed again once it has an entry, as
  /// it was before models were kept, rather than decoded without one for good.
  @Test func `a text model made without an entry is parsed again with one`() async throws {
    let sandbox = Sandbox()
    defer { sandbox.remove() }
    let id = DocumentID.rfc(2119)
    let first = sandbox.store(build: "1")
    try Fixtures.data("rfc2119.txt").write(to: sandbox.file(id, format: .text))
    let parsed = try await first.document(id, formats: [.text], client: Self.openFetcher())
    await first.untilModelsWritten()
    try Self.overwriteInPlace(sandbox.file(id, format: .text))
    let entry = RFCMetadata(
      id: id, title: "Key Words", date: PublicationDate(year: 1997, month: 3), formats: [.text])

    let reopened = try await sandbox.store(build: "1")
      .document(id, formats: [.text], entry: entry, client: Self.openFetcher())

    #expect(reopened != LegacyTextParser.applying(entry, to: parsed))
  }

  /// A body moved over another keeps its own creation date, so the model left beside
  /// the one it replaced is not taken for its own.
  @Test func `a body moved over another is not read from the other's model`() async throws {
    let sandbox = Sandbox()
    defer { sandbox.remove() }
    let id = DocumentID.rfc(8999)
    let store = sandbox.store(build: "1")
    _ = try await store.document(id, formats: [.xml], client: Self.openFetcher())
    await store.untilModelsWritten()
    #expect(try await store.keepCached(id))
    try Data("not a document".utf8).write(to: sandbox.file(id, format: .xml), options: .atomic)
    #expect(try await store.keepCached(id))

    let fetcher = await Self.openFetcher()
    _ = try await sandbox.store(build: "1").document(id, formats: [.xml], client: fetcher)

    #expect(fetcher.documentFetches == 1)
  }

  /// A model written into the cache grows it, as a body does, so eviction looks again.
  @Test func `a model written into the cache counts as the cache growing`() async throws {
    let sandbox = Sandbox()
    defer { sandbox.remove() }
    let id = DocumentID.rfc(8999)
    try FileManager.default.createDirectory(
      at: sandbox.file(id, format: .xml).deletingLastPathComponent(),
      withIntermediateDirectories: true)
    try Fixtures.data("rfc8999.xml").write(to: sandbox.file(id, format: .xml))
    let store = sandbox.store(build: "1")
    await store.evict(pinned: [], bound: .max)

    _ = try await store.document(id, formats: [.xml], client: Self.openFetcher())
    await store.untilModelsWritten()

    #expect(FileManager.default.fileExists(atPath: sandbox.model(id).path))
    #expect(await store.hasGrownSinceEviction)
  }

  /// A model is written only where the disk has room for it, as a body is.
  @Test func `a model the disk has no room for is not written`() async throws {
    let sandbox = Sandbox()
    defer { sandbox.remove() }
    let id = DocumentID.rfc(8999)
    let asked = Mutex(0)
    let store = sandbox.store(
      freeSpace: { _ in
        let count = asked.withLock { asked in
          asked += 1
          return asked
        }
        return count == 1 ? Int.max / 2 : 0
      }, build: "1")
    _ = try await store.document(id, formats: [.xml], client: Self.openFetcher())
    await store.untilModelsWritten()

    #expect(sandbox.exists(id, format: .xml, in: .cache))
    #expect(!FileManager.default.fileExists(atPath: sandbox.model(id).path))
  }

  @Test func `a model written under another build is parsed again`() async throws {
    let sandbox = Sandbox()
    defer { sandbox.remove() }
    let id = DocumentID.rfc(8999)
    let first = sandbox.store(build: "1")
    _ = try await first.document(id, formats: [.xml], client: Self.openFetcher())
    await first.untilModelsWritten()
    try Self.overwriteInPlace(sandbox.file(id, format: .xml))

    let fetcher = await Self.openFetcher()
    _ = try await sandbox.store(build: "2").document(id, formats: [.xml], client: fetcher)

    #expect(fetcher.documentFetches == 1)
  }

  /// A body written again is a new file, whose creation date the model no longer
  /// matches.
  @Test func `a model written for another body is parsed again`() async throws {
    let sandbox = Sandbox()
    defer { sandbox.remove() }
    let id = DocumentID.rfc(8999)
    let first = sandbox.store(build: "1")
    _ = try await first.document(id, formats: [.xml], client: Self.openFetcher())
    await first.untilModelsWritten()
    try Data("not a document".utf8).write(to: sandbox.file(id, format: .xml), options: .atomic)

    let fetcher = await Self.openFetcher()
    _ = try await sandbox.store(build: "1").document(id, formats: [.xml], client: fetcher)

    #expect(fetcher.documentFetches == 1)
  }

  /// The model is part of what the cache holds: counted toward its size, and
  /// removed with its body, by eviction, Clear Cache or a removal.
  @Test func `a model counts toward the cache and goes with its body`() async throws {
    let sandbox = Sandbox()
    defer { sandbox.remove() }
    let id = DocumentID.rfc(8999)
    let store = sandbox.store(build: "1")
    _ = try await store.document(id, formats: [.xml], client: Self.openFetcher())
    await store.untilModelsWritten()
    let size = { (url: URL) in try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0 }
    let bytes = try size(sandbox.file(id, format: .xml)) + size(sandbox.model(id))

    #expect(await store.storageUsage(sparing: []).cache == StorageUsage(documents: 1, bytes: bytes))
    #expect(await store.clearCache(sparing: []) == [id])
    #expect(!FileManager.default.fileExists(atPath: sandbox.model(id).path))

    _ = try await store.document(id, formats: [.xml], client: Self.openFetcher())
    await store.untilModelsWritten()
    await store.remove(id)
    #expect(!FileManager.default.fileExists(atPath: sandbox.model(id).path))
  }

  /// A removal made while the model is still to be written leaves no model behind:
  /// one written after it would belong to no body.
  @Test func `a body removed before its model is written gets none`() async throws {
    let sandbox = Sandbox()
    defer { sandbox.remove() }
    let id = DocumentID.rfc(8999)
    let store = sandbox.store(build: "1")
    _ = try await store.document(id, formats: [.xml], client: Self.openFetcher())
    await store.remove(id)
    await store.untilModelsWritten()

    #expect(!FileManager.default.fileExists(atPath: sandbox.model(id).path))
  }

  /// A body kept offline keeps its model beside it, moved with it between the tiers.
  @Test func `a model moves with its body`() async throws {
    let sandbox = Sandbox()
    defer { sandbox.remove() }
    let id = DocumentID.rfc(8999)
    let store = sandbox.store(build: "1")
    _ = try await store.document(id, formats: [.xml], client: Self.openFetcher())
    await store.untilModelsWritten()

    #expect(try await store.keepCached(id))
    #expect(FileManager.default.fileExists(atPath: sandbox.model(id, in: .kept).path))
    #expect(!FileManager.default.fileExists(atPath: sandbox.model(id, in: .cache).path))
  }
}
