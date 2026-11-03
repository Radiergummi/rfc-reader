import Foundation
import RFCKit
import SwiftData
import Testing

@testable import RFCReaderKit

/// The documents' bodies as `LibraryModel` handles them (#595): a load and the
/// eviction after it, Clear Cache, and Keep Offline, against the document store's own
/// sequences in a sandbox and the user's data in memory.
@Suite("Document repository", .hangGuard)
@MainActor
struct DocumentRepositoryTests {
  private typealias Sandbox = DocumentStoreTests.Sandbox

  nonisolated private static let bcp14 = DocumentID(series: .bcp, number: 14)

  /// Serves the committed fixtures as `DocumentStoreTests.GatedFetcher` does, with
  /// its gate open; a draft is never found.
  private final class Fetcher: DocumentFetching, DraftFetching {
    let documents = DocumentStoreTests.GatedFetcher()

    init() async {
      await documents.gate.open()
    }

    @concurrent
    func fetchPreferredDocument(
      _ id: DocumentID, availableFormats: [FileFormat]?, entry: RFCMetadata?
    ) async throws -> RFCEditorClient.FetchedDocument {
      try await documents.fetchPreferredDocument(
        id, availableFormats: availableFormats, entry: entry)
    }

    func fetchDocumentData(_ id: DocumentID, format: FileFormat) async throws -> Data {
      try await documents.fetchDocumentData(id, format: format)
    }

    @concurrent
    func fetchDraftInfo(_ id: DraftID) async throws -> (info: DraftInfo, data: Data) {
      throw URLError(.fileDoesNotExist)
    }

    @concurrent
    func fetchDraft(_ id: DraftID) async throws -> RFCEditorClient.FetchedDocument {
      throw URLError(.fileDoesNotExist)
    }

    func fetchDraftData(_ id: DraftID, format: FileFormat) async throws -> Data {
      throw URLError(.fileDoesNotExist)
    }
  }

  /// One test's repository, with what it was made from.
  @MainActor
  private struct Setup {
    let sandbox = Sandbox()
    let defaults: UserDefaults
    let suiteName = "DocumentRepositoryTests-\(UUID().uuidString)"
    let container: ModelContainer
    let userData: UserDataMirror
    let fetcher: Fetcher
    /// What the windows show, which a test changes as a reader would.
    let open = Box<[ReadableDocument]>([])
    /// Every report of `onRemoved`.
    let removed = Box<[[DocumentID]]>([])

    init() async throws {
      defaults = UserDefaults(suiteName: suiteName)!
      container = try UserData.container(
        configurations: ModelConfiguration(isStoredInMemoryOnly: true))
      userData = UserDataMirror(container: container)
      fetcher = await Fetcher()
    }

    /// A repository over this setup, its eviction bound at nothing, so a load
    /// evicts everything nothing pins, with the index of the fixtures and a network that
    /// lets every fetch go ahead. Wired to the mirror as `LibraryModel` wires it.
    func repository(cacheBound: Int = 0) -> DocumentRepository {
      let index = DocumentRepositoryTests.index
      let repository = DocumentRepository(
        store: sandbox.store(), client: fetcher, clientFailingOnExpensiveNetworks: fetcher,
        drafts: DraftStore(directory: sandbox.root.appending(path: "Drafts")),
        userData: userData, defaults: defaults, isStoredInMemory: false,
        index: { index }, openDocuments: { [open] in open.value },
        networkDecision: { _ in .fetch }, cacheBound: cacheBound)
      repository.onRemoved = { [removed] in removed.value.append($0) }
      userData.onOfflineMarksChanged = { [weak repository] in
        repository?.wantedOfflineChanged()
      }
      userData.onBookmarksChanged = { [weak repository] in repository?.bookmarksChanged() }
      userData.start()
      return repository
    }

    func remove() {
      sandbox.remove()
      UserDefaults.standard.removePersistentDomain(forName: suiteName)
    }
  }

  @MainActor
  final class Box<Value> {
    var value: Value
    init(_ value: Value) { self.value = value }
  }

  nonisolated private static let index = RFCIndex(
    rfcs: [Fixtures.metadata(2119), Fixtures.metadata(8174), Fixtures.metadata(8999)],
    series: [SeriesEntry(id: bcp14, members: [.rfc(2119), .rfc(8174)])])

  // MARK: - Eviction

  @Test func `a load past the bound evicts what nothing pins, and reports it`() async throws {
    let setup = try await Setup()
    defer { setup.remove() }
    let repository = setup.repository()

    setup.open.value = [.rfc(.rfc(8999))]
    _ = try await repository.document(for: .rfc(.rfc(8999)))
    setup.open.value = [.rfc(.rfc(2119))]
    _ = try await repository.document(for: .rfc(.rfc(2119)))

    #expect(setup.removed.value == [[.rfc(8999)]])
    #expect(!setup.sandbox.exists(.rfc(8999), format: .xml, in: .cache))
    #expect(setup.sandbox.exists(.rfc(2119), format: .xml, in: .cache))
  }

  /// A bookmarked series stands for its members (#656).
  @Test func `eviction keeps what is bookmarked, and a bookmarked series' members`()
    async throws
  {
    let setup = try await Setup()
    defer { setup.remove() }
    let repository = setup.repository()
    setup.userData.toggleBookmark(.rfc(8999), title: "RFC 8999")
    setup.userData.toggleBookmark(Self.bcp14, title: "BCP 14")

    for number in [8999, 2119, 8174] {
      _ = try await repository.document(for: .rfc(.rfc(number)))
    }

    #expect(setup.removed.value.isEmpty)
    for number in [8999, 2119, 8174] {
      #expect(setup.sandbox.exists(.rfc(number), format: .xml, in: .cache))
    }
  }

  @Test func `eviction keeps what was read in the last month`() async throws {
    let setup = try await Setup()
    defer { setup.remove() }
    let repository = setup.repository()
    try setup.userData.recordOpening(.rfc(.rfc(8999)))

    _ = try await repository.document(for: .rfc(.rfc(8999)))
    _ = try await repository.document(for: .rfc(.rfc(2119)))

    #expect(setup.sandbox.exists(.rfc(8999), format: .xml, in: .cache))
    #expect(setup.removed.value == [[.rfc(2119)]])
  }

  // MARK: - Clear Cache

  @Test func `clearing the cache spares what is open, and reports what it removed`() async throws {
    let setup = try await Setup()
    defer { setup.remove() }
    let repository = setup.repository(cacheBound: CacheEviction.defaultBound)
    for number in [8999, 2119] {
      _ = try await repository.document(for: .rfc(.rfc(number)))
    }
    setup.open.value = [.rfc(.rfc(2119))]

    await repository.clearCache()

    #expect(setup.removed.value == [[.rfc(8999)]])
    #expect(setup.sandbox.exists(.rfc(2119), format: .xml, in: .cache))
    #expect(!setup.sandbox.exists(.rfc(8999), format: .xml, in: .cache))
  }

  /// Until the marks have been read, what to spare is not known.
  @Test func `clearing the cache removes nothing before the marks have been read`() async throws {
    let setup = try await Setup()
    defer { setup.remove() }
    let repository = DocumentRepository(
      store: setup.sandbox.store(), client: setup.fetcher,
      clientFailingOnExpensiveNetworks: setup.fetcher,
      drafts: DraftStore(directory: setup.sandbox.root.appending(path: "Drafts")),
      userData: setup.userData, defaults: setup.defaults, isStoredInMemory: false,
      index: { Self.index }, openDocuments: { [] }, networkDecision: { _ in .fetch },
      cacheBound: CacheEviction.defaultBound)
    _ = try await repository.document(for: .rfc(.rfc(8999)))

    await repository.clearCache()

    #expect(setup.sandbox.exists(.rfc(8999), format: .xml, in: .cache))
    #expect(await repository.storageUsage().clearable.documents == 0)
  }

  // MARK: - Keep Offline

  @Test func `marking Keep Offline fetches into the kept tier and lists the document`()
    async throws
  {
    let setup = try await Setup()
    defer { setup.remove() }
    let repository = setup.repository()

    try await repository.setKeptOffline(.rfc(8999), true)
    #expect(await repository.keptSize(.rfc(8999)) != nil)

    #expect(repository.availableOfflineNumbers == [8999])
    #expect(repository.isAvailableOffline(.rfc(8999)))
    #expect(setup.sandbox.exists(.rfc(8999), format: .xml, in: .kept))
  }

  /// Per device, as storage is, so read from and written to user defaults.
  @Test func `keeping bookmarks offline is remembered, and lists the bookmarks`() async throws {
    let setup = try await Setup()
    defer { setup.remove() }
    let repository = setup.repository()
    setup.userData.toggleBookmark(Self.bcp14, title: "BCP 14")
    #expect(!repository.keepsBookmarksOffline)
    #expect(repository.availableOfflineNumbers.isEmpty)

    repository.setKeepsBookmarksOffline(true)

    #expect(repository.availableOfflineNumbers == [2119, 8174])
    #expect(setup.repository().keepsBookmarksOffline)
  }

  @Test func `removing every offline document removes the marks and stops keeping bookmarks`()
    async throws
  {
    let setup = try await Setup()
    defer { setup.remove() }
    let repository = setup.repository()
    repository.setKeepsBookmarksOffline(true)
    try await repository.setKeptOffline(.rfc(8999), true)

    repository.removeAllOffline()
    _ = await repository.storageUsage()

    #expect(!repository.keepsBookmarksOffline)
    #expect(setup.userData.offlineMarks.isEmpty)
    #expect(repository.availableOfflineNumbers.isEmpty)
    #expect(setup.sandbox.exists(.rfc(8999), format: .xml, in: .cache))
  }

  // MARK: - Reading paths

  @Test func `a reading path without a citation index says there is none`() async throws {
    let setup = try await Setup()
    defer { setup.remove() }
    let repository = setup.repository()

    await repository.refreshCitationIndex()

    #expect(!repository.hasCitationIndex)
    guard case .noIndex = await repository.readingPath(from: .rfc(8999), depth: 1) else {
      Issue.record("expected no index")
      return
    }
  }
}
