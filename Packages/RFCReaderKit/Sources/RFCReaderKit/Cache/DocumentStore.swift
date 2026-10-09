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
  /// Awaited at the start of each look at the disk for a body to parse: nil but in
  /// tests.
  private let parsing: (@Sendable () async -> Void)?

  /// The documents parsed last, so reopening one, or going back to it, skips the
  /// parse: 35 to 60 ms for the largest XML, half a second for RFC 5661's text
  /// (`make benchmark`). Bounded: it used to keep every document opened for as long
  /// as the app ran.
  private var parsed = RecentValues<DocumentID, Parse>(capacity: 8)

  /// A document as parsed, with the index entry its parse was given: nil for one
  /// parsed before the index arrived, or read from XML, which takes none (#767).
  private struct Parse: Sendable {
    let document: RFCDocument
    let entry: RFCMetadata?
  }

  /// Which bodies are in each tier, scanned once on first use and kept current by
  /// every write, move and removal below, so asking does not enumerate a directory.
  /// Each question revalidates them first, which scans again only if a directory
  /// changed some other way, such as the system purging Caches.
  private lazy var keptDocuments = DocumentCacheIndex(scanning: keptDirectory)
  private lazy var cachedDocuments = DocumentCacheIndex(scanning: cacheDirectory)

  /// The documents wanted offline, as the app last said. A body of one of these is
  /// written to the kept tier, whoever fetched it, and eviction leaves it be, so a
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
  private let downloads = InFlightDownloads<
    (fetched: RFCEditorClient.FetchedDocument, entry: RFCMetadata?)
  >()
  private let texts = InFlightDownloads<Data>()
  /// The parses of cached bodies running, for the same three reasons: a parse
  /// suspends the open, so the actor lets a second open or a removal in meanwhile.
  /// A pack installed meanwhile marks the parses of the documents it serves as a
  /// removal does, so none of them is kept.
  private let parses = InFlightDownloads<Parse?>()
  /// How many removals each document has had, so a download started again for a
  /// reader whose joined one the path refused knows whether one came meanwhile.
  private var removals: [DocumentID: Int] = [:]

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
    self.init(directory: directory, caches: caches, freeSpace: freeSpace, parsing: nil)
  }

  /// The store above, with `parsing` awaited at the start of each look at the disk
  /// for a body to parse, once it has chosen which files to read, whether or not one
  /// is there: for a test to hold the parse open as it holds a fetch.
  init(
    directory: URL, caches: URL, freeSpace: (@Sendable (StorageTier) -> Int?)?,
    parsing: (@Sendable () async -> Void)?
  ) {
    self.parsing = parsing
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
    Self.check(of: indexURL, keptAt: checkURL)
  }

  /// The check kept at `checkURL` of the file at `file`, or nil when the file is gone:
  /// a check describes that file, and nothing else.
  private nonisolated static func check(of file: URL, keptAt checkURL: URL) -> IndexCheck? {
    guard FileManager.default.fileExists(atPath: file.path),
      let data = try? Data(contentsOf: checkURL)
    else { return nil }
    return try? JSONDecoder().decode(IndexCheck.self, from: data)
  }

  /// Records that a check sent with `kept`'s validators found the index unchanged,
  /// and returns when.
  public func recordUnchangedIndex(_ kept: IndexCheck) throws -> Date {
    try Self.recordUnchanged(kept, at: checkURL)
  }

  private func storeCheck(_ check: IndexCheck) throws {
    try Self.store(check, at: checkURL)
  }

  private static func store(_ check: IndexCheck, at url: URL) throws {
    try JSONEncoder().encode(check).write(to: url, options: .atomic)
  }

  /// `kept` checked again now and found unchanged, kept at `url`; returns when.
  private static func recordUnchanged(_ kept: IndexCheck, at url: URL) throws -> Date {
    var check = kept
    check.checkedAt = .now
    try store(check, at: url)
    return check.checkedAt
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

  // MARK: - Errata

  private nonisolated var errataURL: URL { directory.appending(path: "errata.json") }
  private nonisolated var errataCheckURL: URL { directory.appending(path: "errata-check.json") }

  /// The errata feed kept (#387), as the RFC Editor served it, for the caller to
  /// decode off the main actor; nil when none is kept. Read on this actor, not the
  /// caller's: the feed is the size of the index.
  public func cachedErrata() -> Data? {
    try? Data(contentsOf: errataURL)
  }

  /// The last check of the feed kept, as `indexCheck()` is the index's: nil when no
  /// feed is kept for the validators to describe.
  public nonisolated func errataCheck() -> IndexCheck? {
    Self.check(of: errataURL, keptAt: errataCheckURL)
  }

  /// Keeps a fetched feed and what identifies it for the next check.
  public func storeErrata(_ data: Data, validators: CacheValidators?) throws {
    try data.write(to: errataURL, options: .atomic)
    try Self.store(
      IndexCheck(checkedAt: .now, fetchedAt: .now, validators: validators), at: errataCheckURL)
  }

  /// Records that a check sent with `kept`'s validators found the feed unchanged.
  public func recordUnchangedErrata(_ kept: IndexCheck) throws {
    _ = try Self.recordUnchanged(kept, at: errataCheckURL)
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

  /// Until the downloads running now for `documents`, of a body or a text, have
  /// ended: what the reconciler waits for before it moves a body it had to leave.
  public func untilDownloadsEnd(of documents: Set<DocumentID>) async {
    for id in documents {
      await downloads.ended(id)
      await texts.ended(id)
    }
  }

  /// Removes `id`'s bodies from both tiers. A body that cannot be deleted is left
  /// where it is, and stays cached: the index records what the removal left on
  /// disk, not what it set out to do.
  public func remove(_ id: DocumentID) {
    keeping.remove(id)
    remove(id, from: Self.tiers)
  }

  private func remove(_ id: DocumentID, from tiers: [StorageTier]) {
    removals[id, default: 0] += 1
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
    // Kept first: a document already kept needs no move, and one that failed would
    // fail a keep that has nothing left to do.
    if isKept(id) { return }
    if try keepCached(id) { return }
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

  /// Moves `id`'s cached body into the kept tier, replacing one already there, so
  /// a document with a body in both ends with one. Fetches nothing: a body no
  /// longer in the cache, evicted or purged since it was asked for, leaves this
  /// with nothing to do. Answers whether there was a body to move.
  @discardableResult
  public func keepCached(_ id: DocumentID) throws -> Bool {
    cachedDocuments.revalidate()
    guard cachedDocuments.contains(id) else { return false }
    try move(id, to: .kept)
    return true
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
  ///
  /// A body is moved in beside the one it replaces, under a name of its own, and
  /// only then swapped in: a move that fails leaves the destination's body as it
  /// was, rather than deleted with nothing in its place.
  private func move(_ id: DocumentID, to tier: StorageTier) throws {
    let source: StorageTier = tier == .kept ? .cache : .kept
    let files = FileManager.default
    try createFolder(of: tier)
    try update(id, in: tier) {
      for format in DocumentCacheIndex.bodyFormats {
        let origin = fileURL(id, format: format, in: source)
        guard files.fileExists(atPath: origin.path) else { continue }
        let destination = fileURL(id, format: format, in: tier)
        guard files.fileExists(atPath: destination.path) else {
          try files.moveItem(at: origin, to: destination)
          continue
        }
        let incoming = destination.deletingLastPathComponent()
          .appending(path: ".\(UUID().uuidString)-\(destination.lastPathComponent)")
        try files.moveItem(at: origin, to: incoming)
        do {
          _ = try files.replaceItemAt(destination, withItemAt: incoming)
        } catch {
          try? files.removeItem(at: incoming)
          throw error
        }
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

  /// `entry` is the document's index entry, where the app holds one: a legacy RFC
  /// read from its text takes its header from it (#767), applied as it is handed out,
  /// so a parse kept from before the index arrived shows the entry's header too. Its
  /// title is chosen once: against the page where the parse had no entry, and by the
  /// parse where it had one, as the converter chooses it.
  public func document(
    _ id: DocumentID, formats: [FileFormat], entry: RFCMetadata? = nil,
    client: any DocumentFetching
  ) async throws -> RFCDocument {
    let parse = try await load(id, formats: formats, entry: entry, client: client)
    guard let entry, parse.document.source == .text else { return parse.document }
    guard parse.entry != nil else { return LegacyTextParser.applying(entry, to: parse.document) }
    var document = parse.document
    _ = IndexHeader.apply(entry, to: &document.header)
    return document
  }

  /// `document(_:formats:entry:client:)`'s parse, before the entry is applied. The
  /// entry is passed to a parse that runs, so the title the page sets is kept out of
  /// the lead-in as the converter keeps it.
  private func load(
    _ id: DocumentID, formats: [FileFormat], entry: RFCMetadata?, client: any DocumentFetching
  ) async throws -> Parse {
    let signpostID = signposter.makeSignpostID()
    let interval = signposter.beginInterval(
      "Load document", id: signpostID, "\(id.displayName, privacy: .public)")
    defer { signposter.endInterval("Load document", interval) }
    markOpened(id)
    if let cached = parsed.value(for: id) { return cached }

    if let cached = try await cachedDocument(id, entry: entry, signpostID: signpostID) {
      return cached
    }
    // A fetch another open started may have finished while the disk was read (#324).
    if let cached = parsed.value(for: id) { return cached }
    // A body moved between the tiers while the parse looked in each in turn is in
    // the other one now, and a second look finds it.
    if isCached(id),
      let cached = try await cachedDocument(id, entry: entry, signpostID: signpostID)
    {
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
      if let cached = try await cachedDocument(id, entry: entry, signpostID: signpostID) {
        return cached
      }
      // Removed while it downloaded: shown, and not kept (#116).
      return await Self.parseText(data, entry: entry, signpostID: signpostID)
    }

    return try await fetchDocument(id, formats: formats, entry: entry, client: client)
  }

  /// Fetches `id`'s preferred document, joining a fetch already running, and writes
  /// it to the tier it belongs in.
  private func fetchDocument(
    _ id: DocumentID, formats: [FileFormat], entry: RFCMetadata? = nil,
    client: any DocumentFetching
  ) async throws -> Parse {
    // With the entry the fetch was started with: a fetch this open joined was given another's.
    let (download, isKept) = try await value(of: downloads, for: id) {
      Task {
        (try await Self.fetch(id, formats: formats, entry: entry, client: client), entry)
      }
    }
    let fetched = download.fetched
    let parse = Parse(document: fetched.document, entry: download.entry)
    // A removal while this was in flight, or another reader of the same fetch has
    // kept it: the document is shown, and not written here (#116).
    guard isKept else { return parse }
    try write(fetched.data, for: id, format: fetched.format)
    // A pack installed while this was in flight serves the document from now on.
    if legacyPack?.file(for: id) == nil {
      parsed.store(parse, for: id)
    }
    return parse
  }

  /// The body on disk, parsed and kept, or nil when there is none: the parse is
  /// joined by a second open, and a body removed while it parsed is shown but not
  /// kept, like a fetch (#116), and so is one parsed from what a pack installed
  /// meanwhile replaces: every open that joins it before it ends, even after the
  /// install, shows it, and the first open after it ends reads the pack.
  private func cachedDocument(
    _ id: DocumentID, entry: RFCMetadata?, signpostID: OSSignpostID
  ) async throws -> Parse? {
    let xmlURLs = fileURLs(id, format: .xml)
    let textURLs = fileURLs(id, format: .text)
    let packURL = legacyPack?.file(for: id)
    let parsing = parsing
    let (cached, isCachedKept) = try await parses.value(for: id) {
      Task {
        await parsing?()
        return await Self.parseCached(
          id, from: Bodies(xml: xmlURLs, pack: packURL, text: textURLs), entry: entry,
          signpostID: signpostID)
      }
    }
    if let cached, isCachedKept { parsed.store(cached, for: id) }
    return cached
  }

  /// Where a document's body may be on disk: its XML and its text in either tier, and
  /// the installed pack's file.
  private struct Bodies {
    let xml: [URL]
    let pack: URL?
    let text: [URL]
  }

  /// The body on disk, parsed: the XML of either tier if there is one, then the
  /// installed pack's, otherwise the text of either tier, or nil when none is there.
  /// Off the actor, like a fetch's parse, so the store answers other calls meanwhile
  /// -- whether a document is available offline, the next open -- instead of
  /// queueing them behind half a second of legacy text.
  @concurrent
  private static func parseCached(
    _ id: DocumentID, from bodies: Bodies, entry: RFCMetadata?, signpostID: OSSignpostID
  ) async -> Parse? {
    for url in bodies.xml {
      if let data = try? Data(contentsOf: url),
        let document = try? signposter.withIntervalSignpost(
          "Parse document", id: signpostID, "XML", around: { try RFCXMLParser.parse(data) })
      {
        return Parse(document: document, entry: nil)
      }
    }
    // Before a cached `.txt`: the pack is the single XML path it exists for, and a
    // `.txt` cached before it arrived still serves Original Text.
    if let pack = bodies.pack {
      do {
        return Parse(document: try RFCXMLParser.parse(Data(contentsOf: pack)), entry: nil)
      } catch {
        storeLog.error(
          "\(id.displayName, privacy: .public): not read from the data pack: \(String(describing: error), privacy: .public)"
        )
      }
    }
    guard let data = bodies.text.lazy.compactMap({ try? Data(contentsOf: $0) }).first else {
      return nil
    }
    return await parseText(data, entry: entry, signpostID: signpostID)
  }

  @concurrent
  private static func parseText(_ data: Data, entry: RFCMetadata?, signpostID: OSSignpostID)
    async -> Parse
  {
    let document = signposter.withIntervalSignpost(
      "Parse document", id: signpostID, "text",
      around: { LegacyTextParser.parse(data, entry: entry) })
    return Parse(document: document, entry: entry)
  }

  /// Not cached: the XML when the index says it exists, otherwise the text, and the
  /// text only when there is no XML (#125). Off the actor, parse included, so the
  /// store answers other calls meanwhile.
  private static func fetch(
    _ id: DocumentID, formats: [FileFormat], entry: RFCMetadata?, client: any DocumentFetching
  ) async throws -> RFCEditorClient.FetchedDocument {
    let interval = signposter.beginInterval(
      "Fetch document", id: signposter.makeSignpostID(), "\(id.displayName, privacy: .public)")
    defer { signposter.endInterval("Fetch document", interval) }
    let fetched = try await client.fetchPreferredDocument(
      id, availableFormats: formats, entry: entry)
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
    // A parse running now read what the pack replaces, and is not kept either, by
    // whichever open joined it (#116).
    parsed.removeAll { pack.file(for: $0) != nil }
    for id in parses.runningDocuments where pack.file(for: id) != nil {
      parses.removed(id)
    }
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
  /// pinned one, nor one wanted offline, which is in the cache only until the
  /// reconciler moves it; see `CacheEviction`. The kept tier is never looked at.
  /// Only after the cache has grown, so an ordinary open costs nothing here.
  /// Returns what it removed.
  @discardableResult
  public func evict(pinned: Set<DocumentID>, bound: Int) -> [DocumentID] {
    guard hasGrown else { return [] }
    hasGrown = false
    let victims = CacheEviction.victims(
      of: CacheEviction.entries(in: cacheDirectory), pinned: pinned.union(wanted), bound: bound)
    for id in victims {
      remove(id, from: [.cache])
    }
    return victims
  }

  // MARK: - Storage (#358)

  /// What each tier holds: the documents kept offline, and the reading cache.
  public func storageUsage() -> (kept: StorageUsage, cache: StorageUsage) {
    (
      StorageUsage(CacheEviction.entries(in: keptDirectory)),
      StorageUsage(CacheEviction.entries(in: cacheDirectory))
    )
  }

  /// Empties the reading cache, as Settings' Clear Cache does, but for a body wanted
  /// offline, which is in the cache only until the reconciler moves it. The kept tier
  /// is not looked at. Returns what it removed.
  @discardableResult
  public func clearCache() -> Set<DocumentID> {
    cachedDocuments.revalidate()
    let victims = cachedDocuments.all.subtracting(wanted)
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
    let (data, isKept) = try await value(of: texts, for: id) {
      Task { try await client.fetchDocumentData(id, format: .text) }
    }
    if isKept {
      try write(data, for: id, format: .text)
    }
    return data
  }

  /// `downloads.value(for:start:)`, started again with `start` when the download
  /// joined was somebody else's and the path refused it (#358): the keeper fetches
  /// what nobody waits for on a session that may not use an expensive path, and a
  /// reader who joined it, whose own client may, should not fail because the device
  /// moved to one. Once, and only for a download this caller did not start, whose
  /// own client could only be refused again. A removal while the refused one ran
  /// leaves the second unkept, as it would have the first (#116).
  private func value<Value>(
    of downloads: InFlightDownloads<Value>, for id: DocumentID,
    start: () -> Task<Value, any Error>
  ) async throws -> (value: Value, isKept: Bool) {
    var isOwn = false
    let removalsBefore = removals[id]
    do {
      return try await downloads.value(for: id) {
        isOwn = true
        return start()
      }
    } catch let error as URLError where error.networkUnavailableReason != nil && !isOwn {
      let (value, isKept) = try await downloads.value(for: id, start: start)
      return (value, isKept && removals[id] == removalsBefore)
    }
  }

  // MARK: - Tests

  /// How many readers wait for the fetch of `id`'s document, for its `.txt`, and for
  /// the parse of its body on disk, so a test acts once the readers it started have
  /// joined them.
  func waiters(_ id: DocumentID) -> Waiters {
    Waiters(
      documents: downloads.waiters(id), texts: texts.waiters(id), parses: parses.waiters(id))
  }

  struct Waiters: Equatable {
    var documents: Int
    var texts: Int
    var parses: Int
  }
}
