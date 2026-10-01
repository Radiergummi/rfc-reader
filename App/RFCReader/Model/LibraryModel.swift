import Foundation
import Observation
import RFCKit
import RFCReaderKit
import SwiftData
import os

nonisolated private let libraryLog = Logger(
  subsystem: Bundle.main.bundleIdentifier ?? "me.mazetti.rfc-reader", category: "library")

#if os(macOS)
  import AppKit
#else
  import UIKit
#endif

#if os(macOS)
  /// What the library asks of the window layer, which on macOS is the app's own:
  /// `AppDelegate` makes every window, and answers these when it sets itself as
  /// `LibraryModel.windows`. The library says what it needs, and never reaches for
  /// the delegate itself.
  protocol WindowOpening: AnyObject {
    /// A window of its own, in front.
    func openWindow()
    /// A tab of the window the user is looking at.
    func openTab(inBackground: Bool)
    /// The window showing `scene`, made key and its tab selected.
    func bringForward(_ scene: NavigationModel)
    /// The tab the menu acts on, and the one `route(_:)` prefers: the front tab of
    /// the reader window made key last, which it stays while the app is in the
    /// background.
    var activeNavigation: NavigationModel? { get }
  }
#endif

/// The library, one per process: the index and its search, the lists drawn from
/// it, the document cache, and the registry of open tabs a link is routed through.
///
/// Navigation is each tab's own (`NavigationModel`), and what the reader shows is
/// each window's (`ReaderState`). The user's own data — bookmarks, reading
/// positions, collections — is SwiftData's; this holds the sets read from it that
/// every tab shows.
@Observable
final class LibraryModel {
  /// One instance per process so App Intents and URL handlers reach the same state.
  static let shared = LibraryModel()

  enum IndexState: Equatable {
    case idle
    case loading
    case ready(updatedAt: Date)
    case failed(String)

    var isReady: Bool {
      if case .ready = self { true } else { false }
    }
  }

  private(set) var index: RFCIndex?
  private(set) var indexState: IndexState = .idle
  private(set) var recent: [RecentRFC] = []

  /// `revisions.json`: adopted drafts that intend to obsolete or update an RFC. Nil
  /// until the cached copy or a fetch has arrived.
  private(set) var revisions: RFCRevisions?
  /// When this launch last fetched it; nil until it has.
  @ObservationIgnored private var revisionsFetchedAt: Date?
  @ObservationIgnored private var isRefreshingRevisions = false
  @ObservationIgnored private var activations: (any NSObjectProtocol)?

  /// Every bookmarked document, fetched again on every save of the store: one set
  /// for the toolbars and scripts alike, which ask about the document on screen, so
  /// BCP 14 is not answered for by RFC 14 (#152).
  private(set) var bookmarkedDocuments: Set<DocumentID> = []

  /// The bookmarked RFCs' numbers, for the lists, which list RFCs. Kept beside
  /// `bookmarkedDocuments` rather than derived from it: every list body reads it.
  private(set) var bookmarkedNumbers: Set<Int> = []

  /// The presentation the reader chose from a block's menu, per document, for the
  /// app's session. Here rather than in `DocumentSession`, which goes when the
  /// reader goes back. Not persisted.
  private(set) var chosenPresentations:
    [DocumentID: [PresentationKey: PresentationChoices.Presentation]] = [:]

  /// The reader's choices in `id`, over the preference for every document.
  func presentationChoices(for id: DocumentID, drawsDiagrams: Bool) -> PresentationChoices {
    PresentationChoices(drawsDiagrams: drawsDiagrams, chosen: chosenPresentations[id] ?? [:])
  }

  func choose(
    _ presentation: PresentationChoices.Presentation, for key: PresentationKey,
    in id: DocumentID
  ) {
    chosenPresentations[id, default: [:]][key] = presentation
  }

  /// Every collection and its members, fetched again on every save of the store and
  /// published only when it changed (#349). The sidebar, a collection's list, the
  /// Add to Collection menus, the Mac's menu bar and scripts all read it.
  private(set) var collections = CollectionSnapshot.empty
  @ObservationIgnored private var storeSaves: (any NSObjectProtocol)?

  /// Every RFC with a cached body: the Available Offline list. Kept here, and
  /// refreshed whenever the cache can have changed, so a tab can take it the moment
  /// it enters that filter rather than waiting on the store's actor.
  private(set) var downloadedNumbers: Set<Int> = []

  /// How many RFCs Recently Read lists, for the sidebar's count (#344): the length
  /// of `recentlyReadNumbers()`, kept current on every save rather than by a live
  /// query of every reading position in the view.
  private(set) var recentlyReadCount = 0

  private init() {
    refreshBookmarks()
    refreshCollections()
    refreshRecentlyReadCount()
    storeSaves = NotificationCenter.default.addObserver(
      forName: ModelContext.didSave, object: nil, queue: .main
    ) { [weak self] _ in
      MainActor.assumeIsolated {
        self?.refreshBookmarks()
        self?.refreshCollections()
        self?.refreshRecentlyReadCount()
      }
    }
    // On activation, not `scenePhase`: on macOS the reader's roots are hosted, outside
    // SwiftUI's scene environment.
    #if os(macOS)
      let didBecomeActive = NSApplication.didBecomeActiveNotification
    #else
      let didBecomeActive = UIApplication.didBecomeActiveNotification
    #endif
    activations = NotificationCenter.default.addObserver(
      forName: didBecomeActive, object: nil, queue: .main
    ) { [weak self] _ in
      MainActor.assumeIsolated {
        guard let self else { return }
        Task(name: "Refresh revisions") { await self.refreshRevisions() }
        self.recheckSpotlight()
      }
    }
  }

  private func refreshRecentlyReadCount() {
    let count: Int
    do {
      count = try ReadingPositionStore.recentlyReadRFCCount(in: AppData.container.mainContext)
    } catch {
      // The last count read stands until a fetch succeeds.
      libraryLog.error(
        "counting the recently read failed: \(String(describing: error), privacy: .public)")
      return
    }
    guard count != recentlyReadCount else { return }
    recentlyReadCount = count
  }

  private func refreshCollections() {
    let snapshot = CollectionSnapshot.fetch(in: AppData.container.mainContext)
    // Only a change is news: most saves record a reading position.
    guard snapshot != collections else { return }
    collections = snapshot
    // A collection deleted in another tab, or on another device, is not left on
    // screen with no name and nothing in it.
    for scene in scenes.compactMap(\.model) {
      scene.keepFilter(in: snapshot)
    }
  }

  /// What a filter is called, wherever it is shown, against the collections as they
  /// are now.
  func title(for filter: LibraryFilter) -> String {
    filter.title(in: collections)
  }

  /// How many of a collection's documents the index knows, for the sidebar. Nil
  /// until the index has loaded.
  func count(of entry: CollectionSnapshot.Entry) -> Int? {
    guard let index else { return nil }
    return entry.rfcNumbers.count(where: { index[$0] != nil })
  }

  /// Runs a change to collections on the app's context. A failure is logged rather
  /// than shown (#125): every change the interface offers is one the store accepts,
  /// and an empty name is refused before it gets here.
  func editCollections(_ change: (ModelContext) throws -> Void) {
    do {
      try change(AppData.container.mainContext)
    } catch {
      libraryLog.error(
        "changing a collection failed: \(String(describing: error), privacy: .public)")
    }
  }

  /// Adds the bookmark or removes it, on the app's context, titled from the index
  /// or else `documentTitle`, what an open reader has parsed. A failure is logged
  /// rather than shown, as a collection's is (#125). A failed lookup changes
  /// nothing; a failed save leaves the change pending in the context, saved with
  /// the next save that succeeds.
  func toggleBookmark(_ id: DocumentID, documentTitle: String? = nil) {
    let title = DocumentActions.bookmarkTitle(
      metadata: metadata(id), documentTitle: documentTitle, id: id)
    do {
      try BookmarkStore.toggle(id, title: title, in: AppData.container.mainContext)
    } catch {
      libraryLog.error(
        "toggling a bookmark failed: \(String(describing: error), privacy: .public)")
    }
  }

  private func refreshBookmarks() {
    let documents: Set<DocumentID>
    do {
      documents = try BookmarkStore.bookmarkedDocuments(in: AppData.container.mainContext)
    } catch {
      // The last set read stands until a fetch succeeds.
      libraryLog.error("reading bookmarks failed: \(String(describing: error), privacy: .public)")
      return
    }
    // Only a change is news: most saves record a reading position, not a bookmark.
    guard documents != bookmarkedDocuments else { return }
    bookmarkedDocuments = documents
    bookmarkedNumbers = Set(documents.filter { $0.series == .rfc }.map(\.number))
  }

  private func refreshDownloadedNumbers() async {
    let numbers = await store.cachedNumbers()
    guard numbers != downloadedNumbers else { return }
    downloadedNumbers = numbers
  }

  private let client = RFCEditorClient()
  /// For the automatic daily check, which waits for a network that is neither
  /// metered nor in Low Data Mode instead of failing (#314).
  private let clientOnCheapNetworks = RFCEditorClient(
    transport: URLSessionTransport(session: .rfcEditorOnCheapNetworks))
  private let store = DocumentStore()
  private var search: IndexSearch?

  // MARK: - Bootstrap

  func bootstrap() async {
    guard indexState == .idle else { return }
    indexState = .loading
    // Before anything is awaited, so that the parse is already running when this
    // first suspends. On macOS, `AppDelegate` starts this with `Task.immediate` and
    // makes the first window at that suspension: the window is about 255 ms of the
    // main thread, and the parse, which needs nothing from it, runs beside it rather
    // than after it (#367). Every `await` stays below this line.
    async let cached = Self.loadCachedIndex(from: store)
    #if DEBUG
      installPackFromLaunchArgument()
    #endif
    // Just Published needs neither the index nor the downloads, so it starts beside
    // them rather than after the index is applied. It is decoration: a failure leaves
    // it empty, and is logged rather than shown (#125).
    Task(name: "Fetch recent RFCs") {
      do {
        recent = try await client.fetchRecent()
      } catch {
        libraryLog.error(
          "fetching recent RFCs failed: \(String(describing: error), privacy: .public)")
      }
    }
    await refreshDownloadedNumbers()
    do {
      if let (prepared, updatedAt) = try await cached {
        apply(prepared, updatedAt: updatedAt)
        // Check in the background if the index was last checked over a day ago:
        // only on a cheap network, since nobody is waiting for it (#314).
        if IndexCheck.isDue(checkedAt: updatedAt, now: .now) {
          Task(name: "Refresh index") { await refreshIndex(onExpensiveNetworks: false) }
        }
      } else {
        await refreshIndex()
      }
    } catch {
      indexState = .failed(error.localizedDescription)
    }
    Task(name: "Refresh revisions") { await refreshRevisions() }
    // Only the Mac's Go to RFC palette looks values up (#175); an iPhone would
    // fetch them for nothing.
    #if os(macOS)
      Task(name: "Load registries") { await refreshRegistries() }
    #endif
  }

  // MARK: - Registries

  /// The IANA registry values the Go to RFC palette looks up (#175). Not observed:
  /// the palette asks on each keystroke, and nothing on screen lists them.
  @ObservationIgnored private var registryEntries: [RegistryEntry] = []

  /// Registries change more often than RFCs, but not by the day.
  private static let registryMaximumAge: TimeInterval = 7 * 86_400

  /// When the registries were last checked, nil until launch first checks them.
  @ObservationIgnored private var registriesCheckedAt: Date?

  /// Checks the registries again if the last check is older than
  /// `registryMaximumAge`: the palette asks as it opens, since the app may stay open
  /// for weeks after the check at launch.
  func refreshRegistriesIfDue() {
    guard let checked = registriesCheckedAt,
      checked.timeIntervalSinceNow < -Self.registryMaximumAge
    else { return }
    Task(name: "Refresh registries") { await refreshRegistries() }
  }

  /// Reads the cached registries, then fetches those that are due: a first fetch on
  /// any network, a refresh only on a cheap one (`RegistryRefresh`). A registry that
  /// cannot be fetched keeps its cached entries, and is logged rather than shown
  /// (#125): the palette still finds RFCs without it.
  private func refreshRegistries() async {
    // Set before the first suspension, so a palette opened meanwhile does not start
    // a second check.
    registriesCheckedAt = .now
    var cached = await store.cachedRegistries(maximumAge: Self.registryMaximumAge)
    registryEntries = IANARegistry.allCases.flatMap { cached.entries[$0] ?? [] }
    let fetches = RegistryRefresh.fetches(stale: cached.stale, cached: Set(cached.entries.keys))
    for fetch in fetches {
      let registry = fetch.registry
      let fetched: (entries: [RegistryEntry], data: Data)
      do {
        fetched = try await (fetch.onExpensiveNetworks ? client : clientOnCheapNetworks)
          .fetchRegistry(registry, onExpensiveNetworks: fetch.onExpensiveNetworks)
      } catch {
        libraryLog.error(
          "fetching the \(registry.file, privacy: .public) registry failed: \(String(describing: error), privacy: .public)"
        )
        continue
      }
      // Listed as soon as it is read, not after the slowest of the others, and
      // whether or not it can be kept for the next launch.
      cached.entries[registry] = fetched.entries
      registryEntries = IANARegistry.allCases.flatMap { cached.entries[$0] ?? [] }
      do {
        try await store.storeRegistry(fetched.data, for: registry)
      } catch {
        libraryLog.error(
          "caching the \(registry.file, privacy: .public) registry failed: \(String(describing: error), privacy: .public)"
        )
      }
    }
  }

  /// The registry values `query` names exactly: `425`, `tls alert 70`,
  /// `application/dns-message`.
  func registryMatches(for query: String) -> [RegistryEntry] {
    RegistryLookup.matches(query, in: registryEntries)
  }

  #if DEBUG
    /// `-installPack <url>`, a developer's way to install a pack from a URL or a
    /// path (#36). Logged, not shown: nothing on screen asked for it.
    private func installPackFromLaunchArgument() {
      guard let argument = UserDefaults.standard.string(forKey: "installPack") else { return }
      // Installed on every launch the argument is set for, which is what a
      // developer setting it in a scheme wants while iterating on a pack.
      let source = PackInstaller.source(fromArgument: argument)
      Task(name: "Install data pack") {
        do {
          let pack = try await installLegacyPack(from: source)
          libraryLog.info(
            "installed data pack \(pack.manifest.version, privacy: .public): \(pack.manifest.files.count) documents"
          )
        } catch {
          libraryLog.error(
            "installing a data pack failed: \(String(describing: error), privacy: .public)")
        }
      }
    }
  #endif

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
        libraryLog.error(
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

  /// Asks the RFC Editor for the index, sending what identifies the one kept so an
  /// unchanged index is a `304` rather than 14 MB (#314). `onExpensiveNetworks`
  /// false is the automatic daily check, which waits for a network that is neither
  /// metered nor in Low Data Mode; a person's Retry or pull to refresh takes any,
  /// and fails at once when there is none.
  func refreshIndex(onExpensiveNetworks: Bool = true) async {
    do {
      // Only with an index in memory: without one, a `304` would leave nothing to
      // show, so the whole index is asked for.
      let kept = index == nil ? nil : store.indexCheck()
      let validators = kept?.validators(at: .now)
      let interval = signposter.beginInterval("Fetch index")
      let fetched: IndexFetch
      do {
        // Ended on a throw too, so an offline refresh does not leave it open.
        defer { signposter.endInterval("Fetch index", interval) }
        fetched = try await (onExpensiveNetworks ? client : clientOnCheapNetworks)
          .fetchIndexData(unlessMatching: validators, onExpensiveNetworks: onExpensiveNetworks)
      }
      switch fetched {
      case .unchanged:
        // A `304` answers only a request that sent validators, which came from `kept`.
        guard let kept else { break }
        indexState = .ready(updatedAt: try await store.recordUnchangedIndex(kept))
      case .changed(let data, let validators):
        // Off the main actor: the parse alone is about a second (#124).
        let prepared = try await Self.parse(data)
        try await store.storeIndex(data, parsed: prepared.index, validators: validators)
        apply(prepared, updatedAt: .now)
      }
    } catch {
      // With an index already showing, the failure is not shown, but it is not
      // discarded either.
      libraryLog.error(
        "refreshing the index failed: \(String(describing: error), privacy: .public)")
      if index == nil { indexState = .failed(error.localizedDescription) }
    }
  }

  /// Only assigns: everything in `prepared` was built off the main actor.
  private func apply(_ prepared: PreparedIndex, updatedAt: Date) {
    self.index = prepared.index
    self.search = prepared.search
    self.topWorkingGroups = prepared.topWorkingGroups
    self.knownWorkingGroups = prepared.knownWorkingGroups
    self.indexCounts = prepared.counts
    listCache = RecentValues(capacity: Self.listCacheCapacity)
    hitCache = RecentValues(capacity: Self.listCacheCapacity)
    indexGeneration += 1
    indexState = .ready(updatedAt: updatedAt)
    signposter.emitEvent("Index ready")
    indexForSpotlight(prepared.index.rfcs)
  }

  // MARK: - Spotlight

  /// The Spotlight indexing under way (#178), canceled when a newer one starts.
  @ObservationIgnored private var spotlightIndexing: Task<Void, Never>?
  /// When the last one started, so an activation knows whether the week has turned.
  @ObservationIgnored private var spotlightCheckedAt: Date?

  private func indexForSpotlight(_ rfcs: [RFCMetadata]) {
    // A launch with a day-old cache applies it, then the refreshed index: the first
    // indexing gives way, so the older index cannot finish last and win.
    spotlightIndexing?.cancel()
    spotlightCheckedAt = .now
    spotlightIndexing = Task(name: "Index for Spotlight") {
      await SpotlightIndexer.update(rfcs)
    }
  }

  /// On activation: an app left running past its items' `lifetime` would otherwise
  /// lose every RFC from Spotlight, since only a newer index checks. Once a week at
  /// most, and the indexer skips an unchanged state.
  private func recheckSpotlight() {
    guard let index, let spotlightCheckedAt,
      SpotlightEntry.isRecheckDue(lastCheckedAt: spotlightCheckedAt, now: .now)
    else { return }
    indexForSpotlight(index.rfcs)
  }

  // MARK: - Revisions

  /// Loads the cached file first, so the banner is right offline. Then fetches, once a
  /// launch and again when the last fetch is a day old: launch and every activation
  /// call this, and the first to get here does the fetch. A failure keeps the cached
  /// copy, leaves the next call to try again, and is logged, not shown (#125).
  func refreshRevisions() async {
    guard !isRefreshingRevisions else { return }
    isRefreshingRevisions = true
    defer { isRefreshingRevisions = false }
    if revisions == nil, let cached = await store.cachedRevisions() {
      revisions = cached
    }
    if let fetchedAt = revisionsFetchedAt, Date.now.timeIntervalSince(fetchedAt) < 86_400 {
      return
    }
    do {
      let fetched = try await client.fetchRevisions()
      try await store.storeRevisions(fetched.data)
      revisionsFetchedAt = .now
      if fetched.revisions != revisions { revisions = fetched.revisions }
    } catch {
      libraryLog.error(
        "fetching revisions failed: \(String(describing: error), privacy: .public)")
    }
  }

  /// The drafts revising `id`.
  func revisionsSummary(for id: DocumentID) -> RevisionsSummary {
    RevisionsSummary(revisions, for: id, now: .now)
  }

  // MARK: - Lists

  func metadata(_ id: DocumentID) -> RFCMetadata? {
    index?[id]
  }

  /// Working groups with the most RFCs, for the sidebar.
  ///
  /// Derived once per index rather than per read: `SidebarView.body` reads this, so
  /// as a computed property it counted all 9,842 RFCs and sorted them again on every
  /// body pass -- measured at 1.8 ms release, 6 ms debug, dozens of times a session.
  /// `PreparedIndex` counts them.
  private(set) var topWorkingGroups: [String] = []

  /// Every working group the index names, lowercased, derived with the index for the
  /// same reason `topWorkingGroups` is: the iOS search field tokenizes its text with
  /// them on every body pass (#21).
  private(set) var knownWorkingGroups: Set<String> = []

  /// How many RFCs each filter the index decides lists, derived with the index for
  /// the same reason `topWorkingGroups` is (#344).
  private(set) var indexCounts: [LibraryFilter: Int] = [:]

  /// Answers remembered against their inputs.
  ///
  /// `list` is read from `RFCListView.body` — and by the toolbar's count and by
  /// scripts — and SwiftUI evaluates that body far more often than any of these
  /// inputs change -- twice per pass, several passes per click.
  /// Uncached, one filter change ran the full-text scan a dozen times over, and that
  /// scan measures 107 ms against the real index.
  ///
  /// A dictionary rather than a single slot because tabs have their own filters now:
  /// with one slot, two tabs listing different things evict each other on every pass
  /// and the hit rate collapses to zero. Bounded, forgetting the list used longest
  /// ago -- this is a cache, so losing an entry costs time, never correctness.
  ///
  /// Not observed: `list` writes it from a view's body on a miss, and a write to
  /// a property the running body read invalidated that body, so every miss rendered
  /// the list twice (#126). It is a memo of state that is observed, not state itself.
  /// That makes a hit read nothing observable, though, so `list` reads `index`
  /// before looking here: the key carries every other input, and those the caller
  /// reads for itself.
  @ObservationIgnored private var listCache = RecentValues<LibraryList, [RFCMetadata]>(
    capacity: listCacheCapacity)
  private static let listCacheCapacity = 8

  /// What force-click previews showed, kept for the next preview of the same
  /// document in the same style (#374), which then shows its text at once rather
  /// than a spinner. Four, at 4.5 to 8 MB a build.
  ///
  /// The whole preview rather than the build alone, so a build is never paired with
  /// another parse of its document. A document's previews go when it is removed or
  /// evicted (`forgetPreviews`), as the store's parse of it does, so what is gone
  /// from the disk is gone from memory too. Empty on iOS, which has no such preview.
  ///
  /// Not observed, for the reason `listCache` is not: it is a memo, and nothing is
  /// drawn from it.
  @ObservationIgnored private var previews = RecentValues<BuildKey, DocumentPreview.Loaded>(
    capacity: 4)

  /// What the last preview of `key` showed, if it is still kept.
  func keptPreview(for key: BuildKey) -> DocumentPreview.Loaded? {
    previews.value(for: key)
  }

  /// Keeps `preview` for the next preview of `key`, unless its document was removed
  /// or evicted while it was being fetched and built: its previews were forgotten
  /// then, and this one would come back after them.
  func keep(_ preview: DocumentPreview.Loaded, for key: BuildKey) async {
    guard await store.isCached(key.document) else { return }
    previews.store(preview, for: key)
  }

  private func forgetPreviews(of documents: some Sequence<DocumentID>) {
    let documents = Set(documents)
    previews.removeAll { documents.contains($0.document) }
  }

  /// What `scene`'s list shows: its filter and search, over the inputs it took on
  /// entering the filter and the bookmarks as they stand.
  func list(for scene: NavigationModel) -> [RFCMetadata] {
    // Observed on every call, hit or miss: this is what re-renders the list when
    // `refreshIndex` lands a new index, since a hit reads nothing else of ours.
    guard let index else { return [] }
    // Only the inputs this filter reads: in the key, the rest would make a list
    // that cannot have changed miss the cache — every tab's search re-run for a
    // bookmark toggled, and an order hashed on every lookup for a filter that
    // ignores it.
    let filter = scene.filter
    let key = LibraryList(
      filter: filter,
      query: scene.appliedQuery,
      bookmarked: filter == .bookmarks ? bookmarkedNumbers : [],
      recentlyRead: filter == .recent ? scene.recentOrder : [],
      downloaded: filter == .downloaded ? scene.downloaded : [],
      options: scene.listOptions,
      members: members(of: filter)
    )
    return list(key, in: index)
  }

  /// The whole library searched for `query`, whatever filter a scene is on: what the
  /// sidebar lists while it is searched on an iPhone, where the list is not on
  /// screen beside it (#345).
  func librarySearch(_ query: String) -> [RFCMetadata] {
    // Observed on every call, for the reason `list(for:)` gives.
    guard let index else { return [] }
    let key = LibraryList(filter: .all, query: query)
    return list(key, in: index)
  }

  /// A collection's members, read here — an observed read — so a change to them
  /// re-renders the list showing it.
  private func members(of filter: LibraryFilter) -> [Int] {
    guard case .collection(let identifier) = filter else { return [] }
    return collections[identifier]?.rfcNumbers ?? []
  }

  /// Every input is read off the key, so the cache cannot go stale against something
  /// the list consults but the key does not carry. The one input not in the key is
  /// `index` (and `search`, which `apply` replaces with it), which is why `apply`
  /// empties the cache: that keeps the cache correct, and the read of `index` at the
  /// top of `list` is what gets the view to ask again. The index is handed in from
  /// that read rather than read again here, so the observed read is the only one.
  private func list(_ key: LibraryList, in index: RFCIndex) -> [RFCMetadata] {
    if let hit = listCache.value(for: key) { return hit }
    let computed = signposter.withIntervalSignpost(
      "List", id: signposter.makeSignpostID(), "\(key.query, privacy: .public)"
    ) {
      key.rows(in: index, search: search, hits: hitCache.value(for: key.query))
    }
    listCache.store(computed, for: key)
    return computed
  }

  /// The subtitle under the list's title: how many documents it shows. Empty while
  /// the index loads — "0 Documents" would be a claim about the library, not about a
  /// list that has not arrived yet.
  func listSubtitle(for scene: NavigationModel) -> String {
    indexState.isReady ? DocumentCount.label(list(for: scene).count) : ""
  }

  /// Every hit for a query, best first, searched off the main actor by
  /// `prepareSearch(_:)` before a scene applies the query (#124), so a list
  /// computed for it only filters. The scan measures 7–11 ms in Release and up to
  /// 98 ms in Debug. A query that is not here, as after `apply` or for a script,
  /// is searched on the spot.
  ///
  /// Not observed, for the reason `listCache` gives; applying the query is what
  /// the list observes.
  @ObservationIgnored private var hitCache = RecentValues<String, [RFCMetadata]>(
    capacity: listCacheCapacity)
  /// Counts the indexes `apply` has installed, so a search that outlived its index
  /// is not kept.
  @ObservationIgnored private var indexGeneration = 0

  /// Searches for `query` off the main actor, so the list can apply it without
  /// scanning the index in a view update.
  func prepareSearch(_ query: String) async {
    guard !query.isEmpty, hitCache.value(for: query) == nil, let search else { return }
    let generation = indexGeneration
    let hits = await Self.hits(in: search, for: query)
    // A new index landed meanwhile, so these are hits in the old one; or typing
    // moved on, and a query nobody applies would push out one that is applied.
    guard indexGeneration == generation, !Task.isCancelled else { return }
    hitCache.store(hits, for: query)
  }

  @concurrent
  private static func hits(in search: IndexSearch, for query: String) async -> [RFCMetadata] {
    signposter.withIntervalSignpost(
      "Search", id: signposter.makeSignpostID(), "\(query, privacy: .public)"
    ) {
      search.search(query, limit: .max).map(\.rfc)
    }
  }

  /// The Go to RFC palette's candidates for what was typed, best first.
  ///
  /// Off the main actor: a short query like `http` scans every title and abstract,
  /// measured at 107 ms (#22), and this runs as the reader types.
  func suggestions(for query: String, limit: Int) async -> [DocumentID] {
    guard let search else { return [] }
    return await Self.suggestions(in: search, for: query, limit: limit)
  }

  /// What the Go to RFC palette and sheet list under what was typed, once the reader
  /// has paused: run per change of the query and canceled by the next, which is the
  /// debounce, so only a pause long enough to outlast the sleep reaches the search.
  ///
  /// - Returns: nil for nothing typed, or when the reader typed on first; no hits,
  ///   without searching, for a link, which names its document outright and which
  ///   no title or abstract contains, and while the index is still loading.
  func quickOpenHits(for query: String) async -> [DocumentID]? {
    guard !query.isEmpty else { return nil }
    if query.contains("://"), DocumentReference.link(from: query) != nil { return [] }
    guard index != nil else { return [] }
    do {
      try await Task.sleep(for: .milliseconds(120))
    } catch {
      return nil
    }
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

  // MARK: - Scene routing

  /// The open scenes, most recently used first.
  ///
  /// Weak, because a scene's lifetime is its window's and nothing here should keep a
  /// closed tab alive. This registry exists because `onOpenURL` is delivered to
  /// *every* open scene: without one place to decide, a deep link would open in all
  /// of them at once.
  private var scenes: [WeakScene] = []

  private struct WeakScene {
    weak let model: NavigationModel?
  }

  /// Waiting for the next scene to appear, because nothing can be handed to a tab
  /// as it is made — see `openInNewScene(_:inBackground:)` — or because a link was
  /// routed before any scene existed — see `route(_:)`. Taken in `register(_:)` and
  /// cleared there, so no later window picks up a stale one.
  private var pendingSceneLink: RFCLink?

  #if os(macOS)
    /// The window layer, set by `AppDelegate` at launch. Weak: the delegate owns the
    /// windows, and the library only asks it for them.
    @ObservationIgnored weak var windows: (any WindowOpening)?
  #endif

  /// Registers a new scene, and gives it the link it was opened for if it was
  /// opened for one. Nil for a window from the menu or at launch, which lands on
  /// the library as before.
  func register(_ scene: NavigationModel) {
    promote(scene)
    guard let link = pendingSceneLink else { return }
    pendingSceneLink = nil
    scene.open(link, in: index)
  }

  func unregister(_ scene: NavigationModel) {
    scenes.removeAll { $0.model == nil || $0.model === scene }
  }

  /// Makes a scene the most recently used, which is where an untargeted link lands
  /// when no tab is preferred over it -- on macOS `route(_:)` prefers the tab of the
  /// window that was key last.
  func activate(_ scene: NavigationModel) {
    guard scenes.first?.model !== scene else { return }
    promote(scene)
  }

  private func promote(_ scene: NavigationModel) {
    unregister(scene)
    scenes.insert(WeakScene(model: scene), at: 0)
  }

  /// Sends `link` to exactly one scene: the tab already showing that document if
  /// there is one, otherwise the tab the reader is in -- on macOS the one whose
  /// window was key last, which a tab opened in the background does not displace --
  /// and failing that the most recently used tab.
  ///
  /// A link can arrive before any scene has registered -- a URL or the Open RFC
  /// intent cold-launching the app on iOS -- and was dropped (#140). It waits in
  /// `pendingSceneLink` instead, for `register(_:)` to hand to the first scene. One
  /// slot, so of two links routed before then the later wins: the first scene can
  /// show one document, and the later link is the more recent ask. It cannot race
  /// `openInNewScene`, which is only ever reached from a scene that already exists.
  ///
  /// On macOS the app makes every window itself, so the tab that takes the link is
  /// also brought forward: `makeKeyAndOrderFront` selects a tab within its group.
  /// With every window closed there is no scene coming to take the link, so one is
  /// opened for it -- the way `openInNewScene` does -- rather than leaving it for
  /// whatever window the reader next opens, possibly minutes later. iOS brings up a
  /// scene of its own on launch, and that one registers.
  func route(_ link: RFCLink) {
    scenes.removeAll { $0.model == nil }
    let open = scenes.compactMap(\.model)
    #if os(macOS)
      let preferred = windows?.activeNavigation
    #else
      let preferred: NavigationModel? = nil
    #endif
    guard
      let target = LinkRouting.target(
        for: link.id, in: open, showing: \.selection, preferring: { $0 === preferred })
    else {
      openInNewWindow(link)
      return
    }
    deliver(link, to: target)
  }

  /// Opens `link` in `scene` and makes that the tab in use.
  private func deliver(_ link: RFCLink, to scene: NavigationModel) {
    scene.open(link, in: index)
    // The tab that took the link is the most recently used one now, and where the
    // next untargeted link belongs -- even when it already showed that document, so
    // its selection did not change and `activate` was not called for it.
    activate(scene)
    #if os(macOS)
      windows?.bringForward(scene)
    #endif
  }

  /// Opens a window for `link`, which it takes in `register(_:)`.
  private func openInNewWindow(_ link: RFCLink) {
    pendingSceneLink = link
    #if os(macOS)
      windows?.openWindow()
    #endif
  }

  /// Opens `link` the way the click asked for: in `scene`, or in a tab of its own.
  ///
  /// The single place an activation becomes an effect, so Command-click means the
  /// same thing on a cross reference in the prose, a reference in the inspector and
  /// a button in the status banner. Every gesture that owns its own click goes
  /// through here; the document list is the exception, and says why at its binding.
  func open(_ id: DocumentID, activation: LinkActivation, in scene: NavigationModel) {
    open(RFCLink(id: id), activation: activation, in: scene)
  }

  func open(_ link: RFCLink, activation: LinkActivation, in scene: NavigationModel) {
    switch activation {
    case .here:
      scene.open(link, in: index)
    case .newTab(let inBackground):
      openInNewScene(link, inBackground: inBackground)
    }
  }

  /// Opens `link` in a tab of its own, either behind the current one or in front.
  ///
  /// On macOS through AppKit, because the app makes its own windows: there is no
  /// `WindowGroup` to ask, and `newWindowForTab:` is answered by our own window
  /// controller rather than by SwiftUI. Nothing can be passed to a window as it is
  /// made, so the link waits in `pendingSceneLink` for the window that appears to
  /// take it in `register(_:)`.
  ///
  /// On iPad a window of its own, asked of UIKit with a user activity carrying the
  /// link, which the new scene reads (`SceneRequest`, #158). Not `openWindow`: the
  /// app's `WindowGroup` is a plain one, which cannot take a value. A new window
  /// always comes to the front there, so `inBackground` does not apply.
  private func openInNewScene(_ link: RFCLink, inBackground: Bool) {
    #if os(macOS)
      pendingSceneLink = link
      windows?.openTab(inBackground: inBackground)
    #else
      guard opensNewWindows else { return }
      let activity = NSUserActivity(activityType: SceneRequest.activityType)
      activity.userInfo = SceneRequest.userInfo(for: link)
      UIApplication.shared.activateSceneSession(
        for: UISceneSessionActivationRequest(role: .windowApplication, userActivity: activity)
      ) { @Sendable error in
        // Sendable: UIKit does not promise to call this on the main thread, and a
        // main-actor closure called off it traps.
        libraryLog.error(
          "opening a window failed: \(String(describing: error), privacy: .public)")
      }
    #endif
  }

  #if !os(macOS)
    /// Whether this device can show another window: an iPad, not an iPhone. Menus
    /// offer Open in New Window only where it is.
    var opensNewWindows: Bool { UIApplication.shared.supportsMultipleScenes }

    /// Opens `id` in a window of its own, from a menu that offers it.
    func openWindow(for id: DocumentID) {
      openInNewScene(RFCLink(id: id), inBackground: false)
    }
  #endif

  #if os(macOS)
    /// Where a document asked for by name opens.
    enum Placement {
      case frontTab
      case newTab
      case newWindow
    }

    /// Opens `link` where `placement` says.
    ///
    /// The front tab is the one the menu acts on (`WindowOpening.activeNavigation`),
    /// not whichever tab `route(_:)` would pick: a script that says "open this"
    /// means the window it is looking at. With no window open there is no front
    /// tab, and the link is routed the way one from outside is, which opens one.
    func open(_ link: RFCLink, placement: Placement) {
      switch placement {
      case .frontTab:
        if let scene = windows?.activeNavigation {
          deliver(link, to: scene)
        } else {
          route(link)
        }
      case .newTab:
        openInNewScene(link, inBackground: false)
      case .newWindow:
        openInNewWindow(link)
      }
    }
  #endif

  // MARK: - Documents

  /// Fetching a document caches it, so the offline set is refreshed after.
  func document(for id: DocumentID) async throws -> RFCDocument {
    let document = try await store.document(id, formats: index?[id]?.formats ?? [], client: client)
    await evictIfGrown()
    await refreshDownloadedNumbers()
    return document
  }

  /// Installs the legacy XML pack from an `.aar`, a folder or a URL; see
  /// `DocumentStore.installLegacyPack(from:)`. A developer's path for now (#36).
  func installLegacyPack(from source: URL) async throws -> InstalledPack {
    try await store.installLegacyPack(from: source)
  }

  func originalText(for id: DocumentID) async throws -> String {
    let text = try await store.originalText(id, client: client)
    await evictIfGrown()
    await refreshDownloadedNumbers()
    return text
  }

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
      libraryLog.error(
        "eviction skipped, reading what it keeps failed: \(String(describing: error), privacy: .public)"
      )
      return
    }
    let evicted = await store.evict(pinned: pinned, bound: CacheEviction.defaultBound)
    forgetPreviews(of: evicted)
  }

  /// What eviction never removes (#39): bookmarks, a bookmark being a promise to
  /// keep the document offline; what was read in the last month; and whatever a
  /// window has open, which includes the document just fetched.
  private func pinnedDocuments() throws -> Set<DocumentID> {
    let context = AppData.container.mainContext
    let monthAgo = Date.now.addingTimeInterval(-30 * 86_400)
    let read = try ReadingPositionStore.read(since: monthAgo, in: context)
    let bookmarked = try BookmarkStore.bookmarkedDocuments(in: context)
    let open = scenes.compactMap { $0.model?.selection }
    return bookmarked.union(read).union(open)
  }

  func isDownloaded(_ id: DocumentID) async -> Bool {
    await store.isCached(id)
  }

  func downloadedSize(_ id: DocumentID) async -> Int? {
    await store.downloadedSize(id)
  }

  /// The documents the reader has opened, most recent first.
  ///
  /// Fetched on demand rather than observed, and that is the point: the Recently
  /// read list is history as of the moment the filter is entered, and a live query
  /// re-sorted it under the click that was reading it. `NavigationModel` takes one
  /// of these when its filter changes, exactly as it takes `downloadedNumbers`.
  ///
  /// Empty when the fetch fails, which is logged: the list is only shown, and
  /// nothing is decided by its being empty.
  func recentlyReadNumbers() -> [Int] {
    let documents: [DocumentID]
    do {
      documents = try ReadingPositionStore.recentlyRead(in: AppData.container.mainContext)
    } catch {
      libraryLog.error(
        "reading the recently read list failed: \(String(describing: error), privacy: .public)")
      return []
    }
    return documents.filter { $0.series == .rfc }.map(\.number)
  }

  func download(_ id: DocumentID) async throws {
    _ = try await document(for: id)
  }

  #if os(macOS)
    /// A format of a document saved to Downloads, as Safari saves a file: under its
    /// own name, or numbered when that is taken, and the Dock's Downloads stack told,
    /// so it bounces. What Option-clicking a format in the Info pane does (#25).
    func saveToDownloads(_ id: DocumentID, format: FileFormat) async throws {
      let data = try await client.fetchDocumentData(id, format: format)
      let name = RFCEditorEndpoints.document(id, format: format).lastPathComponent
      let file = try await Self.writeToDownloads(data, named: name)
      DistributedNotificationCenter.default().post(
        name: Notification.Name("com.apple.DownloadFileFinished"), object: file.path)
    }

    /// Off the main actor: a PDF is a few megabytes to write.
    @concurrent
    private nonisolated static func writeToDownloads(_ data: Data, named name: String) async throws
      -> URL
    {
      let files = FileManager.default
      let downloads = try files.url(
        for: .downloadsDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
      let unique = DownloadName.unique(name) {
        files.fileExists(atPath: downloads.appending(path: $0).path)
      }
      let file = downloads.appending(path: unique)
      try data.write(to: file, options: .withoutOverwriting)
      return file
    }
  #endif

  func removeDownload(_ id: DocumentID) async {
    await store.remove(id)
    forgetPreviews(of: [id])
    await refreshDownloadedNumbers()
  }
}
