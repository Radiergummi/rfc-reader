import Foundation
import RFCKit
import os

/// The app's log subsystem, as the app's own loggers name it: at run time
/// `Bundle.main` is the app's, from a package too.
private let storeLog = Logger(
  subsystem: Bundle.main.bundleIdentifier ?? "me.mazetti.rfc-reader", category: "store")

/// The store's intervals, in the app's Points of Interest lane: the same subsystem
/// and category as the app's `signposter`, so `make trace` reads them as before.
private let signposter = OSSignposter(
  subsystem: Bundle.main.bundleIdentifier ?? "me.mazetti.rfc-reader",
  category: .pointsOfInterest
)

/// On-disk cache of raw RFC files plus an in-memory cache of parsed documents.
///
/// Files are stored exactly as served by the RFC Editor, so the "original text"
/// view and re-parsing after a parser improvement both come for free.
///
/// Here rather than in the App target for its tests, which run its sequences — a
/// second open joining the first, a removal during a download — against a fetcher
/// that waits until the test lets it finish (#596).
public actor DocumentStore {
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
  /// canceled (#116). A `.txt` is fetched in `texts`, which Original Text and, where
  /// the text is all there is to a document, its load share (#324): the download
  /// alone, parsed afterwards by a load that wants it, so Original Text shows it
  /// without waiting for a parse, and a reader who leaves cancels nothing but bytes.
  private let downloads = InFlightDownloads<RFCEditorClient.FetchedDocument>()
  private let texts = InFlightDownloads<Data>()
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

  public struct AlreadyInstalling: Error, CustomStringConvertible {
    public var description: String { "A data pack is already being installed." }
  }

  public struct DownloadFailed: Error, CustomStringConvertible {
    public let url: URL
    public let status: Int
    public var description: String { "\(url.absoluteString) answered HTTP \(status)" }
  }

  /// The app's store: Application Support/RFCReader for what it keeps, and
  /// Caches/RFCReader for what it can make again.
  public init() {
    let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[
      0]
    let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
    self.init(
      directory: support.appending(path: "RFCReader", directoryHint: .isDirectory),
      caches: caches.appending(path: "RFCReader", directoryHint: .isDirectory))
  }

  /// A store keeping its documents, index and packs in `directory`, and the index
  /// snapshot in `caches`. Both are created when they do not exist.
  public init(directory: URL, caches: URL) {
    self.directory = directory
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try? FileManager.default.createDirectory(at: caches, withIntermediateDirectories: true)
    snapshotURL = caches.appending(path: "rfc-index.json")
  }

  // MARK: - Index

  private nonisolated var indexURL: URL { directory.appending(path: "rfc-index.xml") }
  private nonisolated var checkURL: URL { directory.appending(path: "rfc-index-check.json") }

  /// The cached index's XML, when it was written, and its snapshot when that is current.
  public struct CachedIndex: Sendable {
    public let url: URL
    public let updatedAt: Date
    public let snapshot: URL?
  }

  /// Where the cached index is, when it was written, and its snapshot when that is
  /// current: the RFC Editor's copy in the cache, or else the one bundled with the
  /// app. Nil when there is neither. See `IndexSnapshot`.
  ///
  /// Only a lookup, and nonisolated: the caller reads it, off this actor (#367).
  /// Read here, the index held the store for as long as the parse took, so a
  /// document opened during launch — an `rfc://` link — waited behind it.
  public nonisolated func cachedIndexLocation() -> CachedIndex? {
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
  public func storeIndex(_ data: Data, parsed index: RFCIndex, validators: CacheValidators?)
    async throws
  {
    await snapshotWrite?.value
    try data.write(to: indexURL, options: .atomic)
    writeSnapshot(of: index)
    try storeCheck(IndexCheck(checkedAt: .now, fetchedAt: .now, validators: validators))
  }

  /// The last check of the index kept on disk, or nil when there is no index on
  /// disk to have checked: the validators describe that file, and nothing else.
  public nonisolated func indexCheck() -> IndexCheck? {
    guard FileManager.default.fileExists(atPath: indexURL.path),
      let data = try? Data(contentsOf: checkURL)
    else { return nil }
    return try? JSONDecoder().decode(IndexCheck.self, from: data)
  }

  /// Records that a check sent with `kept`'s validators found the index unchanged,
  /// and returns when.
  public func recordUnchangedIndex(_ kept: IndexCheck) throws -> Date {
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
  public func writeSnapshot(of index: RFCIndex) {
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
  public func cachedRevisions() -> RFCRevisions? {
    guard let data = try? Data(contentsOf: revisionsURL) else { return nil }
    return try? RFCRevisions.decode(data)
  }

  public func storeRevisions(_ data: Data) throws {
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
  public func cachedRegistries(maximumAge: TimeInterval) -> (
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

  public func storeRegistry(_ data: Data, for registry: IANARegistry) throws {
    try FileManager.default.createDirectory(
      at: registriesDirectory, withIntermediateDirectories: true)
    try data.write(to: registryURL(registry), options: .atomic)
  }

  // MARK: - Documents

  private func fileURL(_ id: DocumentID, format: FileFormat) -> URL {
    directory.appending(path: DocumentCacheIndex.fileName(for: id, format: format))
  }

  public func isCached(_ id: DocumentID) -> Bool {
    cachedDocuments.revalidate()
    return cachedDocuments.contains(id)
  }

  /// How much disk the cached body takes, or nil when there is none.
  public func downloadedSize(_ id: DocumentID) -> Int? {
    let sizes = DocumentCacheIndex.bodyFormats.compactMap { format in
      (try? fileURL(id, format: format).resourceValues(forKeys: [.fileSizeKey]))?.fileSize
    }
    return sizes.isEmpty ? nil : sizes.reduce(0, +)
  }

  /// Numbers of every RFC with a cached body.
  public func cachedNumbers() -> Set<Int> {
    cachedDocuments.revalidate()
    return cachedDocuments.rfcNumbers
  }

  /// A body that cannot be deleted is left where it is, and stays cached: the
  /// index records what the removal left on disk, not what it set out to do.
  public func remove(_ id: DocumentID) {
    downloads.removed(id)
    texts.removed(id)
    parses.removed(id)
    parsed.removeAll { $0 == id }
    let urls = DocumentCacheIndex.bodyFormats.map { fileURL(id, format: $0) }
    cachedDocuments.update(id) {
      for url in urls {
        try? FileManager.default.removeItem(at: url)
      }
    }
  }

  public func document(_ id: DocumentID, formats: [FileFormat], client: any DocumentFetching)
    async throws -> RFCDocument
  {
    let signpostID = signposter.makeSignpostID()
    let interval = signposter.beginInterval(
      "Load document", id: signpostID, "\(id.displayName, privacy: .public)")
    defer { signposter.endInterval("Load document", interval) }
    markOpened(id)
    if let cached = parsed.value(for: id) { return cached }

    if let cached = try await cachedDocument(id, signpostID: signpostID) { return cached }
    // A fetch another open started may have finished while the disk was read (#324).
    if let cached = parsed.value(for: id) { return cached }

    // The `.txt` is the document: the download Original Text shares (#324), parsed
    // here once it is on disk. Written by then unless a removal kept it off, even
    // when Original Text was the reader to write it.
    if RFCEditorClient.textIsTheDocument(availableFormats: formats) {
      let data: Data
      do {
        let fetchInterval = signposter.beginInterval(
          "Fetch document", id: signposter.makeSignpostID(), "\(id.displayName, privacy: .public)")
        defer { signposter.endInterval("Fetch document", fetchInterval) }
        data = try await text(id, client: client)
      }
      if let cached = try await cachedDocument(id, signpostID: signpostID) { return cached }
      // Removed while it downloaded: shown, and not kept (#116).
      return await Self.parseText(data, signpostID: signpostID)
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

  /// The body on disk, parsed and kept, or nil when there is none: the parse is
  /// joined by a second open, and a body removed while it parsed is shown but not
  /// kept, like a fetch (#116).
  private func cachedDocument(_ id: DocumentID, signpostID: OSSignpostID) async throws
    -> RFCDocument?
  {
    let xmlURL = fileURL(id, format: .xml)
    let textURL = fileURL(id, format: .text)
    let packURL = legacyPack?.file(for: id)
    let (cached, isCachedKept) = try await parses.value(for: id) {
      Task {
        await Self.parseCached(
          id, xml: xmlURL, pack: packURL, text: textURL, signpostID: signpostID)
      }
    }
    if let cached, isCachedKept { parsed.store(cached, for: id) }
    return cached
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
    return await parseText(data, signpostID: signpostID)
  }

  @concurrent
  private static func parseText(_ data: Data, signpostID: OSSignpostID) async -> RFCDocument {
    signposter.withIntervalSignpost(
      "Parse document", id: signpostID, "text", around: { LegacyTextParser.parse(data) })
  }

  /// Not cached: the XML when the index says it exists, otherwise the text, and the
  /// text only when there is no XML (#125). Off the actor, parse included, so the
  /// store answers other calls meanwhile.
  private static func fetch(_ id: DocumentID, formats: [FileFormat], client: any DocumentFetching)
    async throws -> RFCEditorClient.FetchedDocument
  {
    let interval = signposter.beginInterval(
      "Fetch document", id: signposter.makeSignpostID(), "\(id.displayName, privacy: .public)")
    defer { signposter.endInterval("Fetch document", interval) }
    let fetched = try await client.fetchPreferredDocument(id, availableFormats: formats)
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
  public func installLegacyPack(from source: URL) async throws -> InstalledPack {
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
  public var hasGrownSinceEviction: Bool { hasGrown }

  /// Removes the least recently opened bodies past `bound`, never a pinned one; see
  /// `CacheEviction`. Only after the cache has grown, so an ordinary open costs
  /// nothing here. Returns what it removed.
  @discardableResult
  public func evict(pinned: Set<DocumentID>, bound: Int) -> [DocumentID] {
    guard hasGrown else { return [] }
    hasGrown = false
    let victims = CacheEviction.victims(
      of: CacheEviction.entries(in: directory), pinned: pinned, bound: bound)
    for id in victims {
      remove(id)
    }
    return victims
  }

  public func originalText(_ id: DocumentID, client: any DocumentFetching) async throws -> String {
    if let data = try? Data(contentsOf: fileURL(id, format: .text)) {
      return LegacyTextParser.stripPagination(LegacyTextParser.text(decoding: data))
    }
    let data = try await text(id, client: client)
    return LegacyTextParser.stripPagination(LegacyTextParser.text(decoding: data))
  }

  /// The `.txt`, downloaded once for every reader that wants it at the same time,
  /// and written by the one told to keep it, with no suspension between, so a
  /// removal cannot slip in before the write, and the others find it on disk once
  /// they have it (#116).
  private func text(_ id: DocumentID, client: any DocumentFetching) async throws -> Data {
    let (data, isKept) = try await texts.value(for: id) {
      Task { try await client.fetchDocumentData(id, format: .text) }
    }
    if isKept {
      try cachedDocuments.update(id) {
        try data.write(to: fileURL(id, format: .text), options: .atomic)
      }
      hasGrown = true
    }
    return data
  }
}
