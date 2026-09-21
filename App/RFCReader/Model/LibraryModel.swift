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

    var filter: LibraryFilter = .all
    var searchText = ""
    var selection: DocumentID?
    /// A section to scroll to once the selected document has loaded.
    var pendingSection: String?
    var isShowingGoToSheet = false

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
        listCache = nil
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

    /// Everything the list is a function of. `list` is read from `RFCListView.body`,
    /// which SwiftUI evaluates far more often than any of this changes -- twice per
    /// pass, several passes per click -- so the answer is remembered against its
    /// inputs. Without it a single filter change ran the full-text scan a dozen times.
    private struct ListKey: Equatable {
        let filter: LibraryFilter
        let query: String
        let bookmarked: Set<Int>
        let recentlyRead: [Int]
        let downloaded: Set<Int>
    }

    private var listCache: (key: ListKey, value: [RFCMetadata])?

    func list(bookmarked: Set<Int>, recentlyRead: [Int], downloaded: Set<Int>) -> [RFCMetadata] {
        let key = ListKey(
            filter: filter,
            query: searchText.trimmingCharacters(in: .whitespaces),
            bookmarked: bookmarked,
            recentlyRead: recentlyRead,
            downloaded: downloaded
        )
        if let listCache, listCache.key == key {
            return listCache.value
        }
        let computed = computeList(key)
        listCache = (key, computed)
        return computed
    }

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

    // MARK: - Navigation

    func open(_ link: RFCLink) {
        var id = link.id
        // BCP/STD links open their first member RFC.
        if id.series != .rfc, let first = index?.series(id)?.members.first {
            id = first
        }
        pendingSection = link.section
        selection = id
        filter = .all
    }

    func open(_ id: DocumentID, section: String? = nil) {
        open(RFCLink(id: id, section: section))
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
