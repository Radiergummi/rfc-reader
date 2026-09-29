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
  /// The documents parsed last, so reopening one, or going back to it, skips the
  /// parse: 35 to 60 ms for the largest XML, half a second for RFC 5661's text
  /// (`make benchmark`). Bounded: it used to keep every document opened for as long
  /// as the app ran.
  private var parsed = RecentValues<DocumentID, RFCDocument>(capacity: 8)

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
  /// The parses of cached bodies running, for the same three reasons: a parse
  /// suspends the open, so the actor lets a second open or a removal in meanwhile.
  private let parses = InFlightDownloads<RFCDocument?>()

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

  /// The installed data packs (#36), in a folder of the cache's directory but not
  /// part of the cache: a pack is installed and replaced whole, never evicted a
  /// document at a time. The cache's index and eviction read only the bodies the
  /// store names itself, at the directory's top level, so a folder is never one.
  private var packsDirectory: URL {
    directory.appending(path: "Packs", directoryHint: .isDirectory)
  }

  /// The converted legacy RFCs, the one pack the app reads so far. Nil until one
  /// is installed.
  private lazy var legacyPack: InstalledPack? = Self.installedPack(
    in: packsDirectory.appending(path: Self.legacyPackName, directoryHint: .isDirectory))
  private static let legacyPackName = "legacy-xml"
  /// One install at a time: two would unpack into one destination and race to
  /// swap it in.
  private var isInstallingPack = false

  struct AlreadyInstalling: Error, CustomStringConvertible {
    var description: String { "A data pack is already being installed." }
  }

  struct DownloadFailed: Error, CustomStringConvertible {
    let url: URL
    let status: Int
    var description: String { "\(url.absoluteString) answered HTTP \(status)" }
  }

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

  private nonisolated var indexURL: URL { directory.appending(path: "rfc-index.xml") }
  private nonisolated var checkURL: URL { directory.appending(path: "rfc-index-check.json") }

  /// The cached index's XML, when it was written, and its snapshot when that is current.
  struct CachedIndex {
    let url: URL
    let updatedAt: Date
    let snapshot: URL?
  }

  /// Where the cached index is, when it was written, and its snapshot when that is
  /// current: the RFC Editor's copy in the cache, or else the one bundled with the
  /// app. Nil when there is neither. See `IndexSnapshot`.
  ///
  /// Only a lookup, and nonisolated: the caller reads it, off this actor (#367).
  /// Read here, the index held the store for as long as the parse took, so a
  /// document opened during launch — an `rfc://` link — waited behind it.
  nonisolated func cachedIndexLocation() -> CachedIndex? {
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
    let isCurrent = IndexSnapshot.isCurrent(
      written: Self.modificationDate(of: snapshotURL),
      index: Self.modificationDate(of: url) ?? .distantFuture,
      app: Bundle.main.executableURL.flatMap(Self.modificationDate(of:)) ?? .distantFuture
    )
    return CachedIndex(url: url, updatedAt: updatedAt, snapshot: isCurrent ? snapshotURL : nil)
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
  nonisolated func indexCheck() -> IndexCheck? {
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
  func writeSnapshot(of index: RFCIndex) {
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

  // MARK: - Revisions

  private var revisionsURL: URL { directory.appending(path: "revisions.json") }

  /// The last good `revisions.json`. Nil when there is none, or it no longer decodes
  /// (a newer version, after a downgrade).
  func cachedRevisions() -> RFCRevisions? {
    guard let data = try? Data(contentsOf: revisionsURL) else { return nil }
    return try? RFCRevisions.decode(data)
  }

  func storeRevisions(_ data: Data) throws {
    try data.write(to: revisionsURL, options: .atomic)
  }

  // MARK: - Registries

  /// The IANA registries the Go to RFC palette looks values up in (#175), one file
  /// each, as IANA serves it.
  private var registriesDirectory: URL {
    directory.appending(path: "Registries", directoryHint: .isDirectory)
  }

  private func registryURL(_ registry: IANARegistry) -> URL {
    registriesDirectory.appending(path: "\(registry.file).xml")
  }

  /// Every cached registry's entries, and which registries are due a fetch: never
  /// fetched, older than `maximumAge`, or no longer readable. A stale registry's
  /// entries are still returned, to use until the fetch succeeds.
  func cachedRegistries(maximumAge: TimeInterval) -> (
    entries: [IANARegistry: [RegistryEntry]], stale: [IANARegistry]
  ) {
    var entries: [IANARegistry: [RegistryEntry]] = [:]
    var stale: [IANARegistry] = []
    for registry in IANARegistry.allCases {
      let url = registryURL(registry)
      guard let data = try? Data(contentsOf: url),
        let parsed = try? IANARegistry.parse(data, as: registry)
      else {
        stale.append(registry)
        continue
      }
      entries[registry] = parsed
      let fetched = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
        .contentModificationDate
      if (fetched ?? .distantPast).timeIntervalSinceNow < -maximumAge {
        stale.append(registry)
      }
    }
    return (entries, stale)
  }

  func storeRegistry(_ data: Data, for registry: IANARegistry) throws {
    try FileManager.default.createDirectory(
      at: registriesDirectory, withIntermediateDirectories: true)
    try data.write(to: registryURL(registry), options: .atomic)
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
    parses.removed(id)
    parsed.removeAll { $0 == id }
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
    if let cached = parsed.value(for: id) { return cached }

    let xmlURL = fileURL(id, format: .xml)
    let textURL = fileURL(id, format: .text)
    let packURL = legacyPack?.file(for: id)
    let (cached, isCachedKept) = try await parses.value(for: id) {
      Task {
        await Self.parseCached(
          id, xml: xmlURL, pack: packURL, text: textURL, signpostID: signpostID)
      }
    }
    if let cached {
      // A body removed while it parsed is shown but not kept, like a fetch (#116).
      if isCachedKept { parsed.store(cached, for: id) }
      return cached
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
    // A pack installed while this was in flight serves the document from now on.
    if legacyPack?.file(for: id) == nil {
      parsed.store(fetched.document, for: id)
    }
    return fetched.document
  }

  /// The body on disk, parsed: the cached XML if there is one, then the installed
  /// pack's, otherwise the cached text, or nil when none is there. Off the actor,
  /// like a fetch's parse, so the store answers other calls meanwhile -- whether a
  /// document is available offline, the next open -- instead of queueing them
  /// behind half a second of legacy text.
  @concurrent
  private static func parseCached(
    _ id: DocumentID, xml: URL, pack: URL?, text: URL, signpostID: OSSignpostID
  ) async -> RFCDocument? {
    if let data = try? Data(contentsOf: xml),
      let document = try? signposter.withIntervalSignpost(
        "Parse document", id: signpostID, "XML", around: { try RFCXMLParser.parse(data) })
    {
      return document
    }
    // Before a cached `.txt`: the pack is the single XML path it exists for, and a
    // `.txt` cached before it arrived still serves Original Text.
    if let pack {
      do {
        return try RFCXMLParser.parse(Data(contentsOf: pack))
      } catch {
        storeLog.error(
          "\(id.displayName, privacy: .public): not read from the data pack: \(String(describing: error), privacy: .public)"
        )
      }
    }
    guard let data = try? Data(contentsOf: text) else { return nil }
    return signposter.withIntervalSignpost(
      "Parse document", id: signpostID, "text", around: { LegacyTextParser.parse(data) })
  }

  /// Not cached: the XML when the index says it exists, otherwise the text, and the
  /// text only when there is no XML (#125). Off the actor, parse included, so the
  /// store answers other calls meanwhile.
  private static func fetch(_ id: DocumentID, formats: [FileFormat], client: RFCEditorClient)
    async throws -> RFCEditorClient.FetchedDocument
  {
    let interval = signposter.beginInterval(
      "Fetch document", id: signposter.makeSignpostID(), "\(id.displayName, privacy: .public)")
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

  // MARK: - Data packs (#36)

  /// The pack in `directory`, or nil when none is installed there or its manifest
  /// does not read. That is logged, because the store would otherwise fall back to
  /// the network with no sign of why.
  private static func installedPack(in directory: URL) -> InstalledPack? {
    guard FileManager.default.fileExists(atPath: directory.path(percentEncoded: false)) else {
      return nil
    }
    do {
      return try InstalledPack(contentsOf: directory)
    } catch {
      storeLog.error(
        "the installed data pack is unreadable: \(String(describing: error), privacy: .public)")
      return nil
    }
  }

  /// Installs the legacy XML pack from an `.aar`, an unpacked folder, or a URL to
  /// download one from, replacing the installed one only once the new one has
  /// verified. Documents already parsed are parsed again on their next open, so
  /// they come from the pack.
  func installLegacyPack(from source: URL) async throws -> InstalledPack {
    // Checked and set without a suspension between them, so a second install
    // arriving while the first is off the actor is refused rather than raced.
    guard !isInstallingPack else { throw AlreadyInstalling() }
    isInstallingPack = true
    defer { isInstallingPack = false }
    let pack = try await Self.install(source, as: Self.legacyPackName, in: packsDirectory)
    legacyPack = pack
    // Parsed again on their next open, from the pack; nothing else it could serve.
    parsed.removeAll { pack.file(for: $0) != nil }
    return pack
  }

  /// Off the actor: a whole pack is unpacked and every file hashed.
  @concurrent
  private static func install(_ source: URL, as name: String, in packs: URL) async throws
    -> InstalledPack
  {
    guard !source.isFileURL else {
      return try PackInstaller.install(source, as: name, in: packs)
    }
    let (downloaded, response) = try await URLSession.shared.download(from: source)
    defer { try? FileManager.default.removeItem(at: downloaded) }
    // An error page is not an archive, and would be reported as one that failed
    // to unpack.
    if let status = (response as? HTTPURLResponse)?.statusCode, !(200..<300).contains(status) {
      throw DownloadFailed(url: source, status: status)
    }
    return try PackInstaller.install(downloaded, as: name, in: packs)
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
