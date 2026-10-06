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
/// A body is stored in one of two tiers (#358): the kept tier, for documents wanted
/// offline, which is a promise and has no bound; and the reading cache, for
/// everything else read, which eviction bounds and the system may purge.
///
/// Here rather than in the App target for its tests, which run its sequences — a
/// second open joining the first, a removal during a download — against a fetcher
/// that waits until the test lets it finish (#596).
public actor DocumentStore {
  /// The index, the registries and the packs: what the app keeps besides bodies.
  private let directory: URL
  /// The kept tier's bodies, in a folder of `directory` excluded from backups,
  /// since they can be downloaded again.
  private let keptDirectory: URL
  /// The reading cache's bodies, in a folder of Caches of their own, so writing the
  /// index snapshot beside it does not send `cachedDocuments` to scan again.
  private let cacheDirectory: URL
  /// The bytes free on the disk for a body in each tier; see `StorageTier.hasRoom`.
  private let freeSpace: @Sendable (StorageTier) -> Int?

  /// The documents parsed last, so reopening one, or going back to it, skips the
  /// parse: 35 to 60 ms for the largest XML, half a second for RFC 5661's text
  /// (`make benchmark`). Bounded: it used to keep every document opened for as long
  /// as the app ran.
  private var parsed = RecentValues<DocumentID, RFCDocument>(capacity: 8)

  /// Which bodies are in each tier, scanned once on first use and kept current by
  /// every write, move and removal below, so asking does not enumerate a directory.
  /// Each question revalidates them first, which scans again only if a directory
  /// changed some other way, such as the system purging Caches.
  private lazy var keptDocuments = DocumentCacheIndex(scanning: keptDirectory)
  private lazy var cachedDocuments = DocumentCacheIndex(scanning: cacheDirectory)

  /// The documents wanted offline, as the app last said: the marked ones, and the
  /// bookmarked ones when the setting keeps them (`OfflineReconciler.wanted`). A
  /// body of one of these is written to the kept tier, whoever fetched it, so a
  /// marked document a reader opens before the reconciler has fetched it is kept,
  /// not cached.
  private var wanted: Set<DocumentID> = []

  /// The documents `keep(_:formats:client:)` is fetching, whose bodies go to the
  /// kept tier when they arrive, wanted or not: a keep tapped on this device writes
  /// where it is asked to before the mark it made reaches `wanted`.
  private var keeping: Set<DocumentID> = []

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

  /// Whether a body has been written to the cache since eviction last looked, so a
  /// cache that has not grown is not enumerated again.
  private var hasGrown = true

  /// Where the index snapshot lives: in Caches, because it is made again from one
  /// parse, so it stays out of backups.
  private let snapshotURL: URL

  /// The last snapshot write, which the next one waits for, so a snapshot of an
  /// older index never lands after a newer one.
  private var snapshotWrite: Task<Void, Never>?

  /// The installed data packs (#36), not part of either tier: a pack is installed
  /// and replaced whole, never evicted a document at a time.
  private var packsDirectory: URL {
    directory.appending(path: "Packs", directoryHint: .isDirectory)
  }

  /// The converted legacy RFCs, the one pack the app reads documents from. Nil
  /// until one is installed.
  private lazy var legacyPack: InstalledPack? = Self.installedPack(
    in: packsDirectory.appending(path: Self.legacyPackName, directoryHint: .isDirectory))
  private static let legacyPackName = "legacy-xml"
  /// The corpus's index database (#174), which reading paths read (#189).
  private static let indexesPackName = "indexes"
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

  /// A store keeping its index, packs and kept bodies in `directory`, and the
  /// index snapshot and the reading cache in `caches`. Both are created when they
  /// do not exist. `freeSpace` is the bytes free for a body in each tier, read from
  /// the volume when it is nil.
  public init(
    directory: URL, caches: URL, freeSpace: (@Sendable (StorageTier) -> Int?)? = nil
  ) {
    let keptDirectory = directory.appending(path: "Offline", directoryHint: .isDirectory)
    let cacheDirectory = caches.appending(path: "Documents", directoryHint: .isDirectory)
    self.directory = directory
    self.keptDirectory = keptDirectory
    self.cacheDirectory = cacheDirectory
    self.freeSpace =
      freeSpace ?? { tier in
        Self.volumeFreeSpace(for: tier, at: tier == .kept ? keptDirectory : cacheDirectory)
      }
    for folder in [directory, caches] {
      try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }
    try? Self.createFolder(keptDirectory, for: .kept)
    try? Self.createFolder(cacheDirectory, for: .cache)
    snapshotURL = caches.appending(path: "rfc-index.json")
  }

  /// What the volume holding `folder` has free: for important usage for the kept
  /// tier, for opportunistic usage for the cache; see `StorageTier.freeSpace`.
  /// Asked afresh each time, since a URL may answer from values cached on it.
  private static func volumeFreeSpace(for tier: StorageTier, at folder: URL) -> Int? {
    var url = folder
    url.removeAllCachedResourceValues()
    let usageKey: URLResourceKey =
      switch tier {
      case .kept: .volumeAvailableCapacityForImportantUsageKey
      case .cache: .volumeAvailableCapacityForOpportunisticUsageKey
      }
    let values = try? url.resourceValues(forKeys: [usageKey, .volumeAvailableCapacityKey])
    let usage =
      switch tier {
      case .kept: values?.volumeAvailableCapacityForImportantUsage
      case .cache: values?.volumeAvailableCapacityForOpportunisticUsage
      }
    return StorageTier.freeSpace(
      forUsage: usage, available: values?.volumeAvailableCapacity.map(Int64.init))
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

  // MARK: - Bookmark baseline

  private var bookmarkBaselineURL: URL { directory.appending(path: "bookmark-baseline.json") }

  /// What the bookmarked RFCs looked like at the last comparison (#191). Nil when
  /// there is none, or it no longer decodes, which the next comparison takes as a
  /// first one: it reports nothing and starts again from what it sees.
  public func bookmarkBaseline() -> BookmarkBaseline? {
    guard let data = try? Data(contentsOf: bookmarkBaselineURL) else { return nil }
    return try? BookmarkBaseline.decode(data)
  }

  public func storeBookmarkBaseline(_ baseline: BookmarkBaseline) throws {
    try baseline.encoded().write(to: bookmarkBaselineURL, options: .atomic)
  }

  // MARK: - Working groups

  private var workingGroupsURL: URL { directory.appending(path: "groups.json") }

  /// The last good `groups.json` (#363), as `cachedRevisions()` keeps its file.
  public func cachedWorkingGroups() -> WorkingGroups? {
    guard let data = try? Data(contentsOf: workingGroupsURL) else { return nil }
    return try? WorkingGroups.decode(data)
  }

  public func storeWorkingGroups(_ data: Data) throws {
    try data.write(to: workingGroupsURL, options: .atomic)
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

  /// The tiers in the order a body is looked for: a document has a body in one of
  /// them, but one left in both is read from the tier it was kept in.
  private static let tiers: [StorageTier] = [.kept, .cache]

  private func folder(of tier: StorageTier) -> URL {
    switch tier {
    case .kept: keptDirectory
    case .cache: cacheDirectory
    }
  }

  private func fileURL(_ id: DocumentID, format: FileFormat, in tier: StorageTier) -> URL {
    folder(of: tier).appending(path: DocumentCacheIndex.fileName(for: id, format: format))
  }

  /// `id`'s bodies in `format`, in the order they are read.
  private func fileURLs(_ id: DocumentID, format: FileFormat) -> [URL] {
    Self.tiers.map { fileURL(id, format: format, in: $0) }
  }

  /// Runs `change`, which writes, moves or deletes `id`'s bodies in `tier`, and
  /// records what that tier holds afterwards; see `DocumentCacheIndex.update`.
  private func update(_ id: DocumentID, in tier: StorageTier, by change: () throws -> Void)
    rethrows
  {
    switch tier {
    case .kept: try keptDocuments.update(id, by: change)
    case .cache: try cachedDocuments.update(id, by: change)
    }
  }

  /// Whether `id` has a body in either tier.
  public func isCached(_ id: DocumentID) -> Bool {
    cachedDocuments.revalidate()
    return isKept(id) || cachedDocuments.contains(id)
  }

  /// Whether `id` has a body in the kept tier.
  public func isKept(_ id: DocumentID) -> Bool {
    keptDocuments.revalidate()
    return keptDocuments.contains(id)
  }

  /// How much disk the body takes, in the tier it is read from, or nil when there is
  /// none.
  public func downloadedSize(_ id: DocumentID) -> Int? {
    for tier in Self.tiers {
      let sizes = DocumentCacheIndex.bodyFormats.compactMap {
        (try? fileURL(id, format: $0, in: tier).resourceValues(forKeys: [.fileSizeKey]))?.fileSize
      }
      if !sizes.isEmpty { return sizes.reduce(0, +) }
    }
    return nil
  }

  /// Numbers of every RFC with a body in the kept tier.
  public func keptNumbers() -> Set<Int> {
    keptDocuments.revalidate()
    return keptDocuments.rfcNumbers
  }

  /// Sets the documents wanted offline: where a body fetched from now on is
  /// written. Moves nothing; the reconciler's plan does that.
  public func setWanted(_ documents: Set<DocumentID>) {
    wanted = documents
  }

  /// What `OfflineReconciler.plan` reads of the disk and the network.
  public struct OfflineState: Sendable, Hashable {
    /// The documents with a body in the kept tier.
    public var kept: Set<DocumentID>
    /// The documents with a body in the cache.
    public var cached: Set<DocumentID>
    /// Every document with a download running, of its body or its text.
    public var running: Set<DocumentID>
  }

  public func offlineState() -> OfflineState {
    keptDocuments.revalidate()
    cachedDocuments.revalidate()
    return OfflineState(
      kept: keptDocuments.all, cached: cachedDocuments.all,
      running: downloads.runningDocuments.union(texts.runningDocuments))
  }

  /// Removes `id`'s bodies from both tiers. A body that cannot be deleted is left
  /// where it is, and stays cached: the index records what the removal left on
  /// disk, not what it set out to do.
  public func remove(_ id: DocumentID) {
    keeping.remove(id)
    remove(id, from: Self.tiers)
  }

  private func remove(_ id: DocumentID, from tiers: [StorageTier]) {
    downloads.removed(id)
    texts.removed(id)
    parses.removed(id)
    parsed.removeAll { $0 == id }
    for tier in tiers {
      let urls = DocumentCacheIndex.bodyFormats.map { fileURL(id, format: $0, in: tier) }
      update(id, in: tier) {
        for url in urls {
          try? FileManager.default.removeItem(at: url)
        }
      }
    }
  }

  /// The disk has no room to keep a document offline.
  public struct NotEnoughSpace: Error, CustomStringConvertible {
    public let id: DocumentID
    public var description: String { "There is no room on the disk to keep \(id.displayName)." }
  }

  /// Keeps `id` offline: moves its body into the kept tier, or fetches it there
  /// when neither tier has one. Throws `NotEnoughSpace` when the disk has no room
  /// for it, and a fetch's error when the fetch fails.
  public func keep(_ id: DocumentID, formats: [FileFormat], client: any DocumentFetching)
    async throws
  {
    if isKept(id) { return }
    if isCached(id) {
      try move(id, to: .kept)
      return
    }
    keeping.insert(id)
    defer { keeping.remove(id) }
    if RFCEditorClient.textIsTheDocument(availableFormats: formats) {
      _ = try await text(id, client: client)
    } else {
      _ = try await fetchDocument(id, formats: formats, client: client)
    }
    // Released, or removed, while it was fetched: nothing was promised.
    guard keeping.contains(id) else { return }
    guard isKept(id) else { throw NotEnoughSpace(id: id) }
  }

  /// Stops keeping `id` offline: its body goes back into the cache, where eviction
  /// treats it as any other, rather than being deleted.
  public func release(_ id: DocumentID) {
    keeping.remove(id)
    do {
      try move(id, to: .cache)
    } catch {
      storeLog.error(
        "\(id.displayName, privacy: .public): not moved into the cache: \(String(describing: error), privacy: .public)"
      )
    }
  }

  /// Moves `id`'s bodies from the other tier into `tier`, replacing any already
  /// there, so a document with a body in both ends with one. A move within one
  /// volume takes no room, so the disk is not asked.
  private func move(_ id: DocumentID, to tier: StorageTier) throws {
    let source: StorageTier = tier == .kept ? .cache : .kept
    let files = FileManager.default
    try createFolder(of: tier)
    try update(id, in: tier) {
      for format in DocumentCacheIndex.bodyFormats {
        let origin = fileURL(id, format: format, in: source)
        guard files.fileExists(atPath: origin.path) else { continue }
        let destination = fileURL(id, format: format, in: tier)
        try? files.removeItem(at: destination)
        try files.moveItem(at: origin, to: destination)
      }
    }
    // Records what the source holds afterwards, which the moves above changed.
    update(id, in: source) {}
    if tier == .cache { hasGrown = true }
  }

  /// Writes `data` as `id`'s body in `format`, in the tier it belongs in, when the
  /// disk has room for it there; see `StorageTier.hasRoom`. A body with no room is
  /// not written, and the document is fetched again on its next open.
  private func write(_ data: Data, for id: DocumentID, format: FileFormat) throws {
    // A body already kept stays where it is until the reconciler releases it.
    let tier = isKept(id) ? .kept : StorageTier.of(id, wanted: wanted.union(keeping))
    guard tier.hasRoom(for: data.count, available: freeSpace(tier)) else {
      storeLog.notice(
        "\(id.displayName, privacy: .public): not written, the disk is too full")
      return
    }
    let url = fileURL(id, format: format, in: tier)
    try createFolder(of: tier)
    try update(id, in: tier) { try data.write(to: url, options: .atomic) }
    if tier == .cache { hasGrown = true }
  }

  /// Makes `tier`'s folder again when it is gone: the system purges Caches while
  /// the app runs, the folder with it.
  private func createFolder(of tier: StorageTier) throws {
    try Self.createFolder(folder(of: tier), for: tier)
  }

  /// Makes `folder` for `tier`'s bodies, excluding the kept tier's from backups,
  /// since its bodies can be downloaded again.
  private static func createFolder(_ folder: URL, for tier: StorageTier) throws {
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    guard tier == .kept else { return }
    var excluded = URLResourceValues()
    excluded.isExcludedFromBackup = true
    var url = folder
    try url.setResourceValues(excluded)
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
    // A body moved between the tiers while the parse looked in each in turn is in
    // the other one now, and a second look finds it.
    if isCached(id), let cached = try await cachedDocument(id, signpostID: signpostID) {
      return cached
    }

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

    return try await fetchDocument(id, formats: formats, client: client)
  }

  /// Fetches `id`'s preferred document, joining a fetch already running, and writes
  /// it to the tier it belongs in.
  private func fetchDocument(
    _ id: DocumentID, formats: [FileFormat], client: any DocumentFetching
  ) async throws -> RFCDocument {
    let (fetched, isKept) = try await downloads.value(for: id) {
      Task { try await Self.fetch(id, formats: formats, client: client) }
    }
    // A removal while this was in flight, or another reader of the same fetch has
    // kept it: the document is shown, and not written here (#116).
    guard isKept else { return fetched.document }
    try write(fetched.data, for: id, format: fetched.format)
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
    let xmlURLs = fileURLs(id, format: .xml)
    let textURLs = fileURLs(id, format: .text)
    let packURL = legacyPack?.file(for: id)
    let (cached, isCachedKept) = try await parses.value(for: id) {
      Task {
        await Self.parseCached(
          id, xml: xmlURLs, pack: packURL, text: textURLs, signpostID: signpostID)
      }
    }
    if let cached, isCachedKept { parsed.store(cached, for: id) }
    return cached
  }

  /// The body on disk, parsed: the XML of either tier if there is one, then the
  /// installed pack's, otherwise the text of either tier, or nil when none is there.
  /// Off the actor, like a fetch's parse, so the store answers other calls meanwhile
  /// -- whether a document is available offline, the next open -- instead of
  /// queueing them behind half a second of legacy text.
  @concurrent
  private static func parseCached(
    _ id: DocumentID, xml: [URL], pack: URL?, text: [URL], signpostID: OSSignpostID
  ) async -> RFCDocument? {
    for url in xml {
      if let data = try? Data(contentsOf: url),
        let document = try? signposter.withIntervalSignpost(
          "Parse document", id: signpostID, "XML", around: { try RFCXMLParser.parse(data) })
      {
        return document
      }
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
    guard let data = text.lazy.compactMap({ try? Data(contentsOf: $0) }).first else {
      return nil
    }
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
    let pack = try await installPack(source, as: Self.legacyPackName)
    legacyPack = pack
    // Parsed again on their next open, from the pack; nothing else it could serve.
    parsed.removeAll { pack.file(for: $0) != nil }
    return pack
  }

  /// Installs the `indexes` pack, as `installLegacyPack(from:)` installs the legacy
  /// one. A reader opens its database afresh for each question, so nothing here
  /// holds the one it replaces.
  public func installIndexesPack(from source: URL) async throws -> InstalledPack {
    try await installPack(source, as: Self.indexesPackName)
  }

  /// One install at a time, whichever pack.
  private func installPack(_ source: URL, as name: String) async throws -> InstalledPack {
    // Checked and set without a suspension between them, so a second install
    // arriving while the first is off the actor is refused rather than raced.
    guard !isInstallingPack else { throw AlreadyInstalling() }
    isInstallingPack = true
    defer { isInstallingPack = false }
    return try await Self.install(source, as: name, in: packsDirectory)
  }

  /// The installed `indexes` pack's citation database, or nil when no pack is
  /// installed or its manifest does not list one. Read from the disk on each call:
  /// it is asked once per reading path.
  public func citationIndexURL() -> URL? {
    let directory = packsDirectory.appending(
      path: Self.indexesPackName, directoryHint: .isDirectory)
    guard let pack = Self.installedPack(in: directory),
      pack.manifest.files.contains(where: { $0.path == CitationIndex.fileName })
    else { return nil }
    return directory.appending(path: CitationIndex.fileName)
  }

  /// The RFCs the installed legacy pack lists as text that only points to its
  /// original (#316), shown as their original without a load.
  public func pointersInPack() -> Set<DocumentID> {
    legacyPack?.pointers ?? []
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
  /// does not send `DocumentCacheIndex` to scan again. Public for a document opened
  /// without a load: a pointer the installed pack lists (#316).
  public func markOpened(_ id: DocumentID) {
    for format in DocumentCacheIndex.bodyFormats {
      for url in fileURLs(id, format: format) {
        try? FileManager.default.setAttributes(
          [.modificationDate: Date.now], ofItemAtPath: url.path)
      }
    }
  }

  /// Whether a body has been written to the cache since eviction last ran: asked
  /// before the caller builds the pinned set, which is not free.
  public var hasGrownSinceEviction: Bool { hasGrown }

  /// Removes the least recently opened bodies of the cache past `bound`, never a
  /// pinned one; see `CacheEviction`. The kept tier is never looked at. Only after
  /// the cache has grown, so an ordinary open costs nothing here. Returns what it
  /// removed.
  @discardableResult
  public func evict(pinned: Set<DocumentID>, bound: Int) -> [DocumentID] {
    guard hasGrown else { return [] }
    hasGrown = false
    let victims = CacheEviction.victims(
      of: CacheEviction.entries(in: cacheDirectory), pinned: pinned, bound: bound)
    for id in victims {
      remove(id, from: [.cache])
    }
    return victims
  }

  public func originalText(_ id: DocumentID, client: any DocumentFetching) async throws -> String {
    if let data = fileURLs(id, format: .text).lazy.compactMap({ try? Data(contentsOf: $0) }).first {
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
      try write(data, for: id, format: .text)
    }
    return data
  }

  // MARK: - Tests

  /// How many readers wait for the fetch of `id`'s document, and for its `.txt`, so
  /// a test acts once the readers it started have joined them.
  func waiters(_ id: DocumentID) -> (documents: Int, texts: Int) {
    (downloads.waiters(id), texts.waiters(id))
  }
}
