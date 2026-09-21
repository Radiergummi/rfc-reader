import RFCKit
import SwiftData
import SwiftUI

struct RFCListView: View {
    @Environment(LibraryModel.self) private var library
    @Environment(NavigationModel.self) private var navigation
    @Query(sort: \Bookmark.createdAt, order: .reverse) private var bookmarks: [Bookmark]
    @Query(sort: \ReadingPosition.updatedAt, order: .reverse) private var positions: [ReadingPosition]
    @State private var downloaded: Set<Int> = []

    private var rfcs: [RFCMetadata] {
        library.list(
            filter: navigation.filter,
            searchText: navigation.searchText,
            bookmarked: Set(bookmarks.map(\.number)),
            recentlyRead: positions.map(\.number),
            downloaded: downloaded
        )
    }

    /// Selecting a row is a navigation, so it goes through the history rather than
    /// assigning the selection behind its back.
    private var selectionBinding: Binding<DocumentID?> {
        Binding(
            get: { navigation.selection },
            set: { if let id = $0 { navigation.open(id, in: library.index) } }
        )
    }

    var body: some View {
        @Bindable var navigation = navigation
        List(selection: selectionBinding) {
            ForEach(rfcs) { rfc in
                RFCRow(rfc: rfc, isBookmarked: bookmarks.contains { $0.number == rfc.number })
                    .tag(rfc.id)
            }
        }
        .listStyle(.plain)
        .overlay {
            if rfcs.isEmpty, case .ready = library.indexState {
                ContentUnavailableView.search(text: navigation.searchText)
            }
        }
        .searchable(text: $navigation.searchText, prompt: "Search")
        .navigationTitle(navigation.filter.title)
        .task(id: navigation.filter) {
            downloaded = await library.downloadedNumbers()
        }
    }
}

struct RFCRow: View {
    let rfc: RFCMetadata
    let isBookmarked: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(rfc.id.displayName)
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer()
                if isBookmarked {
                    Image(systemName: "bookmark.fill").font(.caption2).foregroundStyle(.tint)
                }
                Text(String(rfc.date.year)).font(.caption).foregroundStyle(.tertiary)
            }
            Text(rfc.title)
                .lineLimit(2)
                .strikethrough(rfc.isObsolete, color: .secondary)
            HStack(spacing: 6) {
                StatusBadge(status: rfc.currentStatus)
                if rfc.isObsolete {
                    Text("Obsolete").font(.caption2).foregroundStyle(.secondary)
                }
                if let group = rfc.workingGroup {
                    Text(group).font(.caption2).foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 2)
    }
}
