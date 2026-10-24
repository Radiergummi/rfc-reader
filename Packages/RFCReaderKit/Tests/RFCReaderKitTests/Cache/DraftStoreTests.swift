import Foundation
import RFCKit
import Testing

@testable import RFCReaderKit

/// Drafts read, kept and asked of Datatracker again (#728).
@Suite("Draft store")
struct DraftStoreTests {
  /// Stands in for Datatracker and the archive: answers what it was given, and
  /// counts what it was asked.
  private final class Network: DraftFetching, @unchecked Sendable {
    private let lock = NSLock()
    private var infoAsks = 0
    private var revisionAsks: [DraftID] = []
    private var newestRevision: String
    private var isDown = false

    init(newest: String) {
      newestRevision = newest
    }

    var askedInfo: Int { lock.withLock { infoAsks } }
    var askedRevisions: [DraftID] { lock.withLock { revisionAsks } }

    func publish(_ revision: String) { lock.withLock { newestRevision = revision } }
    func goDown() { lock.withLock { isDown = true } }

    func fetchDraftInfo(_ id: DraftID) async throws -> (info: DraftInfo, data: Data) {
      let newest = try lock.withLock {
        if isDown { throw URLError(.notConnectedToInternet) }
        infoAsks += 1
        return newestRevision
      }
      let json = """
        {"name": "\(id.name)", "rev": "\(newest)", "title": "An Example", "state": "Active",
         "rev_history": [{"name": "\(id.name)", "rev": "\(newest)", "published": null}]}
        """
      let data = Data(json.utf8)
      return (try DraftInfo.decode(data), data)
    }

    func fetchDraftData(_ id: DraftID, format: FileFormat) async throws -> Data {
      try lock.withLock {
        if isDown { throw URLError(.notConnectedToInternet) }
        revisionAsks.append(id)
      }
      return try Fixtures.data("rfc2119.txt")
    }

    func fetchDraft(_ id: DraftID) async throws -> RFCEditorClient.FetchedDocument {
      try lock.withLock {
        if isDown { throw URLError(.notConnectedToInternet) }
        revisionAsks.append(id)
      }
      // Any RFC's text stands in for a draft's.
      let data = try Fixtures.data("rfc2119.txt")
      return RFCEditorClient.FetchedDocument(
        data: data, format: .text, document: RFCEditorClient.parseDraft(data, id: id),
        xmlParseFailure: nil)
    }
  }

  /// A clock a test moves on.
  private final class Clock: @unchecked Sendable {
    private let lock = NSLock()
    private var current = Date()
    var now: Date { lock.withLock { current } }
    func advance(by interval: TimeInterval) { lock.withLock { current += interval } }
  }

  private static let name = DraftID(parsing: "draft-ietf-example-protocol")!
  private static func revision(_ number: String) -> DraftID { name.at(revision: number)! }

  private func directory() -> URL {
    FileManager.default.temporaryDirectory.appending(
      path: "DraftStoreTests-\(UUID().uuidString)", directoryHint: .isDirectory)
  }

  @Test func `the newest revision is asked of Datatracker, then fetched and kept`() async throws {
    let network = Network(newest: "04")
    let folder = directory()
    let store = DraftStore(directory: folder)
    let document = try await store.document(Self.name, client: network)
    #expect(document.header.draftName == "draft-ietf-example-protocol-04")
    #expect(network.askedInfo == 1)
    #expect(network.askedRevisions == [Self.revision("04")])

    // Another store over the same folder, as on the next launch: from the disk.
    let next = DraftStore(directory: folder)
    _ = try await next.document(Self.revision("04"), client: network)
    #expect(network.askedRevisions == [Self.revision("04")])
  }

  @Test func `a revision named is fetched without asking which is the newest`() async throws {
    let network = Network(newest: "04")
    let store = DraftStore(directory: directory())
    _ = try await store.document(Self.revision("02"), client: network)
    _ = try await store.document(Self.revision("02"), client: network)
    #expect(network.askedInfo == 0)
    #expect(network.askedRevisions == [Self.revision("02")])
  }

  @Test func `which revision is the newest is asked again once a day has passed`() async throws {
    let network = Network(newest: "04")
    let clock = Clock()
    let store = DraftStore(directory: directory(), now: { clock.now })
    #expect(try await store.revision(of: Self.name, client: network) == Self.revision("04"))
    network.publish("05")
    clock.advance(by: DraftStore.infoLifetime - 60)
    #expect(try await store.revision(of: Self.name, client: network) == Self.revision("04"))
    #expect(network.askedInfo == 1)
    clock.advance(by: 120)
    #expect(try await store.revision(of: Self.name, client: network) == Self.revision("05"))
    #expect(network.askedInfo == 2)
  }

  /// A link to a revision published since Datatracker was last asked, within the day.
  @Test func `a revision newer than the newest kept asks Datatracker again`() async throws {
    let network = Network(newest: "04")
    let store = DraftStore(directory: directory())
    _ = try await store.info(for: Self.name, client: network)
    network.publish("05")
    let info = try await store.info(for: Self.revision("05"), client: network)
    #expect(info.newestRevision == "05")
    #expect(network.askedInfo == 2)
    // One it knows of, older or the newest, is what is kept.
    _ = try await store.info(for: Self.revision("03"), client: network)
    #expect(network.askedInfo == 2)
  }

  /// A draft opened without a revision asks for its header and its revision at once.
  @Test func `two asks of Datatracker at once are one`() async throws {
    let network = Network(newest: "04")
    let store = DraftStore(directory: directory())
    async let first = store.info(for: Self.name, client: network)
    async let second = store.info(for: Self.name, client: network)
    _ = try await (first, second)
    #expect(network.askedInfo == 1)
  }

  /// The reader and Original Text read one download.
  @Test func `the original text is the text the revision was read from`() async throws {
    let network = Network(newest: "04")
    let store = DraftStore(directory: directory())
    _ = try await store.document(Self.revision("04"), client: network)
    let text = try await store.originalText(Self.revision("04"), client: network)
    #expect(!text.isEmpty)
    #expect(network.askedRevisions == [Self.revision("04")])
  }

  @Test func `offline, a draft read before opens as it was kept`() async throws {
    let network = Network(newest: "04")
    let clock = Clock()
    let folder = directory()
    _ = try await DraftStore(directory: folder, now: { clock.now })
      .document(Self.name, client: network)
    network.goDown()
    clock.advance(by: 2 * DraftStore.infoLifetime)
    let document = try await DraftStore(directory: folder, now: { clock.now })
      .document(Self.name, client: network)
    #expect(document.header.draftName == "draft-ietf-example-protocol-04")
  }

  @Test func `offline, a draft never read is an error`() async throws {
    let network = Network(newest: "04")
    network.goDown()
    await #expect(throws: URLError.self) {
      try await DraftStore(directory: directory()).document(Self.name, client: network)
    }
  }

  /// Every revision has a text at the archive, which Original Text shows (#728).
  @Test func `a revision's original text is fetched once, then kept`() async throws {
    let network = Network(newest: "04")
    let store = DraftStore(directory: directory())
    let text = try await store.originalText(Self.revision("04"), client: network)
    #expect(!text.isEmpty)
    #expect(try await store.originalText(Self.revision("04"), client: network) == text)
    #expect(network.askedRevisions == [Self.revision("04")])
  }

  /// Settings' Storage tab counts the revisions kept with the reading cache, and
  /// Clear Cache removes them, since every one can be fetched again (#358).
  @Test func `the revisions kept are counted, and cleared`() async throws {
    let network = Network(newest: "04")
    let store = DraftStore(directory: directory())
    #expect(await store.storageUsage(sparing: []).cache == StorageUsage(documents: 0, bytes: 0))
    _ = try await store.document(Self.name, client: network)
    _ = try await store.document(Self.revision("03"), client: network)
    let usage = await store.storageUsage(sparing: [])
    #expect(usage.cache.documents == 2)
    #expect(usage.cache.bytes > 0)
    #expect(usage.clearable == usage.cache)

    await store.clear(sparing: [])
    #expect(await store.storageUsage(sparing: []).cache == StorageUsage(documents: 0, bytes: 0))
    _ = try await store.document(Self.revision("03"), client: network)
    #expect(
      network.askedRevisions == [Self.revision("04"), Self.revision("03"), Self.revision("03")])
  }

  /// An open draft stays, as an open RFC does (`CacheEviction.spared`): its revision,
  /// and what Datatracker said of it, which counts as in use rather than clearable.
  @Test func `the revision open is spared by Clear Cache, and counted as in use`() async throws {
    let network = Network(newest: "04")
    let folder = directory()
    let store = DraftStore(directory: folder)
    _ = try await store.document(Self.name, client: network)
    _ = try await store.document(Self.revision("03"), client: network)
    let open: Set = [Self.revision("04")]

    let usage = await store.storageUsage(sparing: open)
    #expect(usage.cache.documents == 2)
    #expect(usage.clearable.documents == 1)
    #expect(usage.clearable.bytes < usage.cache.bytes)

    await store.clear(sparing: open)
    #expect(await store.storageUsage(sparing: []).cache.documents == 1)
    // Offline, from the disk alone: the revision open, and which is the newest.
    network.goDown()
    _ = try await DraftStore(directory: folder).document(Self.name, client: network)
    await #expect(throws: (any Error).self) {
      try await DraftStore(directory: folder).document(Self.revision("03"), client: network)
    }
  }
}
