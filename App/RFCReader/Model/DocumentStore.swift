import Foundation
import RFCKit
import RFCReaderKit
import os

nonisolated private let storeLog = Logger(
  subsystem: Bundle.main.bundleIdentifier ?? "me.mazetti.rfc-reader", category: "store")

/// On-disk cache of raw RFC files plus an in-memory cache of parsed documents.
///
/// Files are stored exactly as served by the RFC Editor, so the "original text"
/// view and re-parsing after a parser improvement both come for free.
actor DocumentStore {
  private let directory: URL
  private var parsed: [DocumentID: RFCDocument] = [:]

  /// Which bodies are on disk, scanned once on first use and kept current by
  /// every write and removal below, so asking does not enumerate the directory.
  /// Each question revalidates it first, which scans again only if the directory
  /// changed some other way, such as a file deleted in Finder.
  private lazy var cachedDocuments = DocumentCacheIndex(scanning: directory)

  /// The fetches running, so a second open joins the first, a removal made during
  /// one keeps its result off the disk, and one nobody waits for any more is
  /// cancelled (#116). Original Text fetches the `.txt` on its own, so it has its
  /// own.
  private let downloads = InFlightDownloads<RFCEditorClient.FetchedDocument>()
  private let originalTexts = InFlightDownloads<Data>()

  /// Whether a body has been written since eviction last looked, so a cache that
  /// has not grown is not enumerated again.
  private var hasGrown = true

  /// Where the index snapshot lives: in Caches, because it is made again from one
  /// parse, so it stays out of backups, and a write there does not change the date
  /// of `directory`, which `cachedDocuments` would answer with a scan.
  private let snapshotURL: URL

  /// The last snapshot write, which the next one waits for, so a snapshot of an
  /// older index never lands after a newer one.
  private var snapshotWrite: Task<Void, Never>?

  init() {
    let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[
      0]
    directory = support.appending(path: "RFCReader", directoryHint: .isDirectory)
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
      .appending(path: "RFCReader", directoryHint: .isDirectory)
    try? FileManager.default.createDirectory(at: caches, withIntermediateDirectories: true)
    snapshotURL = caches.appending(path: "rfc-index.json")
  }

  // MARK: - Index

  private var indexURL: URL { directory.appending(path: "rfc-index.xml") }
  private var checkURL: URL { directory.appending(path: "rfc-index-check.json") }

  /// The index, from its snapshot when that is current, and otherwise parsed from
  /// the XML -- which then writes a snapshot, so the next launch reads that. See
  /// `IndexSnapshot`.
  func cachedIndex() throws -> (index: RFCIndex, updatedAt: Date)? {
    let url: URL
    var updatedAt = Date.distantPast
    if FileManager.default.fileExists(atPath: indexURL.path) {
      url = indexURL
      updatedAt = indexCheck()?.checkedAt ?? Self.modificationDate(of: url) ?? .distantPast
    } else if let bundled = Bundle.main.url(forResource: "rfc-index", withExtension: "xml") {
      // A snapshot shipped with the app makes first launch work offline.
      url = bundled
    } else {
      return nil
    }
    let interval = signposter.beginInterval("Read cached index")
    defer { signposter.endInterval("Read cached index", interval) }

    let isCurrent = IndexSnapshot.isCurrent(
      written: Self.modificationDate(of: snapshotURL),
      index: Self.modificationDate(of: url) ?? .distantFuture,
      app: Bundle.main.executableURL.flatMap(Self.modificationDate(of:)) ?? .distantFuture
    )
    if isCurrent, let data = try? Data(contentsOf: snapshotURL) {
      do {
        let index = try signposter.withIntervalSignpost("Decode index snapshot") {
          try IndexSnapshot.decode(data)
        }
        return (index, updatedAt)
      } catch {
        storeLog.error(
          "decoding the index snapshot failed: \(String(describing: error), privacy: .public)")
      }
    }
    let index = try signposter.withIntervalSignpost("Parse index XML") {
      try RFCIndexParser.parse(contentsOf: url)
    }
    writeSnapshot(of: index)
    return (index, updatedAt)
  }

  /// Keeps a refreshed index, its snapshot made from the same parse, and what
  /// identifies it for the next check.
  ///
  /// Waits for a snapshot write already running first: one of the index being
  /// replaced that landed after the new XML would be newer than it, and so current.
  func storeIndex(_ data: Data, parsed index: RFCIndex, validators: CacheValidators?) async throws {
    await snapshotWrite?.value
    try data.write(to: indexURL, options: .atomic)
    writeSnapshot(of: index)
    try storeCheck(IndexCheck(checkedAt: .now, fetchedAt: .now, validators: validators))
  }

  /// The last check of the index kept on disk, or nil when there is no index on
  /// disk to have checked: the validators describe that file, and nothing else.
  func indexCheck() -> IndexCheck? {
    guard FileManager.default.fileExists(atPath: indexURL.path),
      let data = try? Data(contentsOf: checkURL)
    else { return nil }
    return try? JSONDecoder().decode(IndexCheck.self, from: data)
  }

  /// Records that a check sent with `kept`'s validators found the index unchanged,
  /// and returns when.
  func recordUnchangedIndex(_ kept: IndexCheck) throws -> Date {
    var check = kept
    check.checkedAt = .now
    try storeCheck(check)
    return check.checkedAt
  }

  private func storeCheck(_ check: IndexCheck) throws {
    try JSONEncoder().encode(check).write(to: checkURL, options: .atomic)
  }

  /// Off the actor and after the caller has its index: encoding the whole index
  /// takes about 165 ms, which a launch should not wait for, and a document opened
  /// meanwhile should not queue behind. A snapshot that fails to write costs the
  /// next launch a parse, nothing else.
  private func writeSnapshot(of index: RFCIndex) {
    snapshotWrite = Task(name: "Write index snapshot") { [snapshotURL, snapshotWrite] in
      await snapshotWrite?.value
      await Self.write(index, to: snapshotURL)
    }
  }

  @concurrent
  private static func write(_ index: RFCIndex, to url: URL) async {
    let interval = signposter.beginInterval("Write index snapshot")
    defer { signposter.endInterval("Write index snapshot", interval) }
    do {
      try IndexSnapshot.encode(index).write(to: url, options: .atomic)
    } catch {
      storeLog.error(
        "writing the index snapshot failed: \(String(describing: error), privacy: .public)")
    }
  }

  private static func modificationDate(of url: URL) -> Date? {
    try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
  }

  // MARK: - Documents

  private func fileURL(_ id: DocumentID, format: FileFormat) -> URL {
    directory.appending(path: DocumentCacheIndex.fileName(for: id, format: format))
  }

  func isCached(_ id: DocumentID) -> Bool {
    cachedDocuments.revalidate()
    return cachedDocuments.contains(id)
  }

  /// How much disk the cached body takes, or nil when there is none.
  func downloadedSize(_ id: DocumentID) -> Int? {
    let sizes = DocumentCacheIndex.bodyFormats.compactMap { format in
      (try? fileURL(id, format: format).resourceValues(forKeys: [.fileSizeKey]))?.fileSize
    }
    return sizes.isEmpty ? nil : sizes.reduce(0, +)
  }

  /// Numbers of every RFC with a cached body.
  func cachedNumbers() -> Set<Int> {
    cachedDocuments.revalidate()
    return cachedDocuments.rfcNumbers
  }

  /// A body that cannot be deleted is left where it is, and stays cached: the
  /// index records what the removal left on disk, not what it set out to do.
  func remove(_ id: DocumentID) {
    downloads.removed(id)
    originalTexts.removed(id)
    parsed[id] = nil
    let urls = DocumentCacheIndex.bodyFormats.map { fileURL(id, format: $0) }
    cachedDocuments.update(id) {
      for url in urls {
        try? FileManager.default.removeItem(at: url)
      }
    }
  }

  func document(_ id: DocumentID, formats: [FileFormat], client: RFCEditorClient) async throws
    -> RFCDocument
  {
    let signpostID = signposter.makeSignpostID()
    let interval = signposter.beginInterval(
      "Load document", id: signpostID, "\(id.displayName, privacy: .public)")
    defer { signposter.endInterval("Load document", interval) }
    markOpened(id)
    if let cached = parsed[id] { return cached }

    let xmlURL = fileURL(id, format: .xml)
    if let data = try? Data(contentsOf: xmlURL),
      let document = try? signposter.withIntervalSignpost(
        "Parse document", id: signpostID, "XML", around: { try RFCXMLParser.parse(data) })
    {
      parsed[id] = document
      return document
    }
    let textURL = fileURL(id, format: .text)
    if let data = try? Data(contentsOf: textURL) {
      let document = signposter.withIntervalSignpost(
        "Parse document", id: signpostID, "text", around: { LegacyTextParser.parse(data) })
      parsed[id] = document
      return document
    }

    let (fetched, isKept) = try await downloads.value(for: id) {
      Task { try await Self.fetch(id, formats: formats, client: client) }
    }
    // A removal while this was in flight, or another reader of the same fetch has
    // kept it: the document is shown, and not written here (#116).
    guard isKept else { return fetched.document }
    let url = fileURL(id, format: fetched.format)
    try cachedDocuments.update(id) { try fetched.data.write(to: url, options: .atomic) }
    hasGrown = true
    parsed[id] = fetched.document
    return fetched.document
  }

  /// Not cached: the XML when the index says it exists, otherwise the text, and the
  /// text only when there is no XML (#125). Off the actor, parse included, so the
  /// store answers other calls meanwhile.
  private static func fetch(_ id: DocumentID, formats: [FileFormat], client: RFCEditorClient)
    async throws -> RFCEditorClient.FetchedDocument
  {
    let signpostID = signposter.makeSignpostID()
    let interval = signposter.beginInterval(
      "Fetch document", id: signpostID, "\(id.displayName, privacy: .public)")
    defer { signposter.endInterval("Fetch document", interval) }
    let fetched = try await client.fetchPreferredDocument(
      id, availableFormats: formats.isEmpty ? nil : formats)
    if let failure = fetched.xmlParseFailure {
      storeLog.error(
        "\(id.displayName, privacy: .public): XML did not parse, shown from the text: \(String(describing: failure), privacy: .public)"
      )
    }
    return fetched
  }

  // MARK: - Eviction (#39)

  /// Records that `id` was opened, as its bodies' modification date: a body is
  /// never modified after it is written, so the date is free to mean "last opened",
  /// and it outlives the process. A file's date is not its directory's, so this
  /// does not send `DocumentCacheIndex` to scan again.
  private func markOpened(_ id: DocumentID) {
    for format in DocumentCacheIndex.bodyFormats {
      try? FileManager.default.setAttributes(
        [.modificationDate: Date.now], ofItemAtPath: fileURL(id, format: format).path)
    }
  }

  /// Whether a body has been written since eviction last ran: asked before the
  /// caller builds the pinned set, which is not free.
  var hasGrownSinceEviction: Bool { hasGrown }

  /// Removes the least recently opened bodies past `bound`, never a pinned one; see
  /// `CacheEviction`. Only after the cache has grown, so an ordinary open costs
  /// nothing here. Returns what it removed.
  @discardableResult
  func evict(pinned: Set<DocumentID>, bound: Int) -> [DocumentID] {
    guard hasGrown else { return [] }
    hasGrown = false
    let victims = CacheEviction.victims(
      of: CacheEviction.entries(in: directory), pinned: pinned, bound: bound)
    for id in victims {
      remove(id)
    }
    return victims
  }

  func originalText(_ id: DocumentID, client: RFCEditorClient) async throws -> String {
    let textURL = fileURL(id, format: .text)
    if let data = try? Data(contentsOf: textURL) {
      return LegacyTextParser.stripPagination(String(decoding: data, as: UTF8.self))
    }
    let (data, isKept) = try await originalTexts.value(for: id) {
      Task { try await client.fetchDocumentData(id, format: .text) }
    }
    if isKept {
      try cachedDocuments.update(id) { try data.write(to: textURL, options: .atomic) }
      hasGrown = true
    }
    return LegacyTextParser.stripPagination(String(decoding: data, as: UTF8.self))
  }
}
