import Foundation
import Observation
import RFCKit

/// What the list in the middle column shows.
enum LibraryFilter: Hashable, Identifiable {
    case all
    case recent
    case bookmarks
    case downloaded
    case standards
    case bestCurrentPractice
    case stream(RFCKit.Stream)
    case workingGroup(String)
    case series(DocumentID)

    var id: Self { self }

    var title: String {
        switch self {
        case .all: "All RFCs"
        case .recent: "Recently Read"
        case .bookmarks: "Bookmarks"
        case .downloaded: "Available Offline"
        case .standards: "Internet Standards"
        case .bestCurrentPractice: "Best Current Practices"
        case .stream(let stream): stream.displayName
        case .workingGroup(let group): group.uppercased()
        case .series(let id): id.displayName
        }
    }

    var systemImage: String {
        switch self {
        case .all: "books.vertical"
        case .recent: "clock"
        case .bookmarks: "bookmark"
        case .downloaded: "arrow.down.circle"
        case .standards: "checkmark.seal"
        case .bestCurrentPractice: "hand.thumbsup"
        case .stream: "tray"
        case .workingGroup: "person.2"
        case .series: "square.stack"
        }
    }
}

/// Application state: the index, navigation, and the document cache.
///
/// One observable object keeps the SwiftUI surface small; SwiftData holds the
/// user's own data (bookmarks, reading positions) separately.
@Observable
@MainActor
final class LibraryModel {
    /// One instance per process so App Intents and URL handlers reach the same state.
    static let shared = LibraryModel()

    enum IndexState: Equatable {
        case idle
        case loading
        case ready(count: Int, updatedAt: Date)
        case failed(String)
    }

    private(set) var index: RFCIndex?
    private(set) var indexState: IndexState = .idle
    private(set) var recent: [RecentRFC] = []

    private let client = RFCEditorClient()
    private let store = DocumentStore()
    private var search: IndexSearch?

    // MARK: - Bootstrap

    func bootstrap() async {
        guard indexState == .idle else { return }
        indexState = .loading
        do {
            if let cached = try await store.cachedIndex() {
                apply(cached.index, updatedAt: cached.updatedAt)
                // Refresh in the background if the cache is older than a day.
                if cached.updatedAt.timeIntervalSinceNow < -86_400 {
                    Task { await refreshIndex() }
                }
            } else {
                await refreshIndex()
            }
        } catch {
            indexState = .failed(error.localizedDescription)
        }
        Task { recent = (try? await client.fetchRecent()) ?? [] }
    }

    func refreshIndex() async {
        do {
            let data = try await client.fetchIndexData()
            let parsed = try RFCIndexParser.parse(data)
            try await store.storeIndex(data)
            apply(parsed, updatedAt: .now)
        } catch {
            if index == nil { indexState = .failed(error.localizedDescription) }
        }
    }

    private func apply(_ index: RFCIndex, updatedAt: Date) {
        self.index = index
        self.search = IndexSearch(index: index)
        self.topWorkingGroups = Self.workingGroups(in: index)
        listCache.removeAll()
        indexState = .ready(count: index.rfcs.count, updatedAt: updatedAt)
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
    private(set) var topWorkingGroups: [String] = []

    private static func workingGroups(in index: RFCIndex) -> [String] {
        var counts: [String: Int] = [:]
        for rfc in index.rfcs {
            if let group = rfc.workingGroup { counts[group, default: 0] += 1 }
        }
        return counts.sorted { $0.value > $1.value }.prefix(12).map(\.key)
    }

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
    /// `list` is read from `RFCListView.body`, which SwiftUI evaluates far more often
    /// than any of these inputs change -- twice per pass, several passes per click.
    /// Uncached, one filter change ran the full-text scan a dozen times over, and that
    /// scan measures 107 ms against the real index.
    ///
    /// A dictionary rather than a single slot because tabs have their own filters now:
    /// with one slot, two tabs listing different things evict each other on every pass
    /// and the hit rate collapses to zero. Capped, and cleared wholesale when it fills
    /// -- this is a cache, so losing an entry costs time, never correctness.
    private var listCache: [ListKey: [RFCMetadata]] = [:]
    private static let listCacheLimit = 8

    func list(
        filter: LibraryFilter,
        searchText: String,
        bookmarked: Set<Int>,
        recentlyRead: [Int],
        downloaded: Set<Int>
    ) -> [RFCMetadata] {
        let key = ListKey(
            filter: filter,
            query: searchText.trimmingCharacters(in: .whitespaces),
            bookmarked: bookmarked,
            recentlyRead: recentlyRead,
            downloaded: downloaded
        )
        if let hit = listCache[key] { return hit }
        let computed = computeList(key)
        if listCache.count >= Self.listCacheLimit { listCache.removeAll(keepingCapacity: true) }
        listCache[key] = computed
        return computed
    }

    /// Reads every input off the key, so the cache cannot go stale against something
    /// this consults but the key does not carry. The one input not in the key is
    /// `index`, which is why `apply` empties the cache.
    private func computeList(_ key: ListKey) -> [RFCMetadata] {
        let filter = key.filter
        guard let index else { return [] }
        let base: [RFCMetadata]
        switch filter {
        case .all: base = index.rfcs.reversed()
        case .recent: base = key.recentlyRead.compactMap { index[$0] }
        case .bookmarks: base = key.bookmarked.sorted(by: >).compactMap { index[$0] }
        case .downloaded: base = key.downloaded.sorted(by: >).compactMap { index[$0] }
        case .standards: base = index.rfcs.reversed().filter { $0.currentStatus == .internetStandard }
        case .bestCurrentPractice: base = index.rfcs.reversed().filter { $0.currentStatus == .bestCurrentPractice }
        case .stream(let stream): base = index.rfcs.reversed().filter { $0.stream == stream }
        case .workingGroup(let group): base = index.rfcs.reversed().filter { $0.workingGroup == group }
        case .series(let id): base = index.series(id)?.members.compactMap { index[$0] } ?? []
        }

        guard !key.query.isEmpty, let search else { return base }
        let allowed = Set(base.map(\.number))
        return search.search(key.query, limit: 500).map(\.rfc).filter { allowed.contains($0.number) }
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
        weak var model: NavigationModel?
    }

    /// Handed to the next scene that appears.
    ///
    /// A new window cannot be given its document directly — see the note on the
    /// window group — so a Cmd-click leaves the link here and opens a window, and the
    /// scene that appears takes it. Cleared on the way out so no later window picks
    /// up a stale one.
    private var pendingSceneLink: RFCLink?

    func handOver(_ link: RFCLink) {
        pendingSceneLink = link
    }

    func takePendingSceneLink() -> RFCLink? {
        defer { pendingSceneLink = nil }
        return pendingSceneLink
    }

    func register(_ scene: NavigationModel) {
        scenes.removeAll { $0.model == nil || $0.model === scene }
        scenes.insert(WeakScene(model: scene), at: 0)
    }

    func unregister(_ scene: NavigationModel) {
        scenes.removeAll { $0.model == nil || $0.model === scene }
    }

    /// Marks a scene as the one the reader is using, which is where an untargeted
    /// link lands.
    func activate(_ scene: NavigationModel) {
        guard scenes.first?.model !== scene else { return }
        register(scene)
    }

    /// Sends `link` to exactly one scene: the tab already showing that document if
    /// there is one, otherwise the most recently used tab.
    ///
    /// Focusing that tab's window when it is not the frontmost one needs its
    /// `NSWindow`, which SwiftUI does not hand out; the state is correct either way,
    /// and the window follows in a later change.
    func route(_ link: RFCLink) {
        scenes.removeAll { $0.model == nil }
        let target = scenes.first { $0.model?.selection == link.id }?.model ?? scenes.first?.model
        target?.open(link, in: index)
    }

    // MARK: - Documents

    func document(for id: DocumentID) async throws -> RFCDocument {
        try await store.document(id, formats: index?[id]?.formats ?? [], client: client)
    }

    func originalText(for id: DocumentID) async throws -> String {
        try await store.originalText(id, client: client)
    }

    func isDownloaded(_ id: DocumentID) async -> Bool {
        await store.isCached(id)
    }

    func downloadedNumbers() async -> Set<Int> {
        await store.cachedNumbers()
    }

    func download(_ id: DocumentID) async throws {
        _ = try await document(for: id)
    }

    func removeDownload(_ id: DocumentID) async {
        await store.remove(id)
    }
}

extension RFCEditorClient {
    /// The index as bytes, so the model can both parse and persist it.
    func fetchIndexData() async throws -> Data {
        let (data, response) = try await URLSession.shared.data(from: RFCEditorEndpoints.index)
        guard (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) ?? true else {
            throw ClientError.httpStatus((response as? HTTPURLResponse)?.statusCode ?? -1, RFCEditorEndpoints.index)
        }
        return data
    }
}
