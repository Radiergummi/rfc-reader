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
    /// A window of its own, in front, whatever the user's "Prefer tabs" setting.
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
/// positions, collections — is SwiftData's; `userData` holds the sets read from it
/// that every tab shows, and this answers for them.
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

  /// The index and its search, the full-text index and Just Published (#595).
  @ObservationIgnored private let indexes: IndexRepository

  /// `IndexRepository.index`.
  var index: RFCIndex? { indexes.index }
  /// `IndexRepository.indexableRFCs`.
  var indexableRFCs: [RFCMetadata] { indexes.indexableRFCs }
  /// `IndexRepository.indexVersion`.
  var indexVersion: Int { indexes.indexVersion }
  /// `IndexRepository.indexState`.
  var indexState: IndexState { indexes.indexState }
  /// `IndexRepository.indexBytesReceived`.
  var indexBytesReceived: Int64? { indexes.indexBytesReceived }
  /// `IndexRepository.indexPlaceholder`.
  var indexPlaceholder: IndexPlaceholder? { indexes.indexPlaceholder }
  /// `IndexRepository.recent`.
  var recent: [RecentRFC] { indexes.recent }

  @ObservationIgnored private var activations: (any NSObjectProtocol)?

  /// The revisions, the working groups, the errata and the registries, read from the
  /// copies kept and fetched when due (#595).
  @ObservationIgnored private let dataFiles: DataFileRefresher

  /// `DataFileRefresher.revisions`.
  var revisions: RFCRevisions? { dataFiles.revisions }
  /// `DataFileRefresher.workingGroups`.
  var workingGroups: WorkingGroups? { dataFiles.workingGroups }
  /// `DataFileRefresher.errata`.
  var errata: Errata? { dataFiles.errata }
  /// `DataFileRefresher.registriesVersion`.
  var registriesVersion: Int { dataFiles.registriesVersion }

  /// The sets read from the user's data, and where a bookmark or a collection is
  /// changed (#595).
  @ObservationIgnored private let userData: UserDataMirror

  /// `UserDataMirror.bookmarkedDocuments`.
  var bookmarkedDocuments: Set<DocumentID> { userData.bookmarkedDocuments }

  /// The presentation the reader chose from a block's menu, per document, for the
  /// app's session. Here rather than in `DocumentSession`, which goes when the
  /// reader goes back. Not persisted.
  private(set) var chosenPresentations:
    [ReadableDocument: [PresentationKey: PresentationChoices.Presentation]] = [:]

  /// The reader's choices in `id`, over the preference for every document.
  func presentationChoices(for id: ReadableDocument, drawsDiagrams: Bool) -> PresentationChoices {
    PresentationChoices(drawsDiagrams: drawsDiagrams, chosen: chosenPresentations[id] ?? [:])
  }

  func choose(
    _ presentation: PresentationChoices.Presentation, for key: PresentationKey,
    in id: ReadableDocument
  ) {
    chosenPresentations[id, default: [:]][key] = presentation
  }

  /// `UserDataMirror.collections`.
  var collections: CollectionSnapshot { userData.collections }

  /// `UserDataMirror.annotations`: every highlight (#522).
  var annotations: AnnotationSnapshot { userData.annotations }

  /// `UserDataMirror.editAnnotations`.
  @discardableResult
  func editAnnotations(_ change: (ModelContext) throws -> Void) -> Bool {
    userData.editAnnotations(change)
  }

  /// `UserDataMirror.offlineMarks`. With the bookmarks when `keepsBookmarksOffline`
  /// is on, what is wanted offline, and what Available Offline lists, whether or not
  /// a body has arrived yet.
  var offlineMarks: Set<DocumentID> { userData.offlineMarks }

  /// The documents' bodies on the device: loads, eviction, Clear Cache, Keep Offline
  /// and the reading path (#595). Lazy, as its closures read the index and the open
  /// tabs through `self`.
  @ObservationIgnored private lazy var documents = DocumentRepository(
    store: store, client: client,
    clientFailingOnExpensiveNetworks: RFCEditorClient(
      transport: URLSessionTransport(session: .rfcEditorFailingOnExpensiveNetworks)),
    drafts: DraftStore(), userData: userData, isStoredInMemory: AppData.isStoredInMemory,
    index: { [weak self] in self?.index },
    openDocuments: { [weak self] in
      self?.sceneRegistry.open.flatMap { scene in
        [scene.shown.map(ReadableDocument.rfc), scene.shownDraft.map(ReadableDocument.draft)]
          .compactMap(\.self)
      } ?? []
    },
    networkDecision: { [weak self] in self?.network.decision(for: $0) })

  /// `DocumentRepository.keepsBookmarksOffline`.
  var keepsBookmarksOffline: Bool { documents.keepsBookmarksOffline }

  /// "Show April 1st RFCs", from Settings' Advanced tab (#713): every tab's list
  /// and Just Published follow it as it changes, so it is held here, observed,
  /// rather than read from user defaults by each.
  private(set) var showsAprilFirst = LibrarySettings(defaults: .standard).showsAprilFirst

  /// Shows or hides the April 1st RFCs in every list, search and Just Published.
  func setShowsAprilFirst(_ isOn: Bool) {
    UserDefaults.standard.set(isOn, forKey: LibraryPreferences.showsAprilFirstKey)
    showsAprilFirst = isOn
  }

  /// Just Published, less the April 1st RFCs while they are hidden.
  var justPublished: [RecentRFC] {
    AprilFirstRFCs.justPublished(recent, showsAprilFirst: showsAprilFirst)
  }

  /// `DocumentRepository.availableOfflineNumbers`.
  var availableOfflineNumbers: Set<Int> { documents.availableOfflineNumbers }

  /// `DocumentRepository.offlineStatus`.
  var offlineStatus: OfflineStatus { documents.offlineStatus }

  /// The path and Low Power Mode, which decide whether the keeper fetches a mark
  /// that arrived from another device now or waits.
  @ObservationIgnored private let network = NetworkConditions()

  /// `IndexRepository.pointersInPack`.
  var pointersInPack: Set<DocumentID> { indexes.pointersInPack }

  /// `DocumentRepository.hasCitationIndex`.
  var hasCitationIndex: Bool { documents.hasCitationIndex }

  /// `UserDataMirror.recentlyReadCount`.
  var recentlyReadCount: Int { userData.recentlyReadCount }

  /// `UserDataMirror.followedGroups`: the working groups the reader follows (#731),
  /// by acronym in lower case.
  var followedGroups: Set<String> { userData.followedGroups }

  /// The Working Groups section of the sidebar: the followed groups, then the
  /// busiest of the rest.
  var sidebarWorkingGroups: [String] {
    WorkingGroupFollowing.sidebarGroups(followed: followedGroups, top: topWorkingGroups)
  }

  func isFollowed(_ group: String) -> Bool {
    followedGroups.contains(group.lowercased())
  }

  /// Follows the group or stops following it. A failure is logged rather than shown,
  /// as a bookmark's is (#125), and leaves the command as it was. The save is
  /// mirrored, which compares at once (`init`).
  func toggleFollowed(_ group: String) {
    do {
      try userData.setFollowed(group, !isFollowed(group))
    } catch {
      libraryLog.error(
        "following a working group failed: \(String(describing: error), privacy: .public)")
    }
  }

  /// The user's data, which `userData` reads its sets from.
  var container: ModelContainer { userData.container }

  private init(container: ModelContainer) {
    userData = UserDataMirror(container: container)
    let store = DocumentStore()
    let client = RFCEditorClient()
    let clientOnCheapNetworks = RFCEditorClient(
      transport: URLSessionTransport(session: .rfcEditorOnCheapNetworks))
    self.store = store
    self.client = client
    self.clientOnCheapNetworks = clientOnCheapNetworks
    dataFiles = DataFileRefresher(
      store: store, client: client, clientOnCheapNetworks: clientOnCheapNetworks)
    indexes = IndexRepository(
      store: store, client: client, clientOnCheapNetworks: clientOnCheapNetworks)
    dataFiles.onRevisionsChanged = { [weak self] in self?.bookmarkWatcher.compare() }
    indexes.onApplied = { [weak self] index in self?.indexApplied(index) }
    indexes.onSettled = { [weak self] in self?.deliverLinksHeldForIndex() }
    indexes.onTextIndexChanged = { [weak self] in self?.indexSectionsForSpotlight() }
    // What is gone from the disk goes from memory too.
    documents.onRemoved = { [weak self] removed in self?.forgetPreviews(of: removed) }
    userData.onBookmarksChanged = { [weak self] in self?.bookmarksChanged() }
    userData.onCollectionsChanged = { [weak self] snapshot in
      // A collection deleted in another tab, or on another device, is not left on
      // screen with no name and nothing in it.
      for scene in self?.sceneRegistry.open ?? [] {
        scene.keepFilter(in: snapshot)
      }
    }
    // A document read for the first time: what a phrase can name (#192).
    userData.onRecentlyReadCountChanged = { RFCReaderShortcuts.refreshParameters() }
    userData.onOfflineMarksChanged = { [weak self] in self?.documents.wantedOfflineChanged() }
    // Compared at once, so the baseline lists a newly followed group's RFCs now, a
    // group followed on another device included: a group followed reports nothing it
    // published before (`BookmarkBaseline`), and left to the next refresh of the
    // index, what that refresh brings would count as before (#731).
    userData.onFollowedGroupsChanged = { [weak self] in self?.bookmarkWatcher.compare() }
    userData.start()
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
        Task(name: "Refresh data files") { await self.dataFiles.refreshAll() }
        self.recheckSpotlight()
      }
    }
    network.start(
      // A new path: what waited may go ahead, what runs may have to wait, and what
      // failed may succeed on it.
      pathChanged: { [weak self] in self?.documents.reconcileOffline(forgettingFailures: true) },
      // Low Power Mode decides whether a fetch waits, not whether it fails.
      powerChanged: { [weak self] in self?.documents.reconcileOffline() })
  }

  /// `DocumentRepository.isAvailableOffline`.
  func isAvailableOffline(_ id: DocumentID) -> Bool {
    documents.isAvailableOffline(id)
  }

  /// `DocumentRepository.setKeepsBookmarksOffline`.
  func setKeepsBookmarksOffline(_ isOn: Bool) {
    documents.setKeepsBookmarksOffline(isOn)
  }

  /// `DocumentRepository.downloadNow`.
  func downloadNow(_ id: DocumentID) {
    documents.downloadNow(id)
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

  /// A collection made from a query as a tab lists it unsearched, for the sidebar's
  /// count (#355): the same evaluation, so the list and the count cannot differ. It
  /// reads, as a tab does, only what its query asks for.
  func list(of entry: CollectionSnapshot.Entry) -> LibraryList {
    LibraryList.reading(
      .collection(entry.id), query: "", options: ListOptions(), from: LibrarySources(library: self))
  }

  /// How many documents `list` lists, made off the main actor as a tab's list is. Nil
  /// while there is no index.
  func count(of list: LibraryList) async -> Int? {
    await listed(list)?.rows.count
  }

  /// `UserDataMirror.editCollections`.
  @discardableResult
  func editCollections(_ change: (ModelContext) throws -> Void) -> Bool {
    userData.editCollections(change)
  }

  /// What an undone or redone removal from a collection does with its failure:
  /// logged, as `editCollections` logs the change's own (#759).
  func collectionUndoFailed(_ error: any Error) {
    libraryLog.error(
      "undoing or redoing a removal from a collection failed: \(String(describing: error), privacy: .public)"
    )
  }

  /// Adds the bookmark or removes it (`UserDataMirror.toggleBookmark`), titled from
  /// the index or else `documentTitle`, what an open reader has parsed. A removal
  /// registers its undo with `undoManager` (#769).
  func toggleBookmark(
    _ id: DocumentID, documentTitle: String? = nil, undoManager: UndoManager? = nil
  ) {
    let title = DocumentActions.bookmarkTitle(
      metadata: metadata(id), documentTitle: documentTitle, id: id)
    userData.toggleBookmark(id, title: title, undoManager: undoManager)
  }

  /// What a change to the bookmarks means beyond the set itself.
  private func bookmarksChanged() {
    documents.bookmarksChanged()
    // So that the baseline holds a new bookmark from now on, and reports a change to
    // it from the next refresh rather than taking it for one from before (#191).
    bookmarkWatcher.compare()
  }

  private let client: RFCEditorClient
  /// For the automatic daily check, which waits for a network that is neither
  /// metered nor in Low Data Mode instead of failing (#314).
  private let clientOnCheapNetworks: RFCEditorClient
  private let store: DocumentStore

  /// `IndexRepository.textIndexVersion`.
  var textIndexVersion: Int { indexes.textIndexVersion }

  /// `IndexRepository.indexAllRun`.
  var indexAllRun: IndexAllRun { indexes.indexAllRun }

  /// `IndexRepository.hasTextIndex`.
  var hasTextIndex: Bool { indexes.hasTextIndex }

  // MARK: - Bootstrap

  /// The index (`IndexRepository.bootstrap()`), then what waits for it: the
  /// citation index, the data files and, on the Mac, the registries.
  func bootstrap() async {
    guard indexState == .idle else { return }
    #if DEBUG
      installPackFromLaunchArgument()
    #endif
    // Nothing above awaits: the repository starts the parse of the index kept before
    // its first suspension, so that it runs beside the first window (#367).
    await indexes.bootstrap()
    // Only the Reading Path items wait for it, so not the list.
    Task(name: "Look for a citation index") { await documents.refreshCitationIndex() }
    Task(name: "Refresh data files") { await dataFiles.refreshAll() }
    // On the Mac at launch, where ⌘L may come first thing. iOS reads them as its Go
    // to RFC sheet opens (`refreshRegistriesIfDue()`): most launches of an iPhone
    // never open it.
    #if os(macOS)
      // Unless an intent has read them already (#192).
      dataFiles.loadRegistriesUnlessChecked()
    #endif
  }

  // MARK: - Registries

  /// `DataFileRefresher.refreshRegistriesIfDue()`.
  func refreshRegistriesIfDue() {
    dataFiles.refreshRegistriesIfDue()
  }

  /// `DataFileRefresher.registryMatches(for:)`.
  func registryMatches(for query: String) -> [RegistryEntry] {
    dataFiles.registryMatches(for: query)
  }

  /// `DataFileRefresher.loadedRegistryEntries()`.
  func loadedRegistryEntries() async -> [RegistryEntry] {
    await dataFiles.loadedRegistryEntries()
  }

  #if DEBUG
    /// `-installPack <url>`, a developer's way to install a pack from a URL or a
    /// path (#36), and `-installIndexesPack <url>` for the `indexes` pack (#189).
    /// Logged, not shown: nothing on screen asked for it.
    private func installPackFromLaunchArgument() {
      let legacy = UserDefaults.standard.string(forKey: "installPack")
      let indexesPack = UserDefaults.standard.string(forKey: "installIndexesPack")
      guard legacy != nil || indexesPack != nil else { return }
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
        if let indexesPack {
          do {
            let pack = try await store.installIndexesPack(
              from: PackInstaller.source(fromArgument: indexesPack))
            await documents.refreshCitationIndex()
            libraryLog.info("installed indexes pack \(pack.manifest.version, privacy: .public)")
          } catch {
            libraryLog.error(
              "installing the indexes pack failed: \(String(describing: error), privacy: .public)")
          }
        }
      }
    }
  #endif

  /// What an index applied means beyond the index itself.
  private func indexApplied(_ index: RFCIndex) {
    indexForSpotlight(index.rfcs)
    indexSectionsForSpotlight()
    bookmarkWatcher.compare()
    // What waited for the formats the index lists.
    documents.reconcileOffline()
    // The RFCs a phrase can name are the ones read recently, which need the index.
    RFCReaderShortcuts.refreshParameters()
  }

  // MARK: - App Intents

  /// `IndexRepository.hasSettled`.
  var hasIndexSettled: Bool { indexes.hasSettled }

  /// The index's search once the index has loaded, or nil if it could not: what an
  /// App Intent's queries run against (#192). The app may have been launched for the
  /// intent alone, before anything started the load, so this starts it then: in a
  /// task of its own, since the load is the app's, and a query the system gives up
  /// on must not cancel it.
  func settledSearch() async -> IndexSearch? {
    if indexState == .idle {
      Task(name: "Bootstrap library") { await bootstrap() }
    }
    return await indexes.settledSearch()
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

  /// The indexing of sections for Spotlight under way (#178).
  @ObservationIgnored private var spotlightSectionIndexing: Task<Void, Never>?
  /// Whether the full-text index changed since the indexing under way began.
  @ObservationIgnored private var spotlightSectionsChanged = false
  /// Whether the next indexing empties Spotlight's sections and indexes them all.
  @ObservationIgnored private var spotlightSectionsRebuild = false

  /// Brings Spotlight's sections to what the full-text index holds from stored
  /// bodies, once both it and the index, which names each section's document, are
  /// there. Coalesced: a change during an indexing runs one more once it is done,
  /// so a batch is never thrown away and two never write the record at once.
  /// `rebuilding`, for rows that changed under the dates they had.
  private func indexSectionsForSpotlight(rebuilding: Bool = false) {
    spotlightSectionsChanged = true
    spotlightSectionsRebuild = spotlightSectionsRebuild || rebuilding
    guard spotlightSectionIndexing == nil else { return }
    spotlightSectionIndexing = Task(name: "Index sections for Spotlight", priority: .utility) {
      [weak self] in
      await self?.indexSectionsWhileChanged()
    }
  }

  private func indexSectionsWhileChanged() async {
    while spotlightSectionsChanged, let textIndexer = indexes.textIndexer, let index {
      spotlightSectionsChanged = false
      let rebuilding = spotlightSectionsRebuild
      spotlightSectionsRebuild = false
      await SpotlightIndexer.updateSections(
        from: textIndexer, rfcs: index.rfcs, rebuilding: rebuilding)
    }
    spotlightSectionIndexing = nil
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

  /// The drafts revising `id`.
  func revisionsSummary(for id: DocumentID) -> RevisionsSummary {
    RevisionsSummary(revisions, for: id, now: .now)
  }

  // MARK: - Bookmark notifications

  /// The bookmark comparison and the background refresh that drives it (#191, #595).
  /// Lazy, as its launch is `bootstrap()`, read through `self`.
  @ObservationIgnored private(set) lazy var bookmarkWatcher = BookmarkWatcher(
    store: store, container: container, indexes: indexes, dataFiles: dataFiles,
    isStoredInMemory: AppData.isStoredInMemory,
    bootstrap: { [weak self] in await self?.bootstrap() },
    post: { await BookmarkNotifications.post($0) })

  /// `IndexRepository.retry()`.
  func retryIndex() {
    indexes.retry()
  }

  /// `IndexRepository.refreshNow()`.
  func refreshIndexNow() async {
    await indexes.refreshNow()
  }

  // MARK: - Working groups

  /// What a working group's card says: the group as the file describes it, if it
  /// does, and every RFC of the group the index has -- all of them, obsolete ones too,
  /// whatever the list's options hide: the card describes the group, not the list.
  func workingGroupSummary(_ acronym: String) -> WorkingGroupSummary {
    let rfcs = indexes.rfcs(ofGroup: acronym)
    return WorkingGroupSummary(
      acronym: acronym, group: workingGroups?.group(acronym), rfcs: rfcs)
  }

  // MARK: - Lists

  /// `IndexRepository.metadata(_:)`.
  func metadata(_ id: DocumentID) -> RFCMetadata? {
    indexes.metadata(id)
  }

  /// `IndexRepository.citedDocument(_:)`.
  func citedDocument(_ id: DocumentID) -> CitedDocument? {
    indexes.citedDocument(id)
  }

  /// `IndexRepository.seriesMembers(_:)`.
  func seriesMembers(_ id: DocumentID) -> String? {
    indexes.seriesMembers(id)
  }

  /// `IndexRepository.documentShown(for:)`.
  func documentShown(for id: DocumentID) -> DocumentID? {
    indexes.documentShown(for: id)
  }

  /// `IndexRepository.topWorkingGroups`.
  var topWorkingGroups: [String] { indexes.topWorkingGroups }

  /// `IndexRepository.knownWorkingGroups`.
  var knownWorkingGroups: Set<String> { indexes.knownWorkingGroups }

  /// `IndexRepository.indexCounts`.
  var indexCounts: [LibraryFilter: Int] { indexes.indexCounts }

  /// What force-click previews showed, kept for the next preview of the same
  /// document in the same style (#374), which then shows its text at once rather
  /// than a spinner. Four, since a build of a large RFC holds megabytes.
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

  /// `IndexRepository.listed(_:hits:)`.
  func listed(_ list: LibraryList, hits: [RFCMetadata]? = nil) async -> ListedRows? {
    await indexes.listed(list, hits: hits)
  }

  /// `IndexRepository.indexAllRFCs()`.
  func indexAllRFCs() {
    indexes.indexAllRFCs()
  }

  /// `IndexRepository.unindexedRFCCount()`.
  func unindexedRFCCount() async -> Int? {
    await indexes.unindexedRFCCount()
  }

  /// `IndexRepository.textIndexUsage()`.
  func textIndexUsage() async -> TextIndexer.Usage? {
    await indexes.textIndexUsage()
  }

  /// `IndexRepository.removeIndexOfAllRFCs()`.
  func removeIndexOfAllRFCs() async {
    await indexes.removeIndexOfAllRFCs()
  }

  /// `IndexRepository.textSearch(_:)`.
  func textSearch(_ list: LibraryList) async -> TextIndexer.Found? {
    await indexes.textSearch(list)
  }

  /// `IndexRepository.listedNow(_:hits:)`.
  func listedNow(_ list: LibraryList, hits: [RFCMetadata]? = nil) -> ListedRows? {
    indexes.listedNow(list, hits: hits)
  }

  /// The subtitle under the list's title: how many documents it shows. Empty until
  /// the list is first made — "0 Documents" would be a claim about the library, not a
  /// list that has not arrived yet.
  func listSubtitle(for scene: NavigationModel) -> String {
    scene.listed.map { DocumentCount.label($0.rows.count) } ?? ""
  }

  /// `IndexRepository.suggestions(for:limit:)`.
  func suggestions(for query: String, limit: Int) async -> [DocumentID] {
    await indexes.suggestions(for: query, limit: limit)
  }

  /// `IndexRepository.quickOpenHits(for:)`.
  func quickOpenHits(for query: String) async -> [DocumentID]? {
    await indexes.quickOpenHits(for: query)
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
  private func deliverLinksHeldForIndex() {
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
    route(.rfc(link))
  }

  /// `route(_:)` for a link to an RFC or a draft (#728).
  func route(_ link: ReadableLink) {
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
    if let id = delivery.link.document.rfc, inspectorRequest?.id == id {
      inspectorRequestScene = delivery.scene
    }
    if delivery.bringsForward {
      deliver(delivery.link, to: delivery.scene)
    } else {
      delivery.scene.open(delivery.link)
    }
  }

  /// Opens `link` in `scene` and makes that the tab in use.
  private func deliver(_ link: ReadableLink, to scene: NavigationModel) {
    scene.open(link)
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
    private func openInNewWindow(_ link: ReadableLink) {
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
    open(.rfc(link), activation: activation, in: scene, arrival: arrival)
  }

  /// The same for a link to an RFC or a draft (#728).
  func open(
    _ link: ReadableLink, activation: LinkActivation, in scene: NavigationModel,
    arrival: HistoryEntry.Arrival = .root
  ) {
    switch activation {
    case .here:
      scene.open(link, arrival: arrival)
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
  private func openInNewScene(_ link: ReadableLink, inBackground: Bool) {
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
      openWindow(for: RFCLink(id: id))
    }

    /// Opens `link` in a window of its own, at the place it names: a reference's
    /// long-press menu (#763).
    func openWindow(for link: RFCLink) {
      openInNewScene(.rfc(link), inBackground: false)
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
      open(.rfc(link), placement: placement)
    }

    /// The same for a link to an RFC or a draft (#728).
    func open(_ link: ReadableLink, placement: Placement) {
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

    /// Opens `link` in a new tab of the window showing `scene`, from a menu in it
    /// (#761): a right click does not make a background window key, and a new tab
    /// joins the key window's group.
    func openTab(_ link: RFCLink, beside scene: NavigationModel) {
      windows?.bringForward(scene)
      openInNewScene(.rfc(link), inBackground: false)
    }
  #endif

  // MARK: - Documents

  /// `DocumentRepository.document(for:)`. A series is read as its first member, the
  /// RFC its reader shows (#656).
  func document(for id: DocumentID) async throws -> RFCDocument {
    try await documents.document(for: .rfc(documentShown(for: id) ?? id))
  }

  /// An RFC as `document(for:)` reads it, or a draft's revision (#728).
  func document(for document: ReadableDocument) async throws -> RFCDocument {
    switch document {
    case .rfc(let id): try await self.document(for: id)
    case .draft: try await documents.document(for: document)
    }
  }

  /// `DocumentRepository.draftInfo(for:)`.
  func draftInfo(for id: DraftID) async throws -> DraftInfo {
    try await documents.draftInfo(for: id)
  }

  /// `DocumentRepository.revision(of:)`.
  func revision(of id: DraftID) async -> DraftID {
    await documents.revision(of: id)
  }

  /// `DocumentRepository.markOpened(_:)`.
  func markOpened(_ id: DocumentID) async {
    await documents.markOpened(id)
  }

  /// `IndexRepository.installLegacyPack(from:)`.
  func installLegacyPack(from source: URL) async throws -> InstalledPack {
    let pack = try await indexes.installLegacyPack(from: source)
    // The RFCs read from the pack now are indexed again with its anchors, under the
    // dates their bodies had: only a rebuild takes Spotlight's sections to them.
    indexSectionsForSpotlight(rebuilding: true)
    return pack
  }

  /// `DocumentRepository.publishedFile(for:format:)`.
  func publishedFile(for id: DocumentID, format: FileFormat) async throws -> Data {
    try await documents.publishedFile(for: id, format: format)
  }

  /// `DocumentRepository.originalText(for:)`.
  func originalText(for id: DocumentID) async throws -> String {
    try await documents.originalText(for: .rfc(id))
  }

  /// `DocumentRepository.originalText(for:)`.
  func originalText(for document: ReadableDocument) async throws -> String {
    try await documents.originalText(for: document)
  }

  // MARK: - Storage (#358)

  /// `DocumentRepository.storageUsage()`.
  func storageUsage() async -> StorageReport {
    await documents.storageUsage()
  }

  /// `DocumentRepository.clearCache()`.
  func clearCache() async {
    await documents.clearCache()
  }

  /// `DocumentRepository.removeAllOffline()`.
  func removeAllOffline() {
    documents.removeAllOffline()
  }

  /// `DocumentRepository.isDownloaded(_:)`.
  func isDownloaded(_ id: DocumentID) async -> Bool {
    await documents.isDownloaded(id)
  }

  /// `DocumentRepository.keptSize(_:)`.
  func keptSize(_ id: DocumentID) async -> Int? {
    await documents.keptSize(id)
  }

  /// `UserDataMirror.recentlyRead`.
  func recentlyRead() -> [DocumentID] {
    userData.recentlyRead()
  }

  /// `UserDataMirror.recordOpening`.
  func recordOpening(_ document: ReadableDocument) throws {
    try userData.recordOpening(document)
  }

  /// `UserDataMirror.saveReadingPlace`.
  func saveReadingPlace(_ place: ReadingPlace, for document: ReadableDocument) throws {
    try userData.saveReadingPlace(place, for: document)
  }

  /// `UserDataMirror.readingPosition`.
  func readingPosition(for document: ReadableDocument) throws -> ReadingPosition? {
    try userData.readingPosition(for: document)
  }

  // MARK: - Reading paths (#189)

  /// `DocumentRepository.readingPath(from:depth:)`.
  func readingPath(from root: DocumentID, depth: Int) async
    -> DocumentRepository.ReadingPathResult
  {
    await documents.readingPath(from: root, depth: depth)
  }

  /// `DocumentRepository.setKeptOffline`.
  func setKeptOffline(_ id: DocumentID, _ isKept: Bool) async throws {
    try await documents.setKeptOffline(id, isKept)
  }

  /// `DocumentRepository.setKeptOfflineInBackground`.
  func setKeptOfflineInBackground(_ id: DocumentID, _ isKept: Bool) {
    documents.setKeptOfflineInBackground(id, isKept)
  }

  #if os(macOS)
    /// A format of a document saved to Downloads, as Safari saves a file: under its
    /// own name, or numbered when that is taken, and the Dock's Downloads stack told,
    /// so it bounces. What Option-clicking a format in the Info pane does (#25).
    func saveToDownloads(_ id: DocumentID, format: FileFormat) async throws {
      let data = try await publishedFile(for: id, format: format)
      let name = RFCEditorEndpoints.document(id, format: format).lastPathComponent
      let file = try await Self.writeToDownloads(data, named: name)
      // Not private API, but not documented either: the notification Safari posts,
      // which the Dock answers today. If a macOS stops answering it, the stack stops
      // bouncing and nothing says so; the file is saved all the same (#762).
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

/// What a list counted in the sidebar lists from: the library's inputs as they
/// stand, where a tab's are the ones it took on entering its filter.
private struct LibrarySources: ListSources {
  let library: LibraryModel

  var bookmarked: Set<DocumentID> { library.bookmarkedDocuments }
  var recentlyRead: [DocumentID] { library.recentlyRead() }
  var downloaded: Set<Int> { library.availableOfflineNumbers }

  func members(of collection: UUID) -> [Int] {
    library.collections[collection]?.rfcNumbers ?? []
  }

  func collection(named name: String) -> UUID? {
    library.collections.collection(named: name)?.id
  }

  func query(of collection: UUID) -> String? {
    library.collections[collection]?.query
  }
}
