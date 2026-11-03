import Foundation
import Observation
import RFCKit
import SwiftData
import os

private let repositoryLog = Logger(
  subsystem: Bundle.main.bundleIdentifier ?? "me.mazetti.rfc-reader", category: "library")

/// The documents' bodies on the device (#595): an RFC or a draft loaded through the
/// store, the reading cache's eviction (#39), Clear Cache and the storage report,
/// what is kept offline and why (#358), and the reading path read from the citation
/// index (#189).
///
/// The index stays where it is loaded, and is read through `index`: the formats a
/// fetch chooses from, and the members a series stands for (#656). What a window has
/// open comes through `openDocuments`, and the network path through `networkDecision`,
/// both App objects. A series is resolved to the RFC its reader shows before it comes
/// here.
@MainActor @Observable
public final class DocumentRepository {
  /// "Keep bookmarked documents offline", from Settings' Storage tab (#358). Per
  /// device, as storage is, so a default rather than synced user data.
  public private(set) var keepsBookmarksOffline: Bool

  /// The RFCs wanted offline, which is what the library lists, kept beside the marks
  /// rather than worked out on every read: the sidebar counts it as it draws.
  public private(set) var availableOfflineNumbers: Set<Int> = []

  /// Whether there is a citation index (#189), bundled with the app (#738) or
  /// installed, without which a reading path can only say there is none: the Reading
  /// Path items are offered only while it is true (#769), which a Debug build without
  /// the bundled pack is not.
  public private(set) var hasCitationIndex = false

  /// Where each document marked Keep Offline stands while its body is not on the
  /// device: waiting and why, downloading, or failed.
  public var offlineStatus: OfflineStatus { offlineKeeper.status }

  /// Called with the documents eviction or Clear Cache removed from the reading
  /// cache, for what the app keeps in memory of them.
  @ObservationIgnored public var onRemoved: ([DocumentID]) -> Void = { _ in }

  @ObservationIgnored private let store: DocumentStore
  @ObservationIgnored private let client: any DocumentFetching & DraftFetching
  /// The Internet-Drafts read (#728), apart from the RFCs.
  @ObservationIgnored private let drafts: DraftStore
  @ObservationIgnored private let userData: UserDataMirror
  @ObservationIgnored private let defaults: UserDefaults
  /// Whether the user's data fell back to a store in memory (#152), whose marks are
  /// not the ones saved.
  @ObservationIgnored private let isStoredInMemory: Bool
  @ObservationIgnored private let index: () -> RFCIndex?
  @ObservationIgnored private let openDocuments: () -> [ReadableDocument]
  @ObservationIgnored private let networkDecision: (FetchPolicy.Cause) -> FetchPolicy.Decision?
  /// The bytes the reading cache holds before eviction trims it.
  @ObservationIgnored private let cacheBound: Int

  /// Moves, releases and fetches bodies to match `wantedOffline`. Its fetches that
  /// nobody waits for take only a path that is neither metered nor in Low Data Mode,
  /// and fail rather than wait when the device moves to one.
  @ObservationIgnored private let offlineKeeper: OfflineKeeper

  /// - Parameters:
  ///   - client: for a fetch somebody waits for: an open, Keep Offline tapped,
  ///     Download Now.
  ///   - clientFailingOnExpensiveNetworks: for the keeper's fetches nobody waits for.
  ///   - index: the index, nil while it loads or after it failed.
  ///   - openDocuments: what the windows show, which eviction and Clear Cache spare.
  ///   - networkDecision: whether a fetch for a cause goes ahead now; nil until the
  ///     network path is known.
  ///   - cacheBound: the bytes the reading cache holds before eviction trims it.
  public init(
    store: DocumentStore, client: any DocumentFetching & DraftFetching,
    clientFailingOnExpensiveNetworks: any DocumentFetching, drafts: DraftStore,
    userData: UserDataMirror, defaults: UserDefaults = .standard, isStoredInMemory: Bool,
    index: @escaping () -> RFCIndex?, openDocuments: @escaping () -> [ReadableDocument],
    networkDecision: @escaping (FetchPolicy.Cause) -> FetchPolicy.Decision?,
    cacheBound: Int = CacheEviction.defaultBound
  ) {
    self.store = store
    self.client = client
    self.drafts = drafts
    self.userData = userData
    self.defaults = defaults
    self.isStoredInMemory = isStoredInMemory
    self.index = index
    self.openDocuments = openDocuments
    self.networkDecision = networkDecision
    self.cacheBound = cacheBound
    keepsBookmarksOffline =
      (defaults.object(forKey: ReaderPreferences.keepBookmarksOfflineKey) as? Bool)
      ?? ReaderPreferences.defaultKeepBookmarksOffline
    offlineKeeper = OfflineKeeper(
      store: store, client: client,
      clientFailingOnExpensiveNetworks: clientFailingOnExpensiveNetworks
    ) { id in
      index()?[id]?.formats ?? []
    }
  }

  // MARK: - Loading

  /// An RFC, or a draft's revision (#728): the newest when it names none.
  public func document(for document: ReadableDocument) async throws -> RFCDocument {
    switch document {
    case .rfc(let id):
      let entry = index()?[id]
      let rfc = try await store.document(
        id, formats: entry?.formats ?? [], entry: entry, client: client)
      await loaded(id)
      return rfc
    case .draft(let id):
      return try await drafts.document(id, client: client)
    }
  }

  /// The plain text of an RFC or a draft's revision (#728).
  public func originalText(for document: ReadableDocument) async throws -> String {
    switch document {
    case .rfc(let id):
      let text = try await store.originalText(id, client: client)
      await loaded(id)
      return text
    case .draft(let id):
      return try await drafts.originalText(id, client: client)
    }
  }

  /// The RFC Editor's own file of `id` in `format`, byte for byte, from the copy kept
  /// on disk when there is one: for an export of it (#377), and what a format row's
  /// Download saves, to Downloads on a Mac (#25) and to Files on iOS (#577).
  public func publishedFile(for id: DocumentID, format: FileFormat) async throws -> Data {
    let data = try await store.publishedFile(id, format: format, client: client)
    await loaded(id)
    return data
  }

  /// What Datatracker says of a draft (#728): its title, revisions and RFC, asked
  /// again once a day.
  public func draftInfo(for id: DraftID) async throws -> DraftInfo {
    try await drafts.info(for: id, client: client)
  }

  /// The revision `id` names, or the newest Datatracker knows of; `id` itself when
  /// neither Datatracker nor what is kept can say (#728).
  public func revision(of id: DraftID) async -> DraftID {
    (try? await drafts.revision(of: id, client: client)) ?? id
  }

  /// Records an RFC opened without a load as a load records it: a pointer the pack
  /// lists, shown as its original (#316).
  public func markOpened(_ id: DocumentID) async {
    await store.markOpened(id)
  }

  public func isDownloaded(_ id: DocumentID) async -> Bool {
    await store.isCached(id)
  }

  /// What follows a load of `id`'s body: the keeper told of a body written into the
  /// kept tier, and the cache brought back under its bound.
  private func loaded(_ id: DocumentID) async {
    await reconcileIfBodyKept(id)
    await evictIfGrown()
  }

  /// A load of a document wanted offline writes its body into the kept tier, which
  /// the keeper, and so the row's mark, learns of only by running again (#936). Only
  /// when the body is kept now: a load that wrote nothing does not start a run.
  private func reconcileIfBodyKept(_ id: DocumentID) async {
    guard isWantedOffline(id), !offlineKeeper.kept.contains(id) else { return }
    guard await store.isKept(id) else { return }
    reconcileOffline()
  }

  // MARK: - Eviction (#39)

  /// Asks the store first, so an open that wrote nothing costs neither the pinned
  /// set's fetches nor the cache's enumeration.
  private func evictIfGrown() async {
    guard await store.hasGrownSinceEviction else { return }
    // No pinned set, no eviction: an empty one would let it delete exactly the
    // documents it promises to keep. The cache has still grown, so the next open
    // tries again.
    let pinned: Set<DocumentID>
    do {
      pinned = try pinnedDocuments()
    } catch {
      repositoryLog.error(
        "eviction skipped, reading what it keeps failed: \(String(describing: error), privacy: .public)"
      )
      return
    }
    let evicted = await store.evict(pinned: pinned, bound: cacheBound)
    if !evicted.isEmpty { onRemoved(evicted) }
  }

  /// What eviction never removes (#39), `CacheEviction.pinned`.
  private func pinnedDocuments() throws -> Set<DocumentID> {
    let context = userData.container.mainContext
    let read = try ReadingPositionStore.read(
      since: CacheEviction.readCutoff(now: .now), in: context)
    let bookmarked = try BookmarkStore.bookmarkedDocuments(in: context)
    // Read here, as the store learns them only when the keeper first runs.
    let marked = try OfflineMarkStore.markedDocuments(in: context)
    // A document with annotations is kept as a bookmarked one is (#522).
    let annotated = try AnnotationStore.annotatedDocuments(in: context)
    return CacheEviction.pinned(
      bookmarked: bookmarked.union(annotated), read: read, marked: marked,
      open: Set(openDocuments().compactMap(\.rfc)), withMembers: withMembers(of:))
  }

  // MARK: - Storage (#358)

  /// What each tier holds, and what of the cache Clear Cache would remove, for
  /// Settings' Storage tab, once the keeper has made the moves asked of it so far; a
  /// fetch still running is counted when it lands. Nothing is clearable when what
  /// `sparedFromClearing` spares cannot be told, as Clear Cache then removes nothing.
  /// The drafts read are counted with the cache, and are clearable but for those
  /// open (#728).
  public func storageUsage() async -> StorageReport {
    await offlineKeeper.untilRunsEnd()
    let open = openDocuments()
    let spared = sparedFromClearing(open: open)
    let draftUsage = await drafts.storageUsage(sparing: Set(open.compactMap(\.draft)))
    var report = await store.storageUsage(sparing: spared ?? [])
    report.cache = report.cache.adding(draftUsage.cache)
    report.clearable =
      spared == nil
      ? StorageUsage(documents: 0, bytes: 0) : report.clearable.adding(draftUsage.clearable)
    return report
  }

  /// Empties the reading cache, but for what `sparedFromClearing` spares, and the
  /// drafts read, but for those open; when what to spare cannot be told, nothing is
  /// removed. The drafts open are read once the RFCs are cleared, so a draft opened
  /// meanwhile is spared too.
  public func clearCache() async {
    guard let spared = sparedFromClearing(open: openDocuments()) else { return }
    let removed = await store.clearCache(sparing: spared)
    if !removed.isEmpty { onRemoved(removed) }
    await drafts.clear(sparing: Set(openDocuments().compactMap(\.draft)))
  }

  /// What Clear Cache leaves in the reading cache, `CacheEviction.spared`. The marks
  /// are read here, as for eviction, since the store learns them only when the keeper
  /// runs; nil when they cannot be read, or when what is wanted offline is not known
  /// yet, which would spare none of the bookmarks kept offline, nor a marked BCP's
  /// members.
  private func sparedFromClearing(open: [ReadableDocument]) -> Set<DocumentID>? {
    guard userData.knowsWantedOffline(keepsBookmarks: keepsBookmarksOffline) else {
      repositoryLog.error(
        "Clear Cache spares everything, what is wanted offline has not been read")
      return nil
    }
    do {
      return CacheEviction.spared(
        marked: try OfflineMarkStore.markedDocuments(in: userData.container.mainContext),
        wantedOffline: wantedOffline, open: Set(open.compactMap(\.rfc)))
    } catch {
      repositoryLog.error(
        "Clear Cache spares everything, reading the marks failed: \(String(describing: error), privacy: .public)"
      )
      return nil
    }
  }

  /// The size of `id`'s kept body, once what keeping it offline started has ended:
  /// a mark from anywhere, the menu, a script or another device, fetches after it is
  /// made.
  public func keptSize(_ id: DocumentID) async -> Int? {
    await offlineKeeper.untilSettled(id)
    return await store.downloadedSize(id)
  }

  // MARK: - Keep Offline (#358)

  /// What is wanted offline: the marks, and the bookmarks when they are kept too.
  private var wantedOffline: Set<DocumentID> {
    OfflineReconciler.wanted(
      marks: withMembers(of: userData.offlineMarks),
      bookmarks: withMembers(of: userData.bookmarkedDocuments),
      keepsBookmarks: keepsBookmarksOffline)
  }

  /// `documents`, a series with its members: a bookmarked or open BCP, STD or FYI
  /// stands for its members' bodies (#656). As they are while there is no index.
  private func withMembers(of documents: Set<DocumentID>) -> Set<DocumentID> {
    index()?.withMembers(of: documents) ?? documents
  }

  /// Whether Available Offline lists `id` and its body is on the device: what a
  /// library row marks as offline (#769). Not while the body waits, downloads or
  /// failed, which only Available Offline's own rows say (#936). Both, because `kept`
  /// learns of an unmark only once the run it starts has read the disk, and the list
  /// at once. Only an RFC: the list holds the RFCs a series names, not the series.
  public func isAvailableOffline(_ id: DocumentID) -> Bool {
    isWantedOffline(id) && offlineKeeper.kept.contains(id)
  }

  /// Whether Available Offline lists `id`.
  private func isWantedOffline(_ id: DocumentID) -> Bool {
    id.series == .rfc && availableOfflineNumbers.contains(id.number)
  }

  /// Lists what is wanted offline, and brings the disk in line with it: what a
  /// change to the marks calls.
  public func wantedOfflineChanged() {
    availableOfflineNumbers = Set(wantedOffline.filter { $0.series == .rfc }.map(\.number))
    reconcileOffline()
  }

  /// What a change to the bookmarks calls: they are wanted offline when they are
  /// kept.
  public func bookmarksChanged() {
    if keepsBookmarksOffline { wantedOfflineChanged() }
  }

  /// Turns "Keep bookmarked documents offline" on or off. On, a bookmarked document's
  /// body is moved into the kept tier, or fetched there once the network allows a
  /// fetch nobody waits for; off, it goes back into the cache.
  public func setKeepsBookmarksOffline(_ isOn: Bool) {
    guard isOn != keepsBookmarksOffline else { return }
    storeKeepsBookmarksOffline(isOn)
    wantedOfflineChanged()
  }

  /// Records the setting, leaving reconciling to the caller.
  private func storeKeepsBookmarksOffline(_ isOn: Bool) {
    defaults.set(isOn, forKey: ReaderPreferences.keepBookmarksOfflineKey)
    keepsBookmarksOffline = isOn
  }

  /// Brings the disk in line with `wantedOffline`, after any reconciliation already
  /// running: what an index applied, a new network path and Low Power Mode call.
  /// Not before the index has loaded, since a fetch needs the formats it lists; nor
  /// before the marks have been read, nor the bookmarks when they are kept offline.
  /// Nor on a store that fell back to memory (#152), whose marks are not the ones
  /// saved: reconciling against them would move every kept body into the cache.
  /// Nor before the network path is known, which decides whether the fetches it
  /// owes start now: every one of them is a mark nobody on this device is waiting
  /// for, since a tapped one is fetched at once.
  /// - Parameter forgettingFailures: on a new path, where what failed may succeed.
  public func reconcileOffline(forgettingFailures: Bool = false) {
    guard index() != nil, userData.knowsWantedOffline(keepsBookmarks: keepsBookmarksOffline),
      !isStoredInMemory, let policy = networkDecision(.syncedMark)
    else { return }
    offlineKeeper.reconcile(
      wanted: wantedOffline, policy: policy, forgettingFailures: forgettingFailures)
  }

  /// Fetches a document marked Keep Offline on whatever path the device has, from
  /// its row's Download Now or Retry. The keeper logs a failure, and its row says it.
  public func downloadNow(_ id: DocumentID) {
    Task(name: "Download now") { try? await offlineKeeper.fetchNow(id) }
  }

  /// Marks `id` Keep Offline, or removes its mark, as the Info pane's toggle does
  /// (#358). Marking moves a copy already read, or downloads one now, on any
  /// network, since somebody is waiting for it, and throws when that fails: the mark
  /// stays, and its row in Available Offline offers Retry until the device moves to
  /// another network, when the keeper tries again by itself. Unmarking moves the
  /// body back into the reading cache rather than deleting it, and leaves a download
  /// running for it. A mark that could not be saved is logged, as a bookmark's is
  /// (#125), and leaves the toggle as it was.
  public func setKeptOffline(_ id: DocumentID, _ isKept: Bool) async throws {
    guard mark(id, keptOffline: isKept), isKept else { return }
    try await offlineKeeper.fetchNow(id)
  }

  /// `setKeptOffline` from a list's context menu or a script, which have nowhere to
  /// show a failed download either. The mark is saved before this returns, so a
  /// script that reads it back reads what it set, and only the download goes on
  /// after.
  public func setKeptOfflineInBackground(_ id: DocumentID, _ isKept: Bool) {
    guard mark(id, keptOffline: isKept), isKept else { return }
    // The keeper logs a failed download itself.
    Task(name: "Keep offline") { try? await offlineKeeper.fetchNow(id) }
  }

  /// Saves the mark, whose save reads the marks again before this returns (the
  /// mirror's `ModelContext.didSave`, posted synchronously on the main actor). Answers
  /// whether it was saved.
  private func mark(_ id: DocumentID, keptOffline isKept: Bool) -> Bool {
    do {
      try userData.setMarked(id, isKept)
    } catch {
      repositoryLog.error(
        "\(id.displayName, privacy: .public): marking Keep Offline failed: \(String(describing: error), privacy: .public)"
      )
      return false
    }
    return true
  }

  /// Keeps nothing offline any more: removes every mark, on every device, since marks
  /// are synced, and turns off keeping this device's bookmarks. The bodies go back
  /// into the reading cache, as an unmarked one does, where eviction or Clear Cache
  /// removes them. A removal that could not be saved is logged and changes nothing
  /// (`UserDataMirror.removeAllOfflineMarks(first:)`).
  public func removeAllOffline() {
    let keptBookmarks = keepsBookmarksOffline
    do {
      // One reconciliation for both, without the bookmarks: the marks' report runs it.
      try userData.removeAllOfflineMarks(first: { storeKeepsBookmarksOffline(false) })
    } catch {
      // Nothing was reconciled, so restoring the setting is all there is to undo.
      storeKeepsBookmarksOffline(keptBookmarks)
      repositoryLog.error(
        "removing every Keep Offline mark failed: \(String(describing: error), privacy: .public)")
    }
  }

  // MARK: - Reading paths (#189)

  public enum ReadingPathResult {
    case path(ReadingPath)
    /// There is no `indexes` pack, bundled or installed, which the sheet says rather
    /// than computing a partial path from the documents in the cache.
    case noIndex
    /// The pack is there and did not read: logged, and said in a sentence.
    case failed
  }

  /// Looks for the citation index again: at launch, and after a pack is installed.
  public func refreshCitationIndex() async {
    let hasIndex = await store.citationIndexURL() != nil
    guard hasIndex != hasCitationIndex else { return }
    hasCitationIndex = hasIndex
  }

  /// The reading path from `root`, `depth` citations deep, read from the `indexes`
  /// pack `DocumentStore.citationIndexURL()` chooses, off the main actor.
  public func readingPath(from root: DocumentID, depth: Int) async -> ReadingPathResult {
    guard let url = await store.citationIndexURL() else { return .noIndex }
    do {
      return .path(try await CitationIndex.readingPath(from: root, depth: depth, in: url))
    } catch {
      repositoryLog.error(
        "reading the citation index failed: \(String(describing: error), privacy: .public)")
      return .failed
    }
  }
}
