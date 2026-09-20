import RFCKit
import SwiftData
import SwiftUI

struct RFCListView: View {
    @Environment(LibraryModel.self) private var library
    @Query(sort: \Bookmark.createdAt, order: .reverse) private var bookmarks: [Bookmark]
    @Query(sort: \ReadingPosition.updatedAt, order: .reverse) private var positions: [ReadingPosition]
    @State private var downloaded: Set<Int> = []

    private var rfcs: [RFCMetadata] {
        library.list(
            bookmarked: Set(bookmarks.map(\.number)),
            recentlyRead: positions.map(\.number),
            downloaded: downloaded
        )
    }

    var body: some View {
        @Bindable var library = library
        List(selection: $library.selection) {
            ForEach(rfcs) { rfc in
                RFCRow(rfc: rfc, isBookmarked: bookmarks.contains { $0.number == rfc.number })
                    .tag(rfc.id)
            }
        }
        .listStyle(.plain)
        .overlay {
            if rfcs.isEmpty, case .ready = library.indexState {
                ContentUnavailableView.search(text: library.searchText)
            }
        }
        .searchable(text: $library.searchText, prompt: "Number, title, keyword, wg:, author:, year:")
        .navigationTitle(library.filter.title)
        .task(id: library.filter) {
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
