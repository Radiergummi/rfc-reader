import Foundation
import Observation
import RFCKit
import os

private let indexLog = Logger(
  subsystem: Bundle.main.bundleIdentifier ?? "me.mazetti.rfc-reader", category: "library")

/// The index and its search (#595): the index read from the copy kept at launch, or
/// fetched when there is none, checked once a day on a cheap network, and fetched
/// again on any network when a person asks; what is worked out from it once per
/// index; the full-text index (#37) and Index All RFCs; and Just Published (#421).
///
/// What the app does once the index has arrived or failed to, the links held for it,
/// comes through `onSettled`, and what it does once an index is in, Spotlight and the
/// bookmark comparison, through `onApplied`. A change to the full-text index is told
/// through `onTextIndexChanged`.
@MainActor @Observable
public final class IndexRepository {
  public private(set) var index: RFCIndex? {
    didSet {
      groupRFCs = [:]
      indexVersion += 1
      indexableRFCs = index.map { IndexAllRun.indexable($0.rfcs) } ?? []
    }
  }

  /// The RFCs Index All RFCs can index (`IndexAllRun.indexable`), worked out once per
  /// index: the footer and Settings count them as they draw.
  @ObservationIgnored public private(set) var indexableRFCs: [RFCMetadata] = []
  /// Which index is installed, counted: what a tab compares to tell whether the
  /// rows and hits it has were made over the index there is now (#597), where
  /// comparing two indexes would compare every entry.
  public private(set) var indexVersion = 0
  /// Each working group's RFCs, worked out once per index for its card (#363): the
  /// list's body asks on every pass, and each answer scans the whole index.
  @ObservationIgnored private var groupRFCs: [String: [RFCMetadata]] = [:]
  public private(set) var indexState: IndexState = .idle
  /// The bytes the index's download has received, while one is under way with no
  /// index to show (#770); nil otherwise.
  public private(set) var indexBytesReceived: Int64?
  /// Counts the index's downloads, so the bytes a download reports after it has ended
  /// are not taken for the next one's.
  @ObservationIgnored private var indexDownloads = 0
  /// What the list shows in place of its rows while there is no index (#770).
  public var indexPlaceholder: IndexPlaceholder? {
    IndexPlaceholder(
      state: indexState, hasIndex: index != nil, bytesReceived: indexBytesReceived)
  }
  /// Open once the index has arrived or failed to, opened by `settle()`: from then on
  /// an intent takes what there is rather than waiting in `settledSearch()`, and the
  /// bookmark refresh goes on (`settled()`). Not `indexState`, which a launch whose
  /// fetch answers nothing leaves loading (#758).
  @ObservationIgnored private let indexSettled = Latch()

  /// Just Published, as the feed kept and then the RFC Editor's newer one have it.
  public private(set) var recent: [RecentRFC] = []
  /// Just Published's refresh at launch (#421), held rather than left to run
  /// unowned.
  @ObservationIgnored private let recentRefresh = SharedRefresh(name: "Refresh recent RFCs")

  /// The RFCs the installed legacy pack lists as text that only points to its
  /// original (#316): the reader shows their original without a load, offline too.
  /// Kept here so the reader can ask while it lays out, not across the store's actor.
  public private(set) var pointersInPack: Set<DocumentID> = []

  private var search: IndexSearch?

  /// Working groups with the most RFCs, for the sidebar.
  ///
  /// Derived once per index rather than per read: `SidebarView.body` reads this, so
  /// as a computed property it counted every RFC and sorted them again on every
  /// body pass, dozens of times a session.
  /// `PreparedIndex` counts them.
  public private(set) var topWorkingGroups: [String] = []

  /// Every working group the index names, folded, derived with the index for the
  /// same reason `topWorkingGroups` is: the iOS search field tokenizes its text with
  /// them on every body pass (#21).
  public private(set) var knownWorkingGroups: Set<String> = []

  /// How many RFCs each filter the index decides lists, derived with the index for
  /// the same reason `topWorkingGroups` is (#344).
  public private(set) var indexCounts: [LibraryFilter: Int] = [:]

  /// The full-text index (#37), kept to the bodies `store` holds. Nil until bootstrap
  /// has opened it, off the main actor, and when it could not be opened, which leaves
  /// the search to the index's metadata.
  @ObservationIgnored public private(set) var textIndexer: TextIndexer?

  /// Counts the full-text index's changes, for a tab to search the text again once
  /// a document is added to it or removed.
  public private(set) var textIndexVersion = 0

  /// Index All RFCs (#37), which Settings and the search's footer start and stop.
  public let indexAllRun = IndexAllRun()

  /// Whether the full-text index has opened, for Index All RFCs to be offered.
  public private(set) var hasTextIndex = false

  /// Called with the index once it is in, from the copy kept or fetched, after the
  /// links held for it were delivered (`onSettled`).
  @ObservationIgnored public var onApplied: (RFCIndex) -> Void = { _ in }
  /// Called once the index has arrived or failed to.
  @ObservationIgnored public var onSettled: () -> Void = {}
  /// Called after each change to the full-text index, and once it has opened.
  @ObservationIgnored public var onTextIndexChanged: () -> Void = {}

  @ObservationIgnored private let store: DocumentStore
  @ObservationIgnored private let client: RFCEditorClient
  /// For the automatic daily check, which waits for a network that is neither
  /// metered nor in Low Data Mode instead of failing (#314).
  @ObservationIgnored private let clientOnCheapNetworks: RFCEditorClient
  /// Where the full-text index is kept, worked out as it opens; nil opens none.
  @ObservationIgnored private let textIndexLocation: (@Sendable () throws -> URL)?
  @ObservationIgnored private let now: () -> Date

  /// The refresh of the index under way, the automatic daily check's or a person's,
  /// which a second one joins, except that a person's replaces the automatic check
  /// (#983).
  @ObservationIgnored private let indexRefresh = SharedRefresh(name: "Refresh index")

  /// - Parameters:
  ///   - client: for a fetch somebody waits for: the first launch, Retry, pull to
  ///     refresh.
  ///   - clientOnCheapNetworks: for the daily check and Just Published.
  ///   - textIndexLocation: where the full-text index is kept, called off the main
  ///     actor as it opens, since it may make the folder; nil opens none.
  public init(
    store: DocumentStore, client: RFCEditorClient, clientOnCheapNetworks: RFCEditorClient,
    textIndexLocation: (@Sendable () throws -> URL)? = { try TextIndexer.defaultURL },
    now: @escaping () -> Date = { .now }
  ) {
    self.store = store
    self.client = client
    self.clientOnCheapNetworks = clientOnCheapNetworks
    self.textIndexLocation = textIndexLocation
    self.now = now
  }

  // MARK: - Bootstrap

  /// Reads the index kept, or fetches it when there is none, and Just Published
  /// beside it; then opens the full-text index. Once per process: a second call
  /// returns at once.
  public func bootstrap() async {
    guard indexState == .idle else { return }
    indexState = .loading
    // Before anything is awaited, so that the parse is already running when this
    // first suspends. On macOS, `AppDelegate` starts this with `Task.immediate` and
    // makes the first window at that suspension: the window holds the main thread
    // until the "First window made" signpost, and the parse, which needs nothing from
    // it, runs beside it rather than after it (#367). Every `await` stays below this line.
    async let cached = Self.loadCachedIndex(from: store)
    // Just Published needs neither the index nor the downloads, so it starts beside
    // them rather than after the index is applied.
    recentRefresh.start { await self.refreshRecent() }
    await refreshPointersInPack()
    do {
      if let (prepared, updatedAt) = try await cached {
        apply(prepared, updatedAt: updatedAt)
        // Check in the background if the index was last checked over a day ago:
        // only on a cheap network, since nobody is waiting for it (#314).
        if IndexCheck.isDue(checkedAt: updatedAt, now: now()) {
          check()
        }
      } else {
        await refreshNow()
      }
    } catch {
      indexState = .failed(error)
      settle()
    }
    openTextIndex()
  }

  private func openTextIndex() {
    guard let textIndexLocation else { return }
    let changed: @Sendable () async -> Void = { [weak self] in await self?.textIndexChanged() }
    Task(name: "Index the text", priority: .utility) { [weak self, store] in
      let indexer: TextIndexer
      do {
        indexer = try await Self.openTextIndexer(at: textIndexLocation, store: store)
      } catch {
        indexLog.error(
          "the full-text index did not open: \(String(describing: error), privacy: .public)")
        return
      }
      self?.textIndexer = indexer
      self?.hasTextIndex = true
      // A list made before the index opened has no section hits, and an index that is
      // already up to date never reports a change: its tabs search the text now.
      self?.textIndexChanged()
      await indexer.run(changed: changed)
    }
  }

  /// Off the main actor: opening may make the folder and the tables.
  @concurrent
  private static func openTextIndexer(
    at location: @Sendable () throws -> URL, store: DocumentStore
  ) async throws -> TextIndexer {
    try TextIndexer(contentsOf: location(), store: store)
  }

  private func refreshPointersInPack() async {
    let pointers = await store.pointersInPack()
    guard pointers != pointersInPack else { return }
    pointersInPack = pointers
  }

  /// The cached index, parsed and prepared off the main actor and off the store's —
  /// the search and the working groups with it. Nil when there is none.
  @concurrent
  private static func loadCachedIndex(from store: DocumentStore) async throws
    -> (prepared: PreparedIndex, updatedAt: Date)?
  {
    guard let cached = store.cachedIndexLocation() else { return nil }
    let interval = signposter.beginInterval("Read cached index")
    defer { signposter.endInterval("Read cached index", interval) }
    if let snapshot = cached.snapshot {
      do {
        let index = try signposter.withIntervalSignpost("Decode index snapshot") {
          try IndexSnapshot.decode(Data(contentsOf: snapshot))
        }
        return (PreparedIndex(index: index), cached.updatedAt)
      } catch {
        indexLog.error(
          "decoding the index snapshot failed: \(String(describing: error), privacy: .public)")
      }
    }
    let prepared = try signposter.withIntervalSignpost("Parse index XML") {
      try PreparedIndex.parse(Data(contentsOf: cached.url))
    }
    // Parsed from the XML, so the next launch reads a snapshot of it instead.
    await store.writeSnapshot(of: prepared.index)
    return (prepared, cached.updatedAt)
  }

  @concurrent
  private static func parse(_ data: Data) async throws -> PreparedIndex {
    try signposter.withIntervalSignpost("Parse index") {
      try PreparedIndex.parse(data)
    }
  }

  // MARK: - Refreshing

  /// The automatic daily check of the index, only on a cheap network (#314): the one
  /// under way, or a new one.
  @discardableResult
  public func check() -> Task<Void, Never> {
    indexRefresh.start(replaceable: true) {
      await self.refresh(onExpensiveNetworks: false)
    }
  }

  /// Retry, after the index failed: on any network, as a person asked for it. It
  /// joins a person's refresh already under way rather than fetching the index beside
  /// it, and replaces the automatic check, which may wait for a cheap network for as
  /// long as there is none (#983).
  public func retry() {
    indexRefresh.start { await self.refresh(onExpensiveNetworks: true) }
  }

  /// The index fetched now, on any network, by the rule of `retry`, and waited
  /// for: pull to refresh and the first launch (#984).
  public func refreshNow() async {
    await indexRefresh.join { await self.refresh(onExpensiveNetworks: true) }
  }

  /// Until the index has arrived or failed to (`settle()`), for a background refresh
  /// that arrived while launch was still loading it (#191).
  public func settled() async {
    await indexSettled.wait()
  }

  /// Asks the RFC Editor for the index, sending what identifies the one kept so an
  /// unchanged index is a `304` rather than the whole index (#314). `onExpensiveNetworks`
  /// false is the automatic daily check, which waits for a network that is neither
  /// metered nor in Low Data Mode; a person's Retry or pull to refresh takes any,
  /// and fails at once when there is none.
  private func refresh(onExpensiveNetworks: Bool) async {
    do {
      // Only with an index in memory: without one, a `304` would leave nothing to
      // show, so the whole index is asked for.
      let kept = index == nil ? nil : store.indexCheck()
      let validators = kept?.validators(at: now())
      // With no index to show, the list shows the download instead (#770), until
      // the index downloaded has been applied or has failed. Not the automatic
      // check's, which may wait for a cheap network for as long as there is none:
      // it runs under the failure, and its Try Again, until it has the index.
      let isFirstDownload = index == nil && onExpensiveNetworks
      var onReceived: (@Sendable (Int64) -> Void)?
      if isFirstDownload {
        indexBytesReceived = 0
        indexDownloads += 1
        let download = indexDownloads
        // Off the main actor, every packet: only the steps the list shows go over
        // to it.
        let steps = OSAllocatedUnfairLock(initialState: IndexPlaceholder.ProgressSteps())
        onReceived = { [weak self] bytes in
          guard steps.withLock({ $0.isStep(bytes) }) else { return }
          Task { @MainActor in
            self?.indexReceived(bytes, in: download)
          }
        }
      }
      defer {
        if isFirstDownload {
          indexBytesReceived = nil
        }
      }
      let interval = signposter.beginInterval("Fetch index")
      let fetched: IndexFetch
      do {
        // Ended on a throw too, so an offline refresh does not leave it open.
        defer { signposter.endInterval("Fetch index", interval) }
        fetched = try await (onExpensiveNetworks ? client : clientOnCheapNetworks)
          .fetchIndexData(
            unlessMatching: validators, onExpensiveNetworks: onExpensiveNetworks,
            onReceived: onReceived)
      }
      switch IndexRefreshOutcome(fetched, kept: kept) {
      case .recordUnchanged(let kept):
        indexState = .ready(updatedAt: try await store.recordUnchangedIndex(kept))
      case .settle:
        settle()
      case .install(let data, let validators):
        // Off the main actor: the parse, with what is built from it, is the "Parse
        // index" signpost (#124).
        let prepared = try await Self.parse(data)
        try await store.storeIndex(data, parsed: prepared.index, validators: validators)
        apply(prepared, updatedAt: now())
      }
    } catch {
      // With an index already showing, the failure is not shown, but it is not
      // discarded either.
      indexLog.error(
        "refreshing the index failed: \(String(describing: error), privacy: .public)")
      // A refresh canceled, the automatic check that a person's replaced (#983) or
      // one iOS's background task ended, leaves the failure already shown as it was
      // rather than showing its cancellation.
      if index == nil, !(Task.isCancelled && indexState.isFailed) {
        indexState = .failed(error)
        settle()
      }
    }
  }

  /// Records the bytes `download` has received; ignored once it has ended.
  private func indexReceived(_ bytes: Int64, in download: Int) {
    guard download == indexDownloads, let shown = indexBytesReceived, bytes > shown else {
      return
    }
    indexBytesReceived = bytes
  }

  /// Only assigns: everything in `prepared` was built off the main actor.
  private func apply(_ prepared: PreparedIndex, updatedAt: Date) {
    self.index = prepared.index
    self.search = prepared.search
    self.topWorkingGroups = prepared.topWorkingGroups
    self.knownWorkingGroups = prepared.knownWorkingGroups
    self.indexCounts = prepared.counts
    indexState = .ready(updatedAt: updatedAt)
    signposter.emitEvent("Index ready")
    // The links held for the index first: a person is waiting for those (#241).
    settle()
    onApplied(prepared.index)
  }

  private func settle() {
    indexSettled.open()
    onSettled()
  }

  // MARK: - Settled

  /// Whether the index has loaded or failed to, for a caller that cannot wait for
  /// `settledSearch()`: a script's accessor (#762).
  public var hasSettled: Bool { indexSettled.isOpen }

  /// The index's search once the index has loaded, or nil if it could not: what an
  /// App Intent's queries run against (#192). Waits; the caller starts `bootstrap()`.
  public func settledSearch() async -> IndexSearch? {
    await indexSettled.wait()
    return search
  }

  // MARK: - Just Published

  /// The feed kept, then a newer one if the RFC Editor has it, asked for only on a
  /// cheap network (`RecentFeedRefresh`). It is decoration: a failure keeps what is
  /// shown, and is logged rather than shown (#125).
  private func refreshRecent() async {
    do {
      try await RecentFeedRefresh.run(store: store, client: clientOnCheapNetworks) { feed in
        if feed != recent { recent = feed }
      }
    } catch {
      indexLog.error(
        "refreshing recent RFCs failed: \(String(describing: error), privacy: .public)")
    }
  }

  // MARK: - Lookups

  public func metadata(_ id: DocumentID) -> RFCMetadata? {
    index?[id]
  }

  /// What a citation of `id` is made from (#712): its entry in the index, or a
  /// series' members'. Nil before the index names it.
  public func citedDocument(_ id: DocumentID) -> CitedDocument? {
    index.flatMap { CitedDocument(id, in: $0) }
  }

  /// "RFC 2119 and RFC 8174", the members of a series, for its reader's subtitle
  /// (#656); nil for an RFC, or before the index names them.
  public func seriesMembers(_ id: DocumentID) -> String? {
    index.flatMap { SeriesTitle.members(of: id, in: $0) }
  }

  /// The RFC whose text the reader shows for `id` (#656), a series' first member;
  /// see `RFCIndex.documentShown(for:)`. Nil for a series while the index loads,
  /// which names its members. A series the index doesn't list, or any once the index
  /// has failed, is shown from its own file, as before.
  public func documentShown(for id: DocumentID) -> DocumentID? {
    guard id.series != .rfc else { return id }
    if let index { return index.documentShown(for: id) ?? id }
    if case .failed = indexState { return id }
    return nil
  }

  /// Every RFC of the working group the index has, obsolete ones too, worked out once
  /// per index.
  public func rfcs(ofGroup acronym: String) -> [RFCMetadata] {
    if let cached = groupRFCs[acronym] { return cached }
    let filter = LibraryFilter.workingGroup(acronym)
    let rfcs = index?.rfcs.filter { filter.includes($0) == true } ?? []
    groupRFCs[acronym] = rfcs
    return rfcs
  }

  // MARK: - Lists and search

  /// `list` over the index as it stands, made off the main actor: what a tab stores
  /// and its list reads (#597). `hits` are the search's for `list.query` over this
  /// index, if a listing found them already. Nil while there is no index.
  public func listed(_ list: LibraryList, hits: [RFCMetadata]? = nil) async -> ListedRows? {
    guard let index else { return nil }
    return await Self.listed(
      list, in: index, indexVersion: indexVersion, search: search, hits: hits)
  }

  /// `listed(_:hits:)` on the main actor, for a script, which reads the list
  /// straight after changing what it lists.
  public func listedNow(_ list: LibraryList, hits: [RFCMetadata]? = nil) -> ListedRows? {
    guard let index else { return nil }
    return Self.signposted(list) {
      ListedRows(list, in: index, indexVersion: indexVersion, search: search, hits: hits)
    }
  }

  @concurrent
  private static func listed(
    _ list: LibraryList, in index: RFCIndex, indexVersion: Int, search: IndexSearch?,
    hits: [RFCMetadata]?
  ) async -> ListedRows {
    signposted(list) {
      ListedRows(list, in: index, indexVersion: indexVersion, search: search, hits: hits)
    }
  }

  private nonisolated static func signposted(
    _ list: LibraryList, _ make: () -> ListedRows
  ) -> ListedRows {
    signposter.withIntervalSignpost(
      "List", id: signposter.makeSignpostID(), "\(list.query, privacy: .public)", around: make)
  }

  /// What the full-text search finds for `list` (#37): its section hits, narrowed as
  /// its RFC rows are. Nil while there is no index, or when the list asks the text
  /// nothing (`LibraryList.textQuery`).
  public func textSearch(_ list: LibraryList) async -> TextIndexer.Found? {
    guard let index, let textIndexer,
      let query = await Self.textQuery(list, in: index, search: search)
    else { return nil }
    do {
      return try await textIndexer.search(
        query.words, section: query.section, in: query.documents)
    } catch {
      indexLog.error(
        "the full-text search failed: \(String(describing: error), privacy: .public)")
      return nil
    }
  }

  @concurrent
  private static func textQuery(
    _ list: LibraryList, in index: RFCIndex, search: IndexSearch?
  ) async -> LibraryList.TextQuery? {
    list.textQuery(in: index, search: search)
  }

  /// The Go to RFC palette's candidates for what was typed, best first.
  ///
  /// Off the main actor: a short query like `http` scans every title and abstract
  /// (the "Search: http" benchmark of `make benchmark`), and this runs as the reader
  /// types.
  public func suggestions(for query: String, limit: Int) async -> [DocumentID] {
    guard let search else { return [] }
    return await Self.suggestions(in: search, for: query, limit: limit)
  }

  /// What the Mac's Go to RFC palette lists under what was typed, once the reader
  /// has paused: run per change of the query and canceled by the next (`Debounce`).
  ///
  /// - Returns: nil for nothing typed, or when the reader typed on first; no hits,
  ///   without searching, for a link, which names its document outright and which
  ///   no title or abstract contains, and while the index is still loading.
  public func quickOpenHits(for query: String) async -> [DocumentID]? {
    guard !query.isEmpty else { return nil }
    if query.contains("://"), DocumentReference.link(from: query) != nil { return [] }
    // A draft is in no index (#728).
    if DocumentReference.draft(from: query) != nil { return [] }
    guard index != nil else { return [] }
    guard await Debounce.outlasted(.milliseconds(120)) else { return nil }
    let hits = await suggestions(for: query, limit: QuickOpenResults.limit)
    return Task.isCancelled ? nil : hits
  }

  @concurrent
  private static func suggestions(
    in search: IndexSearch, for query: String, limit: Int
  ) async -> [DocumentID] {
    signposter.withIntervalSignpost(
      "Suggest", id: signposter.makeSignpostID(), "\(query, privacy: .public)"
    ) {
      search.search(query, limit: limit).map(\.id)
    }
  }

  // MARK: - Full-text index

  private func textIndexChanged() {
    textIndexVersion += 1
    onTextIndexChanged()
  }

  /// Index All RFCs: downloads every one of `indexableRFCs` that is not indexed yet,
  /// on a network that is neither metered nor in Low Data Mode, and indexes it without
  /// keeping its body.
  public func indexAllRFCs() {
    guard let textIndexer else { return }
    let entries = Dictionary(
      indexableRFCs.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    let client = clientOnCheapNetworks
    let changed: @Sendable () async -> Void = { [weak self] in await self?.textIndexChanged() }
    indexAllRun.start(
      entries.keys.sorted(), indexer: textIndexer,
      fetch: { id in
        let entry = entries[id]
        return try await client.fetchPreferredDocument(
          id, availableFormats: entry?.formats, entry: entry
        ).document
      }, changed: changed)
  }

  /// How many of `indexableRFCs` Index All RFCs would download; nil while the
  /// full-text index has not opened.
  public func unindexedRFCCount() async -> Int? {
    await textIndexer?.unindexed(indexableRFCs.map(\.id))
  }

  /// What the full-text index holds, and how much of the disk it takes; nil while it
  /// has not opened.
  public func textIndexUsage() async -> TextIndexer.Usage? {
    await textIndexer?.usage()
  }

  /// Remove Full-Text Index: stops Index All RFCs, and keeps in the index only the
  /// RFCs whose bodies are stored.
  public func removeIndexOfAllRFCs() async {
    guard let textIndexer else { return }
    let changed: @Sendable () async -> Void = { [weak self] in await self?.textIndexChanged() }
    await indexAllRun.remove(from: textIndexer, changed: changed)
  }

  /// Installs the legacy XML pack from an `.aar`, a folder or a URL; see
  /// `DocumentStore.installLegacyPack(from:)`. A developer's path for now (#36). The
  /// RFCs read from the pack are indexed again with its anchors.
  public func installLegacyPack(from source: URL) async throws -> InstalledPack {
    let pack = try await store.installLegacyPack(from: source)
    await refreshPointersInPack()
    let changed: @Sendable () async -> Void = { [weak self] in await self?.textIndexChanged() }
    await textIndexer?.legacyPackInstalled(changed: changed)
    return pack
  }
}
