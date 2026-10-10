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
  ///
  /// Reached directly only where nothing can hand it over: the composition roots
  /// that make the app's state (`RFCReaderApp`, `AppDelegate`, iOS `ContentView`'s
  /// `@State`), and the entry points the system instantiates (`OpenRFCIntent`, the
  /// `Scripting` objects). Everything else is given it, and a hosted root is given it
  /// in a `ReaderEnvironment`.
  static let shared = LibraryModel(container: AppData.container)

  enum IndexState: Equatable {
    case idle
    case loading
    case ready(updatedAt: Date)
    /// What kind of failure, for the sentence the status line says, and the error's
    /// own description, which it shows second (#759).
    case failed(LoadFailure.Kind, message: String)

    var isReady: Bool {
      if case .ready = self { true } else { false }
    }

    static func failed(_ error: any Error) -> IndexState {
      .failed(LoadFailure(error: error).kind, message: error.localizedDescription)
    }
  }

  private(set) var index: RFCIndex? {
    didSet {
      groupRFCs = [:]
      indexVersion += 1
    }
  }
  /// Which index is installed, counted: what a tab compares to tell whether the
  /// rows and hits it has were made over the index there is now (#597), where
  /// comparing two indexes would compare 9,842 entries.
  private(set) var indexVersion = 0
  /// Each working group's RFCs, worked out once per index for its card (#363): the
  /// list's body asks on every pass, and the index is 9,842 RFCs to scan.
  @ObservationIgnored private var groupRFCs: [String: [RFCMetadata]] = [:]
  private(set) var indexState: IndexState = .idle {
    didSet {
      guard indexState != .loading, indexState != .idle else { return }
      let waiting = indexWaiters
      indexWaiters = []
      for waiter in waiting { waiter.resume() }
    }
  }
  /// What waits for the index to be ready or to have failed: a background refresh
  /// that arrived while launch was still loading it (#191).
  @ObservationIgnored private var indexWaiters: [CheckedContinuation<Void, Never>] = []
  private(set) var recent: [RecentRFC] = []

  /// `revisions.json`: adopted drafts that intend to obsolete or update an RFC. Nil
  /// until the cached copy or a fetch has arrived.
  private(set) var revisions: RFCRevisions?
  /// When this launch last fetched it; nil until it has.
  @ObservationIgnored private var revisionsFetchedAt: Date?
  /// The refresh under way, which a second call joins rather than repeats.
  @ObservationIgnored private var revisionsRefresh: Task<Void, Never>?
  /// `groups.json`: the groups the index names, for a working group's card (#363).
  /// Nil until the cached copy or a fetch has arrived.
  private(set) var workingGroups: WorkingGroups?
  /// Every RFC's errata (#387), from the RFC Editor's feed: the copy kept first, then
  /// a check once a day. Nil until either has been read.
  private(set) var errata: Errata?
  @ObservationIgnored private var isRefreshingErrata = false
  /// When this run last had an answer from the RFC Editor for the feed, whatever came
  /// of it: a feed that fails to decode or to be kept records no check, and would
  /// otherwise be downloaded again at every activation. A request that fails is asked
  /// again at the next activation, as the other refreshes are.
  @ObservationIgnored private var errataAskedAt: Date?
  @ObservationIgnored private var workingGroupsFetchedAt: Date?
  @ObservationIgnored private var isRefreshingWorkingGroups = false
  @ObservationIgnored private var activations: (any NSObjectProtocol)?

  /// Every bookmarked document, fetched again on every save of a bookmark: one set
  /// for the toolbars, scripts and lists alike, so BCP 14 is not answered for by
  /// RFC 14 (#152), and is listed as itself (#321).
  private(set) var bookmarkedDocuments: Set<DocumentID> = []

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

  /// Every collection and its members, fetched again on every save of a collection or
  /// an item (#603), and after a failed fetch on the next save of any kind
  /// (`failedMirrors`, #613), and published only when it changed (#349). The sidebar, a
  /// collection's list, the Add to Collection menus, the Mac's menu bar and scripts
  /// all read it.
  private(set) var collections = CollectionSnapshot.empty
  @ObservationIgnored private var storeSaves: (any NSObjectProtocol)?

  /// Every document marked Keep Offline, fetched again on every save of a mark
  /// (#358), and synced, so a mark made on another device arrives here too. With the
  /// bookmarks when `keepsBookmarksOffline` is on, what is wanted offline, and what
  /// Available Offline lists, whether or not a body has arrived yet.
  private(set) var offlineMarks: Set<DocumentID> = []

  /// "Keep bookmarked documents offline", from Settings' Storage tab (#358). Per
  /// device, as storage is, so a default rather than synced user data.
  private(set) var keepsBookmarksOffline =
    (UserDefaults.standard.object(forKey: ReaderPreferences.keepBookmarksOfflineKey) as? Bool)
    ?? ReaderPreferences.defaultKeepBookmarksOffline

  /// What is wanted offline: the marks, and the bookmarks when they are kept too.
  private var wantedOffline: Set<DocumentID> {
    OfflineReconciler.wanted(
      marks: offlineMarks, bookmarks: bookmarkedDocuments, keepsBookmarks: keepsBookmarksOffline)
  }

  /// Whether `offlineMarks` has been read from the store at least once. Until it
  /// has, its emptiness means nothing, and reconciling against it would move every
  /// kept body back into the cache.
  @ObservationIgnored private var hasReadOfflineMarks = false

  /// The RFCs wanted offline, which is what the library lists, kept beside the marks
  /// rather than worked out on every read: the sidebar counts it as it draws.
  private(set) var availableOfflineNumbers: Set<Int> = []

  /// Moves, releases and fetches bodies to match `wantedOffline`. Its fetches that
  /// nobody waits for take only a path that is neither metered nor in Low Data Mode,
  /// and fail rather than wait when the device moves to one.
  @ObservationIgnored private lazy var offlineKeeper = OfflineKeeper(
    store: store, client: client,
    clientFailingOnExpensiveNetworks: RFCEditorClient(
      transport: URLSessionTransport(session: .rfcEditorFailingOnExpensiveNetworks))
  ) { [weak self] id in
    self?.index?[id]?.formats ?? []
  }

  /// Where each document marked Keep Offline stands while its body is not on the
  /// device: waiting and why, downloading, or failed.
  var offlineStatus: OfflineStatus { offlineKeeper.status }

  /// The path and Low Power Mode, which decide whether the keeper fetches a mark
  /// that arrived from another device now or waits.
  @ObservationIgnored private let network = NetworkConditions()

  /// The RFCs the installed legacy pack lists as text that only points to its
  /// original (#316): the reader shows their original without a load, offline too.
  /// Kept here so the reader can ask while it lays out, not across the store's actor.
  private(set) var pointersInPack: Set<DocumentID> = []

  /// How many documents Recently Read lists, for the sidebar's count (#344): the
  /// length of `recentlyRead()`, kept current on every save of a reading position
  /// rather than by a live query of every reading position in the view.
  private(set) var recentlyReadCount = 0

  /// The mirrors whose last fetch failed. The next save reads them again, whatever
  /// it changed, so a failure is mended on the next save, as it was when every save
  /// read every mirror, rather than on the next save of the same entity (#603).
  @ObservationIgnored private var failedMirrors: UserDataMirrors = []

  /// The user's data: what the sets above are read from, and where a bookmark or a
  /// collection is changed.
  @ObservationIgnored let container: ModelContainer

  private init(container: ModelContainer) {
    self.container = container
    refresh(.all)
    storeSaves = NotificationCenter.default.addObserver(
      forName: ModelContext.didSave, object: nil, queue: .main
    ) { [weak self] notification in
      // Only the mirrors fed by what the save changed: most saves record a reading
      // position, and the collections are every row of two entities (#603). Read
      // before the hop, as the notification is not `Sendable` and the names are.
      let changed = UserDataMirrors.changedEntityNames(in: notification.userInfo)
      MainActor.assumeIsolated {
        self?.refresh(UserDataMirrors.changed(byEntities: changed))
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
        Task(name: "Refresh working groups") { await self.refreshWorkingGroups() }
        Task(name: "Refresh errata") { await self.refreshErrata() }
        self.recheckSpotlight()
      }
    }
    network.start(
      // A new path: what waited may go ahead, what runs may have to wait, and what
      // failed may succeed on it.
      pathChanged: { [weak self] in self?.reconcileOffline(forgettingFailures: true) },
      // Low Power Mode decides whether a fetch waits, not whether it fails.
      powerChanged: { [weak self] in self?.reconcileOffline() })
  }

  private func refresh(_ changed: UserDataMirrors) {
    let mirrors = changed.union(failedMirrors)
    failedMirrors = []
    if mirrors.contains(.bookmarks) { refreshBookmarks() }
    if mirrors.contains(.collections) { refreshCollections() }
    if mirrors.contains(.recentlyReadCount) { refreshRecentlyReadCount() }
    if mirrors.contains(.offlineMarks) { refreshOfflineMarks() }
  }

  private func refreshOfflineMarks() {
    let marks: Set<DocumentID>
    do {
      marks = try OfflineMarkStore.markedDocuments(in: container.mainContext)
    } catch {
      // The last set read stands until a fetch succeeds, which the next save tries.
      failedMirrors.insert(.offlineMarks)
      libraryLog.error(
        "reading Keep Offline marks failed: \(String(describing: error), privacy: .public)")
      return
    }
    // The first read reconciles even when it finds what a failed one left: no set.
    let isFirstRead = !hasReadOfflineMarks
    hasReadOfflineMarks = true
    guard isFirstRead || marks != offlineMarks else { return }
    offlineMarks = marks
    wantedOfflineChanged()
  }

  /// Lists what is wanted offline, and brings the disk in line with it.
  private func wantedOfflineChanged() {
    availableOfflineNumbers = Set(wantedOffline.filter { $0.series == .rfc }.map(\.number))
    reconcileOffline()
  }

  /// Turns "Keep bookmarked documents offline" on or off. On, a bookmarked document's
  /// body is moved into the kept tier, or fetched there once the network allows a
  /// fetch nobody waits for; off, it goes back into the cache.
  func setKeepsBookmarksOffline(_ isOn: Bool) {
    guard isOn != keepsBookmarksOffline else { return }
    storeKeepsBookmarksOffline(isOn)
    wantedOfflineChanged()
  }

  /// Records the setting, leaving reconciling to the caller.
  private func storeKeepsBookmarksOffline(_ isOn: Bool) {
    UserDefaults.standard.set(isOn, forKey: ReaderPreferences.keepBookmarksOfflineKey)
    keepsBookmarksOffline = isOn
  }

  /// Brings the disk in line with `wantedOffline`, after any reconciliation already
  /// running. Not before the index has loaded, since a fetch needs the formats it
  /// lists, and applying the index runs this; nor before the marks have been read.
  /// Nor on a store that fell back to memory (#152), whose marks are not the ones
  /// saved: reconciling against them would move every kept body into the cache.
  /// Nor before the network path is known, which decides whether the fetches it
  /// owes start now: every one of them is a mark nobody on this device is waiting
  /// for, since a tapped one is fetched at once.
  private func reconcileOffline(forgettingFailures: Bool = false) {
    guard index != nil, hasReadOfflineMarks, !AppData.isStoredInMemory,
      let policy = network.decision(for: .syncedMark)
    else { return }
    offlineKeeper.reconcile(
      wanted: wantedOffline, policy: policy, forgettingFailures: forgettingFailures)
  }

  /// Fetches a document marked Keep Offline on whatever path the device has, from
  /// its row's Download Now or Retry. The keeper logs a failure, and its row says it.
  func downloadNow(_ id: DocumentID) {
    Task(name: "Download now") { try? await offlineKeeper.fetchNow(id) }
  }

  private func refreshRecentlyReadCount() {
    let count: Int
    do {
      count = try ReadingPositionStore.recentlyReadCount(in: container.mainContext)
    } catch {
      // The last count read stands until a fetch succeeds, which the next save tries.
      failedMirrors.insert(.recentlyReadCount)
      libraryLog.error(
        "counting the recently read failed: \(String(describing: error), privacy: .public)")
      return
    }
    guard count != recentlyReadCount else { return }
    recentlyReadCount = count
    // A document read for the first time: what a phrase can name (#192).
    RFCReaderShortcuts.refreshParameters()
  }

  private func refreshCollections() {
    let snapshot: CollectionSnapshot
    do {
      snapshot = try CollectionSnapshot.fetch(in: container.mainContext)
    } catch {
      // The last snapshot stands until a fetch succeeds, which the next save tries:
      // an empty one would close every filter on a collection (#613).
      failedMirrors.insert(.collections)
      libraryLog.error(
        "reading collections failed: \(String(describing: error), privacy: .public)")
      return
    }
    // Only a change is news: an unknown save reads every mirror (`UserDataMirrors`).
    guard snapshot != collections else { return }
    collections = snapshot
    // A collection deleted in another tab, or on another device, is not left on
    // screen with no name and nothing in it.
    for scene in sceneRegistry.open {
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
  /// and an empty name is refused before it gets here. Answers whether it was made,
  /// for a view that says it was.
  @discardableResult
  func editCollections(_ change: (ModelContext) throws -> Void) -> Bool {
    do {
      try change(container.mainContext)
      return true
    } catch {
      libraryLog.error(
        "changing a collection failed: \(String(describing: error), privacy: .public)")
      return false
    }
  }

  /// What an undone or redone removal from a collection does with its failure:
  /// logged, as `editCollections` logs the change's own (#759).
  func collectionUndoFailed(_ error: any Error) {
    libraryLog.error(
      "undoing or redoing a removal from a collection failed: \(String(describing: error), privacy: .public)"
    )
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
      try BookmarkStore.toggle(id, title: title, in: container.mainContext)
    } catch {
      libraryLog.error(
        "toggling a bookmark failed: \(String(describing: error), privacy: .public)")
    }
  }

  private func refreshBookmarks() {
    let documents: Set<DocumentID>
    do {
      documents = try BookmarkStore.bookmarkedDocuments(in: container.mainContext)
    } catch {
      // The last set read stands until a fetch succeeds, which the next save tries.
      failedMirrors.insert(.bookmarks)
      libraryLog.error("reading bookmarks failed: \(String(describing: error), privacy: .public)")
      return
    }
    // Only a change is news: an unknown save reads every mirror (`UserDataMirrors`).
    guard documents != bookmarkedDocuments else { return }
    bookmarkedDocuments = documents
    if keepsBookmarksOffline { wantedOfflineChanged() }
    // So that the baseline holds a new bookmark from now on, and reports a change to
    // it from the next refresh rather than taking it for one from before (#191).
    compareBookmarks()
  }

  private func refreshPointersInPack() async {
    let pointers = await store.pointersInPack()
    guard pointers != pointersInPack else { return }
    pointersInPack = pointers
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
    await refreshPointersInPack()
    do {
      if let (prepared, updatedAt) = try await cached {
        apply(prepared, updatedAt: updatedAt)
        // Check in the background if the index was last checked over a day ago:
        // only on a cheap network, since nobody is waiting for it (#314).
        if IndexCheck.isDue(checkedAt: updatedAt, now: .now) {
          checkIndex()
        }
      } else {
        await refreshIndex()
      }
    } catch {
      indexState = .failed(error)
      settleIndex()
    }
    Task(name: "Refresh revisions") { await refreshRevisions() }
    Task(name: "Refresh working groups") { await refreshWorkingGroups() }
    Task(name: "Refresh errata") { await refreshErrata() }
    // Only the Mac's Go to RFC palette looks values up (#175); an iPhone would
    // fetch them for nothing.
    #if os(macOS)
      // Unless an intent has read them already (#192). Immediate, as the intent's is,
      // so the check is marked before either can look.
      if registriesCheckedAt == nil {
        Task.immediate(name: "Load registries") { await refreshRegistries() }
      }
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
      // The first fetches come first (`RegistryRefresh`): what is left are refreshes.
      if !fetch.onExpensiveNetworks { registriesBecameReadable() }
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
    registriesBecameReadable()
  }

  /// The registry values `query` names exactly: `425`, `tls alert 70`,
  /// `application/dns-message`.
  func registryMatches(for query: String) -> [RegistryEntry] {
    RegistryLookup.matches(query, in: registryEntries)
  }

  /// What waits in `loadedRegistryEntries()` for the registries to be readable.
  @ObservationIgnored private var registryWaiters: [CheckedContinuation<Void, Never>] = []
  /// Whether the registries are readable: the cached ones read, and the ones never
  /// fetched fetched, or failed to be. Not the refreshes after them, which may wait
  /// for a cheap network.
  @ObservationIgnored private var areRegistriesReadable = false

  private func registriesBecameReadable() {
    guard !areRegistriesReadable else { return }
    areRegistriesReadable = true
    let waiters = registryWaiters
    registryWaiters = []
    for waiter in waiters { waiter.resume() }
  }

  /// The registry entries an App Intent asks for (#192), once they are readable.
  /// Only the Mac reads them at launch, and an intent may be the first to ask on
  /// either platform, so this starts the read when nothing has, in a task of its own,
  /// as `settledSearch()` starts the index's.
  func loadedRegistryEntries() async -> [RegistryEntry] {
    // Immediate, so the check is marked before this suspends and a second query
    // asking meanwhile does not read them again.
    if registriesCheckedAt == nil {
      Task.immediate(name: "Load registries") { await refreshRegistries() }
    }
    if !areRegistriesReadable {
      await withCheckedContinuation { registryWaiters.append($0) }
    }
    return registryEntries
  }

  #if DEBUG
    /// `-installPack <url>`, a developer's way to install a pack from a URL or a
    /// path (#36), and `-installIndexesPack <url>` for the `indexes` pack (#189).
    /// Logged, not shown: nothing on screen asked for it.
    private func installPackFromLaunchArgument() {
      let legacy = UserDefaults.standard.string(forKey: "installPack")
      let indexes = UserDefaults.standard.string(forKey: "installIndexesPack")
      guard legacy != nil || indexes != nil else { return }
      // Installed on every launch the argument is set for, which is what a
      // developer setting it in a scheme wants while iterating on a pack. One after
      // the other, since the store installs one pack at a time, and each whether or
      // not the other failed.
      Task(name: "Install data pack") {
        if let legacy {
          do {
            let pack = try await installLegacyPack(from: PackInstaller.source(fromArgument: legacy))
            libraryLog.info(
              "installed data pack \(pack.manifest.version, privacy: .public): \(pack.manifest.files.count) documents"
            )
          } catch {
            libraryLog.error(
              "installing a data pack failed: \(String(describing: error), privacy: .public)")
          }
        }
        if let indexes {
          do {
            let pack = try await store.installIndexesPack(
              from: PackInstaller.source(fromArgument: indexes))
            libraryLog.info("installed indexes pack \(pack.manifest.version, privacy: .public)")
          } catch {
            libraryLog.error(
              "installing the indexes pack failed: \(String(describing: error), privacy: .public)")
          }
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
        // One that answers none leaves no index to wait for.
        guard let kept else {
          settleIndex()
          break
        }
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
      if index == nil {
        indexState = .failed(error)
        settleIndex()
      }
    }
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
    indexForSpotlight(prepared.index.rfcs)
    settleIndex()
    compareBookmarks()
    // What waited for the formats the index lists.
    reconcileOffline()
    // The RFCs a phrase can name are the ones read recently, which need the index.
    RFCReaderShortcuts.refreshParameters()
  }

  // MARK: - App Intents

  /// What waits in `settledSearch()` for the index to arrive or fail, resumed by
  /// `settleIndex()`.
  @ObservationIgnored private var settledIndexWaiters: [CheckedContinuation<Void, Never>] = []
  /// Whether the index has arrived or failed to, once: from then on an intent takes
  /// what there is rather than waiting. Not `indexState`, which a launch whose fetch
  /// answers nothing leaves loading.
  @ObservationIgnored private var isIndexSettled = false

  /// The index's search once the index has loaded, or nil if it could not: what an
  /// App Intent's queries run against (#192). The app may have been launched for the
  /// intent alone, before anything started the load, so this starts it then: in a
  /// task of its own, since the load is the app's, and a query the system gives up
  /// on must not cancel it.
  func settledSearch() async -> IndexSearch? {
    if indexState == .idle {
      Task(name: "Bootstrap library") { await bootstrap() }
    }
    if !isIndexSettled {
      await withCheckedContinuation { settledIndexWaiters.append($0) }
    }
    return search
  }

  /// A tab of the navigation pane an App Intent asked to show beside a document
  /// (#192), which the reader showing that document in the tab the link went to
  /// takes.
  private(set) var inspectorRequest: DocumentRequest<InspectorTab>?
  /// The tab `inspectorRequest`'s link went to, once `carryOut` has sent it to one:
  /// another window showing the same document leaves the request alone.
  @ObservationIgnored private weak var inspectorRequestScene: NavigationModel?

  /// Routes `link` as `route(_:)` does, and asks its reader to show `tab`.
  func route(_ link: RFCLink, showing tab: InspectorTab) {
    inspectorRequest = DocumentRequest(id: link.id, value: tab)
    inspectorRequestScene = nil
    route(link)
  }

  /// The tab asked for beside `id` in `scene`, which is then no longer asked for; nil
  /// if none was, or it was asked for beside another document or in another tab.
  func takeInspectorRequest(for id: DocumentID, in scene: NavigationModel) -> InspectorTab? {
    guard inspectorRequestScene === scene else { return nil }
    return DocumentRequest.take(&inspectorRequest, for: id)
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
  ///
  /// A call while one is under way waits for that one, so that a background refresh
  /// that asks returns only once the file is in (#191).
  func refreshRevisions() async {
    if let revisionsRefresh { return await revisionsRefresh.value }
    let refresh = Task(name: "Refresh revisions") { await loadRevisions() }
    revisionsRefresh = refresh
    await refresh.value
    revisionsRefresh = nil
  }

  private func loadRevisions() async {
    if revisions == nil, let cached = await store.cachedRevisions() {
      revisions = cached
      compareBookmarks()
    }
    if let fetchedAt = revisionsFetchedAt, Date.now.timeIntervalSince(fetchedAt) < 86_400 {
      return
    }
    do {
      let fetched = try await client.fetchRevisions()
      try await store.storeRevisions(fetched.data)
      revisionsFetchedAt = .now
      if fetched.revisions != revisions {
        revisions = fetched.revisions
        compareBookmarks()
      }
    } catch {
      libraryLog.error(
        "fetching revisions failed: \(String(describing: error), privacy: .public)")
    }
  }

  /// The drafts revising `id`.
  func revisionsSummary(for id: DocumentID) -> RevisionsSummary {
    RevisionsSummary(revisions, for: id, now: .now)
  }

  // MARK: - Bookmark notifications

  /// The refresh of the index under way, the automatic daily check's or a Retry's,
  /// which a second one joins.
  @ObservationIgnored private var indexRefresh: Task<Void, Never>?
  /// The comparison under way. Each waits for the one before, so two never read the
  /// same baseline and both report what changed since.
  @ObservationIgnored private var bookmarkComparison: Task<Void, Never>?

  /// What a background refresh does (#191): the revisions, then the index when its
  /// daily check is due, each of which compares the bookmarks when it changes; and
  /// waits for each comparison, so the system does not suspend the app before it
  /// has posted.
  ///
  /// The revisions come first because the index check waits for a network that is
  /// neither expensive nor constrained (#314), which on a phone network can outlast
  /// iOS's background task. Canceling this, as iOS does when that task expires,
  /// cancels the check.
  func refreshForBookmarks() async {
    await bootstrap()
    if indexState == .loading {
      await withCheckedContinuation { indexWaiters.append($0) }
    }
    await refreshRevisions()
    await bookmarkComparison?.value
    let isIndexDue =
      switch indexState {
      case .ready(let checkedAt): IndexCheck.isDue(checkedAt: checkedAt, now: .now)
      case .failed: true
      case .idle, .loading: false
      }
    guard isIndexDue else { return }
    let check = checkIndex()
    await withTaskCancellationHandler {
      await check.value
    } onCancel: {
      check.cancel()
    }
    await bookmarkComparison?.value
  }

  /// The automatic daily check of the index, only on a cheap network (#314): the one
  /// under way, or a new one.
  @discardableResult
  private func checkIndex() -> Task<Void, Never> {
    if let indexRefresh { return indexRefresh }
    let check = Task(name: "Refresh index") {
      await refreshIndex(onExpensiveNetworks: false)
      indexRefresh = nil
    }
    indexRefresh = check
    return check
  }

  /// Retry, after the index failed: on any network, as a person asked for it, and
  /// joining a refresh already under way rather than fetching the index beside it.
  func retryIndex() {
    guard indexRefresh == nil else { return }
    indexRefresh = Task(name: "Refresh index") {
      await refreshIndex()
      indexRefresh = nil
    }
  }

  /// Compares the bookmarked RFCs with the last baseline, after every change to the
  /// index or the revisions, and posts what changed (`BookmarkNotifications`). Runs
  /// whether notifications are on or not, so the baseline is current when they are
  /// turned on.
  private func compareBookmarks() {
    let previous = bookmarkComparison
    bookmarkComparison = Task(name: "Compare bookmarks") {
      await previous?.value
      await compareBookmarksNow()
    }
  }

  private func compareBookmarksNow() async {
    // A store that fell back to memory (#152) reads as no bookmarks, which would
    // start every one afresh at the next launch that opens the real one.
    guard !AppData.isStoredInMemory else { return }
    let bookmarks: Set<DocumentID>
    do {
      // Read here rather than taken from `bookmarkedDocuments`, which a failed read
      // leaves empty: a baseline of no bookmarks would start every one afresh.
      bookmarks = try BookmarkStore.bookmarkedDocuments(in: container.mainContext)
    } catch {
      libraryLog.error(
        "reading bookmarks to compare failed: \(String(describing: error), privacy: .public)")
      return
    }
    let previous = await store.bookmarkBaseline()
    let baseline = BookmarkBaseline(
      bookmarks: bookmarks, index: index, revisions: revisions, carryingOver: previous)
    guard baseline != previous else { return }
    do {
      // Kept before anything is posted: a baseline that cannot be kept would report
      // the same changes on every refresh.
      try await store.storeBookmarkBaseline(baseline)
    } catch {
      libraryLog.error(
        "keeping the bookmark baseline failed: \(String(describing: error), privacy: .public)")
      return
    }
    let events = BookmarkEvents.between(previous, baseline)
    await BookmarkNotifications.post(BookmarkNotice.notices(for: events, index: index))
  }

  // MARK: - Working groups

  /// As `refreshRevisions()` does for its file, and when it does: the cached copy
  /// first, so a card works offline, then a fetch once a day. A failure keeps the
  /// cached copy and is logged, not shown.
  func refreshWorkingGroups() async {
    guard !isRefreshingWorkingGroups else { return }
    isRefreshingWorkingGroups = true
    defer { isRefreshingWorkingGroups = false }
    if workingGroups == nil, let cached = await store.cachedWorkingGroups() {
      workingGroups = cached
    }
    if let fetchedAt = workingGroupsFetchedAt, Date.now.timeIntervalSince(fetchedAt) < 86_400 {
      return
    }
    do {
      let fetched = try await client.fetchWorkingGroups()
      try await store.storeWorkingGroups(fetched.data)
      workingGroupsFetchedAt = .now
      if fetched.groups != workingGroups { workingGroups = fetched.groups }
    } catch {
      libraryLog.error(
        "fetching working groups failed: \(String(describing: error), privacy: .public)")
    }
  }

  // MARK: - Errata

  /// The copy of the errata feed kept, read the first time, then the RFC Editor asked
  /// for a newer one once a day, as the index is (#314): with the validators of the
  /// one kept, so an unchanged feed is a `304`, and on a network that is neither
  /// metered nor in Low Data Mode, since nobody is waiting for it. A failure keeps
  /// what there is and is logged, not shown.
  func refreshErrata() async {
    guard !isRefreshingErrata else { return }
    isRefreshingErrata = true
    defer { isRefreshingErrata = false }
    if errata == nil, let data = await store.cachedErrata() {
      errata = try? await Self.decodeErrata(data)
    }
    // Without a feed in memory, a `304` would leave nothing to show.
    let kept = errata == nil ? nil : store.errataCheck()
    if let kept, !IndexCheck.isDue(checkedAt: kept.checkedAt, now: .now) { return }
    if let errataAskedAt, !IndexCheck.isDue(checkedAt: errataAskedAt, now: .now) { return }
    do {
      let fetched = try await clientOnCheapNetworks.fetchErrataData(
        unlessMatching: kept?.validators(at: .now), onExpensiveNetworks: false)
      errataAskedAt = .now
      switch fetched {
      case .unchanged:
        if let kept { try await store.recordUnchangedErrata(kept) }
      case .changed(let data, let validators):
        // Shown before it is kept, so a failed write loses only the copy on disk.
        errata = try await Self.decodeErrata(data)
        try await store.storeErrata(data, validators: validators)
      }
    } catch {
      libraryLog.error(
        "refreshing the errata failed: \(String(describing: error), privacy: .public)")
    }
  }

  /// Off the main actor: the feed is every erratum ever reported.
  @concurrent
  private static func decodeErrata(_ data: Data) async throws -> Errata {
    try Errata.decode(data)
  }

  /// What a working group's card says: the group as the file describes it, if it
  /// does, and every RFC of the group the index has -- all of them, obsolete ones too,
  /// whatever the list's options hide: the card describes the group, not the list.
  func workingGroupSummary(_ acronym: String) -> WorkingGroupSummary {
    let rfcs: [RFCMetadata]
    if let cached = groupRFCs[acronym] {
      rfcs = cached
    } else {
      let filter = LibraryFilter.workingGroup(acronym)
      rfcs = index?.rfcs.filter { filter.includes($0) == true } ?? []
      groupRFCs[acronym] = rfcs
    }
    return WorkingGroupSummary(
      acronym: acronym, group: workingGroups?.group(acronym), rfcs: rfcs)
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

  /// Every working group the index names, folded, derived with the index for the
  /// same reason `topWorkingGroups` is: the iOS search field tokenizes its text with
  /// them on every body pass (#21).
  private(set) var knownWorkingGroups: Set<String> = []

  /// How many RFCs each filter the index decides lists, derived with the index for
  /// the same reason `topWorkingGroups` is (#344).
  private(set) var indexCounts: [LibraryFilter: Int] = [:]

  /// What force-click previews showed, kept for the next preview of the same
  /// document in the same style (#374), which then shows its text at once rather
  /// than a spinner. Four, at 4.5 to 8 MB a build.
  ///
  /// The whole preview rather than the build alone, so a build is never paired with
  /// another parse of its document. A document's previews go when it is removed or
  /// evicted (`forgetPreviews`), as the store's parse of it does, so what is gone
  /// from the disk is gone from memory too. Empty on iOS, which has no such preview.
  ///
  /// Not observed: it is a memo, and nothing is drawn from it.
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

  /// `list` over the index as it stands, made off the main actor: what a tab stores
  /// and its list reads (#597). `hits` are the search's for `list.query` over this
  /// index, if a listing found them already. Nil while there is no index.
  func listed(_ list: LibraryList, hits: [RFCMetadata]? = nil) async -> ListedRows? {
    guard let index else { return nil }
    return await Self.listed(
      list, in: index, indexVersion: indexVersion, search: search, hits: hits)
  }

  /// `listed(_:hits:)` on the main actor, for a script, which reads the list
  /// straight after changing what it lists.
  func listedNow(_ list: LibraryList, hits: [RFCMetadata]? = nil) -> ListedRows? {
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

  /// The subtitle under the list's title: how many documents it shows. Empty until
  /// the list is first made — "0 Documents" would be a claim about the library, not a
  /// list that has not arrived yet.
  func listSubtitle(for scene: NavigationModel) -> String {
    scene.listed.map { DocumentCount.label($0.rows.count) } ?? ""
  }

  /// The Go to RFC palette's candidates for what was typed, best first.
  ///
  /// Off the main actor: a short query like `http` scans every title and abstract
  /// (the "Search: http" benchmark of `make benchmark`), and this runs as the reader
  /// types.
  func suggestions(for query: String, limit: Int) async -> [DocumentID] {
    guard let search else { return [] }
    return await Self.suggestions(in: search, for: query, limit: limit)
  }

  /// What the Go to RFC palette and sheet list under what was typed, once the reader
  /// has paused: run per change of the query and canceled by the next (`Debounce`).
  ///
  /// - Returns: nil for nothing typed, or when the reader typed on first; no hits,
  ///   without searching, for a link, which names its document outright and which
  ///   no title or abstract contains, and while the index is still loading.
  func quickOpenHits(for query: String) async -> [DocumentID]? {
    guard !query.isEmpty else { return nil }
    if query.contains("://"), DocumentReference.link(from: query) != nil { return [] }
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

  // MARK: - Scene routing

  /// The open tabs, most recently used first, and the link waiting for one: which tab
  /// a link goes to, and when, is `SceneRegistry`'s to decide (#137). This carries out
  /// its decisions. Not observed: no view reads it.
  @ObservationIgnored private var sceneRegistry = SceneRegistry<NavigationModel>()

  #if os(macOS)
    /// The window layer, set by `AppDelegate` at launch. Weak: the delegate owns the
    /// windows, and the library only asks it for them.
    @ObservationIgnored weak var windows: (any WindowOpening)?
  #endif

  /// Registers a new scene, and gives it the link it was opened for if it was opened
  /// for one and needs nothing more (`SceneRegistry`). Nil for a window from the menu
  /// or at launch, which lands on the library as before.
  func register(_ scene: NavigationModel) {
    if let delivery = sceneRegistry.register(scene) { carryOut(delivery) }
  }

  func unregister(_ scene: NavigationModel) {
    sceneRegistry.unregister(scene)
  }

  /// Makes a scene the most recently used, which is where an untargeted link lands
  /// when no tab is preferred over it -- on macOS `route(_:)` prefers the tab of the
  /// window that was key last.
  func activate(_ scene: NavigationModel) {
    sceneRegistry.activate(scene)
  }

  /// The index has arrived, or failed to: a link held for it goes to its tab now
  /// (#241), where `NavigationModel.open(_:in:)` can resolve a BCP or STD to its first
  /// RFC.
  private func settleIndex() {
    isIndexSettled = true
    let waiters = settledIndexWaiters
    settledIndexWaiters = []
    for waiter in waiters { waiter.resume() }
    let preferred = preferredScene
    sceneRegistry.indexSettled(preferring: { $0 === preferred }).forEach(carryOut)
  }

  /// The tab a link from outside goes to when nothing else decides: on macOS the front
  /// tab of the window made key last (#277); none on iOS.
  private var preferredScene: NavigationModel? {
    #if os(macOS)
      windows?.activeNavigation
    #else
      nil
    #endif
  }

  /// Sends `link` to exactly one scene: the tab already showing that document if
  /// there is one, otherwise the tab the reader is in -- on macOS the one whose
  /// window was key last, which a tab opened in the background does not displace --
  /// and failing that the most recently used tab.
  ///
  /// A link that arrives before any scene has registered, or a BCP or STD link that
  /// arrives before the index has, is held by the registry and delivered once what it
  /// needs is there (#140, #241).
  ///
  /// On macOS the app makes every window itself, so the tab that takes the link is
  /// also brought forward: `makeKeyAndOrderFront` selects a tab within its group.
  /// With every window closed there is no scene coming to take the link, so one is
  /// opened for it -- the way `openInNewScene` does -- rather than leaving it for
  /// whatever window the reader next opens, possibly minutes later. iOS brings up a
  /// scene of its own on launch, and that one registers.
  func route(_ link: RFCLink) {
    let preferred = preferredScene
    switch sceneRegistry.route(link, showing: \.heldDocument, preferring: { $0 === preferred }) {
    case .deliver(let delivery):
      carryOut(delivery)
    case .openWindow:
      #if os(macOS)
        windows?.openWindow()
      #endif
    case .wait:
      break
    }
  }

  private func carryOut(_ delivery: SceneRegistry<NavigationModel>.Delivery) {
    if inspectorRequest?.id == delivery.link.id { inspectorRequestScene = delivery.scene }
    if delivery.bringsForward {
      deliver(delivery.link, to: delivery.scene)
    } else {
      delivery.scene.open(delivery.link, in: index)
    }
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

  #if os(macOS)
    /// Opens a window for `link`, which it takes in `register(_:)`.
    private func openInNewWindow(_ link: RFCLink) {
      sceneRegistry.hold(link, bringsForward: true)
      windows?.openWindow()
    }
  #endif

  /// Opens `link` the way the click asked for: in `scene`, or in a tab of its own.
  ///
  /// The single place an activation becomes an effect, so Command-click means the
  /// same thing on a cross reference in the prose, a reference in the inspector and
  /// a button in the status banner. Every gesture that owns its own click goes
  /// through here; the document list is the exception, and says why at its binding.
  ///
  /// `arrival` is `.citation` for a link followed inside the reader, which on iOS
  /// pushes a reader over the one it was followed in (#263).
  func open(
    _ id: DocumentID, activation: LinkActivation, in scene: NavigationModel,
    arrival: HistoryEntry.Arrival = .root
  ) {
    open(RFCLink(id: id), activation: activation, in: scene, arrival: arrival)
  }

  func open(
    _ link: RFCLink, activation: LinkActivation, in scene: NavigationModel,
    arrival: HistoryEntry.Arrival = .root
  ) {
    switch activation {
    case .here:
      scene.open(link, in: index, arrival: arrival)
    case .newTab(let inBackground):
      openInNewScene(link, inBackground: inBackground)
    }
  }

  /// Opens `link` in a tab of its own, either behind the current one or in front.
  ///
  /// On macOS through AppKit, because the app makes its own windows: there is no
  /// `WindowGroup` to ask, and `newWindowForTab:` is answered by our own window
  /// controller rather than by SwiftUI. Nothing can be passed to a window as it is
  /// made, so the link is held by the registry for the window that appears to take it
  /// in `register(_:)`.
  ///
  /// On iPad a window of its own, asked of UIKit with a user activity carrying the
  /// link, which the new scene reads (`SceneRequest`, #158). Not `openWindow`: the
  /// app's `WindowGroup` is a plain one, which cannot take a value. A new window
  /// always comes to the front there, so `inBackground` does not apply.
  private func openInNewScene(_ link: RFCLink, inBackground: Bool) {
    #if os(macOS)
      sceneRegistry.hold(link, bringsForward: !inBackground)
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

  func document(for id: DocumentID) async throws -> RFCDocument {
    let entry = index?[id]
    let document = try await store.document(
      id, formats: entry?.formats ?? [], entry: entry, client: client)
    await evictIfGrown()
    return document
  }

  /// Records an RFC opened without a load as `document(for:)` records a loaded one:
  /// a pointer the pack lists, shown as its original (#316).
  func markOpened(_ id: DocumentID) async {
    await store.markOpened(id)
  }

  /// Installs the legacy XML pack from an `.aar`, a folder or a URL; see
  /// `DocumentStore.installLegacyPack(from:)`. A developer's path for now (#36).
  func installLegacyPack(from source: URL) async throws -> InstalledPack {
    let pack = try await store.installLegacyPack(from: source)
    await refreshPointersInPack()
    return pack
  }

  func originalText(for id: DocumentID) async throws -> String {
    let text = try await store.originalText(id, client: client)
    await evictIfGrown()
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
  /// keep the document offline; what was read in the last month; a document marked
  /// Keep Offline, whose cached body waits for the keeper to move it (#358); and
  /// whatever a window has open, which includes the document just fetched.
  private func pinnedDocuments() throws -> Set<DocumentID> {
    let context = container.mainContext
    let monthAgo = Date.now.addingTimeInterval(-30 * 86_400)
    let read = try ReadingPositionStore.read(since: monthAgo, in: context)
    let bookmarked = try BookmarkStore.bookmarkedDocuments(in: context)
    // Read here, as the store learns them only when the keeper first runs.
    let marked = try OfflineMarkStore.markedDocuments(in: context)
    let open = sceneRegistry.open.compactMap(\.selection)
    return bookmarked.union(read).union(marked).union(open)
  }

  // MARK: - Storage (#358)

  /// What each tier holds, for Settings' Storage tab, once the keeper has made the
  /// moves asked of it so far; a fetch still running is counted when it lands.
  func storageUsage() async -> (kept: StorageUsage, cache: StorageUsage) {
    await offlineKeeper.untilRunsEnd()
    return await store.storageUsage()
  }

  /// Empties the reading cache, but for what a window has open and what is wanted
  /// offline, whose body waits there for the keeper to move it. The marks are read
  /// here, as for eviction, since the store learns them only when the keeper runs;
  /// when they cannot be read, nothing is removed.
  func clearCache() async {
    let spared: Set<DocumentID>
    do {
      spared = try OfflineMarkStore.markedDocuments(in: container.mainContext)
        .union(wantedOffline).union(sceneRegistry.open.compactMap(\.selection))
    } catch {
      libraryLog.error(
        "Clear Cache skipped, reading the marks failed: \(String(describing: error), privacy: .public)"
      )
      return
    }
    forgetPreviews(of: await store.clearCache(sparing: spared))
  }

  /// Keeps nothing offline any more: removes every mark, on every device, since marks
  /// are synced, and turns off keeping this device's bookmarks. The bodies go back
  /// into the reading cache, as an unmarked one does, where eviction or Clear Cache
  /// removes them. A removal that could not be saved is logged and changes nothing:
  /// it is made in a context of its own, discarded with it, since rolling back the
  /// app's context would discard whatever else waits there to be saved, such as a
  /// bookmark whose save failed.
  func removeAllOffline() {
    do {
      try OfflineMarkStore.removeAll(in: ModelContext(container))
    } catch {
      libraryLog.error(
        "removing every Keep Offline mark failed: \(String(describing: error), privacy: .public)")
      return
    }
    storeKeepsBookmarksOffline(false)
    // One reconciliation for both: the marks' refresh runs it when they changed.
    let marks = offlineMarks
    refreshOfflineMarks()
    if offlineMarks == marks { wantedOfflineChanged() }
  }

  func isDownloaded(_ id: DocumentID) async -> Bool {
    await store.isCached(id)
  }

  /// The size of `id`'s kept body, once what keeping it offline started has ended:
  /// a mark from anywhere, the menu, a script or another device, fetches after it is
  /// made.
  func keptSize(_ id: DocumentID) async -> Int? {
    await offlineKeeper.untilSettled(id)
    return await store.downloadedSize(id)
  }

  /// The documents the reader has opened, most recent first, a BCP, STD or FYI
  /// among them as itself (#321).
  ///
  /// Fetched on demand rather than observed, and that is the point: the Recently
  /// read list is history as of the moment the filter is entered, and a live query
  /// re-sorted it under the click that was reading it. `NavigationModel` takes one
  /// of these when its filter changes, exactly as it takes `availableOfflineNumbers`.
  ///
  /// Empty when the fetch fails, which is logged: the list is only shown, and
  /// nothing is decided by its being empty.
  func recentlyRead() -> [DocumentID] {
    do {
      return try ReadingPositionStore.recentlyRead(in: container.mainContext)
    } catch {
      libraryLog.error(
        "reading the recently read list failed: \(String(describing: error), privacy: .public)")
      return []
    }
  }

  // MARK: - Reading paths (#189)

  enum ReadingPathResult {
    case path(ReadingPath)
    /// No `indexes` pack is installed, which the sheet says rather than computing a
    /// partial path from the documents in the cache.
    case noIndex
    /// The pack is there and did not read: logged, and said in a sentence.
    case failed
  }

  /// The reading path from `root`, `depth` citations deep, read from the installed
  /// `indexes` pack off the main actor.
  func readingPath(from root: DocumentID, depth: Int) async -> ReadingPathResult {
    guard let url = await store.citationIndexURL() else { return .noIndex }
    do {
      return .path(try await CitationIndex.readingPath(from: root, depth: depth, in: url))
    } catch {
      libraryLog.error(
        "reading the citation index failed: \(String(describing: error), privacy: .public)")
      return .failed
    }
  }

  /// Marks `id` Keep Offline, or removes its mark, as the Info pane's toggle does
  /// (#358). Marking moves a copy already read, or downloads one now, on any
  /// network, since somebody is waiting for it, and throws when that fails: the mark
  /// stays, and its row in Available Offline offers Retry until the device moves to
  /// another network, when the keeper tries again by itself. Unmarking moves the
  /// body back into the reading cache rather than deleting it, and leaves a download
  /// running for it. A mark that could not be saved is logged, as a bookmark's is
  /// (#125), and leaves the toggle as it was.
  func setKeptOffline(_ id: DocumentID, _ isKept: Bool) async throws {
    guard mark(id, keptOffline: isKept), isKept else { return }
    try await offlineKeeper.fetchNow(id)
  }

  /// `setKeptOffline` from a list's context menu or a script, which have nowhere to
  /// show a failed download either. The mark is saved before this returns, so a
  /// script that reads it back reads what it set, and only the download goes on
  /// after.
  func setKeptOfflineInBackground(_ id: DocumentID, _ isKept: Bool) {
    guard mark(id, keptOffline: isKept), isKept else { return }
    // The keeper logs a failed download itself.
    Task(name: "Keep offline") { try? await offlineKeeper.fetchNow(id) }
  }

  /// Saves the mark and reads the marks again at once, rather than when the save's
  /// notification arrives, which is after the next turn of the run loop. Answers
  /// whether it was saved.
  private func mark(_ id: DocumentID, keptOffline isKept: Bool) -> Bool {
    do {
      try OfflineMarkStore.setMarked(id, isKept, in: container.mainContext)
    } catch {
      libraryLog.failure(of: id, "marking Keep Offline failed", error)
      return false
    }
    refreshOfflineMarks()
    return true
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
}
