import Foundation
import Observation
import RFCKit
import RFCReaderKit
import SwiftData
import os

private let libraryLog = Logger(
  subsystem: Bundle.main.bundleIdentifier ?? "me.mazetti.rfc-reader", category: "library")

#if os(macOS)
  import AppKit
#endif

/// Application state: the index, navigation, and the document cache.
///
/// One observable object keeps the SwiftUI surface small; SwiftData holds the
/// user's own data (bookmarks, reading positions) separately.
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

  /// Every bookmarked document, fetched again on every save of the store: one set
  /// for the toolbars and scripts alike, which ask about the document on screen, so
  /// BCP 14 is not answered for by RFC 14 (#152).
  private(set) var bookmarkedDocuments: Set<DocumentID> = []

  /// The bookmarked RFCs' numbers, for the lists, which list RFCs. Kept beside
  /// `bookmarkedDocuments` rather than derived from it: every list body reads it.
  private(set) var bookmarkedNumbers: Set<Int> = []
  @ObservationIgnored private var storeSaves: (any NSObjectProtocol)?

  /// Every RFC with a cached body: the Available Offline list. Kept here, and
  /// refreshed whenever the cache can have changed, so a tab can take it the moment
  /// it enters that filter rather than waiting on the store's actor.
  private(set) var downloadedNumbers: Set<Int> = []

  private init() {
    refreshBookmarks()
    storeSaves = NotificationCenter.default.addObserver(
      forName: ModelContext.didSave, object: nil, queue: .main
    ) { [weak self] _ in
      MainActor.assumeIsolated { self?.refreshBookmarks() }
    }
  }

  private func refreshBookmarks() {
    let documents = BookmarkStore.bookmarkedDocuments(in: AppData.container.mainContext)
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
  private let store = DocumentStore()
  private var search: IndexSearch?

  // MARK: - Bootstrap

  func bootstrap() async {
    guard indexState == .idle else { return }
    indexState = .loading
    await refreshDownloadedNumbers()
    do {
      if let cached = try await store.cachedIndex() {
        // The store parses the cached index on its own actor; the search and the
        // working groups are built off the main actor as well.
        let index = cached.index
        let prepared = await Self.prepare(index)
        apply(prepared, updatedAt: cached.updatedAt)
        // Refresh in the background if the cache is older than a day.
        if cached.updatedAt.timeIntervalSinceNow < -86_400 {
          Task(name: "Refresh index") { await refreshIndex() }
        }
      } else {
        await refreshIndex()
      }
    } catch {
      indexState = .failed(error.localizedDescription)
    }
    // Just Published is decoration: a failure leaves it empty, and is logged
    // rather than shown (#125).
    Task(name: "Fetch recent RFCs") {
      do {
        recent = try await client.fetchRecent()
      } catch {
        libraryLog.error(
          "fetching recent RFCs failed: \(String(describing: error), privacy: .public)")
      }
    }
  }

  /// The search and the working groups, built off the main actor.
  @concurrent
  private static func prepare(_ index: RFCIndex) async -> PreparedIndex {
    PreparedIndex(index: index)
  }

  @concurrent
  private static func parse(_ data: Data) async throws -> PreparedIndex {
    try PreparedIndex.parse(data)
  }

  func refreshIndex() async {
    do {
      let data = try await client.fetchIndexData()
      // Off the main actor: the parse alone is about a second (#124).
      let prepared = try await Self.parse(data)
      try await store.storeIndex(data)
      apply(prepared, updatedAt: .now)
    } catch {
      if index == nil { indexState = .failed(error.localizedDescription) }
    }
  }

  /// Only assigns: everything in `prepared` was built off the main actor.
  private func apply(_ prepared: PreparedIndex, updatedAt: Date) {
    self.index = prepared.index
    self.search = prepared.search
    self.topWorkingGroups = prepared.topWorkingGroups
    listCache.removeAll()
    indexState = .ready(updatedAt: updatedAt)
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

  /// Everything the list is a function of.
  ///
  /// The filter and the query are passed in rather than read off `self`: they belong
  /// to one tab (`NavigationModel`), and two tabs may be listing different things at
  /// the same time. Gathering them into one value also gives the cache its key.
  private struct ListKey: Hashable {
    let filter: LibraryFilter
    let query: String
    let bookmarked: Set<Int>
    let recentlyRead: [Int]
    let downloaded: Set<Int>
  }

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
  /// and the hit rate collapses to zero. Capped, and cleared wholesale when it fills
  /// -- this is a cache, so losing an entry costs time, never correctness.
  ///
  /// Not observed: `list` writes it from a view's body on a miss, and a write to
  /// a property the running body read invalidated that body, so every miss rendered
  /// the list twice (#126). It is a memo of state that is observed, not state itself.
  /// That makes a hit read nothing observable, though, so `list` reads `index`
  /// before looking here: the key carries every other input, and those the caller
  /// reads for itself.
  @ObservationIgnored private var listCache: [ListKey: [RFCMetadata]] = [:]
  private static let listCacheLimit = 8

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
    let key = ListKey(
      filter: filter,
      query: scene.searchText.trimmingCharacters(in: .whitespaces),
      bookmarked: filter == .bookmarks ? bookmarkedNumbers : [],
      recentlyRead: filter == .recent ? scene.recentOrder : [],
      downloaded: filter == .downloaded ? scene.downloaded : []
    )
    if let hit = listCache[key] { return hit }
    let computed = computeList(key, in: index)
    if listCache.count >= Self.listCacheLimit { listCache.removeAll(keepingCapacity: true) }
    listCache[key] = computed
    return computed
  }

  /// The subtitle under the list's title: how many documents it shows. Empty while
  /// the index loads — "0 Documents" would be a claim about the library, not about a
  /// list that has not arrived yet.
  func listSubtitle(for scene: NavigationModel) -> String {
    indexState.isReady ? DocumentCount.label(list(for: scene).count) : ""
  }

  /// Reads every input off the key, so the cache cannot go stale against something
  /// this consults but the key does not carry. The one input not in the key is
  /// `index` (and `search`, which `apply` replaces with it), which is why `apply`
  /// empties the cache: that keeps the cache correct, and the read of `index` at the
  /// top of `list` is what gets the view to ask again. The index is handed in from
  /// that read rather than read again here, so the observed read is the only one.
  private func computeList(_ key: ListKey, in index: RFCIndex) -> [RFCMetadata] {
    let filter = key.filter
    let base: [RFCMetadata]
    switch filter {
    case .all: base = index.rfcs.reversed()
    case .recent: base = key.recentlyRead.compactMap { index[$0] }
    case .bookmarks: base = key.bookmarked.sorted(by: >).compactMap { index[$0] }
    case .downloaded: base = key.downloaded.sorted(by: >).compactMap { index[$0] }
    case .standards: base = index.rfcs.reversed().filter { $0.currentStatus == .internetStandard }
    case .bestCurrentPractice:
      base = index.rfcs.reversed().filter { $0.currentStatus == .bestCurrentPractice }
    case .stream(let stream): base = index.rfcs.reversed().filter { $0.stream == stream }
    case .workingGroup(let group): base = index.rfcs.reversed().filter { $0.workingGroup == group }
    case .series(let id): base = index.series(id)?.members.compactMap { index[$0] } ?? []
    }

    guard !key.query.isEmpty, let search else { return base }
    // Every hit, not the top few hundred: the search scores and sorts all of them
    // anyway, the list windows its rows itself (`ListWindow`), and the count over
    // the list says how many there are. A cap also cut before the filter below,
    // so a search inside a collection lost whatever ranked outside the cap overall.
    let hits = search.search(key.query, limit: .max)
    // Everything is allowed in the whole library, so there is nothing to filter.
    if case .all = filter { return hits.map(\.rfc) }
    let allowed = Set(base.map(\.number))
    return hits.compactMap { allowed.contains($0.rfc.number) ? $0.rfc : nil }
  }

  /// The Go to RFC palette's candidates for what was typed, best first.
  ///
  /// Off the main actor: a short query like `http` scans every title and abstract,
  /// measured at 107 ms (#22), and this runs as the reader types.
  func suggestions(for query: String, limit: Int) async -> [DocumentID] {
    guard let search else { return [] }
    return await Self.suggestions(in: search, for: query, limit: limit)
  }

  @concurrent
  private static func suggestions(
    in search: IndexSearch, for query: String, limit: Int
  ) async -> [DocumentID] {
    search.search(query, limit: limit).map(\.id)
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

  /// Marks a scene as the one the reader is using, which is where an untargeted
  /// link lands.
  func activate(_ scene: NavigationModel) {
    guard scenes.first?.model !== scene else { return }
    promote(scene)
  }

  private func promote(_ scene: NavigationModel) {
    unregister(scene)
    scenes.insert(WeakScene(model: scene), at: 0)
  }

  /// Sends `link` to exactly one scene: the tab already showing that document if
  /// there is one, otherwise the most recently used tab.
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
    let target = scenes.first { $0.model?.selection == link.id }?.model ?? scenes.first?.model
    guard let target else {
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
      AppDelegate.shared?.bringForward(scene)
    #endif
  }

  /// Opens a window for `link`, which it takes in `register(_:)`.
  private func openInNewWindow(_ link: RFCLink) {
    pendingSceneLink = link
    #if os(macOS)
      AppDelegate.shared?.openWindow(tabbedWith: nil, inBackground: false)
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
  /// Through AppKit, because on macOS the app makes its own windows: there is no
  /// `WindowGroup` to ask, and `newWindowForTab:` is answered by our own window
  /// controller rather than by SwiftUI.
  ///
  /// Nothing can be passed to a window as it is made, so the link waits in
  /// `pendingSceneLink` for the window that appears to take it in `register(_:)`.
  private func openInNewScene(_ link: RFCLink, inBackground: Bool) {
    #if os(macOS)
      pendingSceneLink = link
      AppDelegate.shared?.openTab(inBackground: inBackground)
    #endif
  }

  #if os(macOS)
    /// Where a document asked for by name opens.
    enum Placement {
      case frontTab
      case newTab
      case newWindow
    }

    /// Opens `link` where `placement` says.
    ///
    /// The front tab is the one the menu acts on (`AppDelegate.activeController`),
    /// not whichever tab `route(_:)` would pick: a script that says "open this"
    /// means the window it is looking at. With no window open there is no front
    /// tab, and the link is routed the way one from outside is, which opens one.
    func open(_ link: RFCLink, placement: Placement) {
      switch placement {
      case .frontTab:
        if let scene = AppDelegate.shared?.activeController?.navigation {
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
    await store.evict(pinned: pinnedDocuments(), bound: CacheEviction.defaultBound)
  }

  /// What eviction never removes (#39): bookmarks, a bookmark being a promise to
  /// keep the document offline; what was read in the last month; and whatever a
  /// window has open, which includes the document just fetched.
  private func pinnedDocuments() -> Set<DocumentID> {
    let context = AppData.container.mainContext
    let monthAgo = Date.now.addingTimeInterval(-30 * 86_400)
    let recent = FetchDescriptor<ReadingPosition>(predicate: #Predicate { $0.updatedAt > monthAgo })
    let read = ((try? context.fetch(recent)) ?? []).compactMap(\.document)
    let bookmarked = BookmarkStore.bookmarkedDocuments(in: context)
    let open = scenes.compactMap { $0.model?.selection }
    return bookmarked.union(read).union(open)
  }

  func isDownloaded(_ id: DocumentID) async -> Bool {
    await store.isCached(id)
  }

  /// The documents the reader has opened, most recent first.
  ///
  /// Fetched on demand rather than observed, and that is the point: the Recently
  /// read list is history as of the moment the filter is entered, and a live query
  /// re-sorted it under the click that was reading it. `NavigationModel` takes one
  /// of these when its filter changes, exactly as it takes `downloadedNumbers`.
  func recentlyReadNumbers() -> [Int] {
    let descriptor = FetchDescriptor<ReadingPosition>(
      sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
    )
    let positions = (try? AppData.container.mainContext.fetch(descriptor)) ?? []
    return positions.compactMap(\.document).filter { $0.series == .rfc }.map(\.number)
  }

  func download(_ id: DocumentID) async throws {
    _ = try await document(for: id)
  }

  func removeDownload(_ id: DocumentID) async {
    await store.remove(id)
    await refreshDownloadedNumbers()
  }
}
