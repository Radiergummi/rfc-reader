import RFCKit
import RFCReaderKit
import SwiftData
import SwiftUI

struct RFCListView: View {
  @Environment(LibraryModel.self) private var library
  @Environment(NavigationModel.self) private var navigation
  @Query(sort: \Bookmark.createdAt, order: .reverse) private var bookmarks: [Bookmark]
  @State private var downloaded: Set<Int> = []
  /// The Recently read order, taken once when the filter is entered.
  ///
  /// Not a live `@Query`: opening or leaving a document writes its `updatedAt`, so
  /// a query sorted on that re-sorted the list the click came from — the row just
  /// left jumped to the top and everything below it shifted down a place. Held
  /// here instead, the order is whatever it was on arrival and stays put while it
  /// is being read through; coming back to the filter takes a fresh one, the same
  /// way `downloaded` beside it does.
  @State private var recentOrder: [Int] = []
  /// How many rows are handed to the `List`. See `ListWindow`: all 9,842 of them at
  /// once is one large diff on the main thread, and AppKit then scans every row to
  /// build its type-ahead strings — measurably, until it gives up and says so.
  @State private var limit = ListWindow.page

  /// Built once per body pass and shared by every row: `RFCRow` used to scan the
  /// whole bookmark list itself, which is a linear search per row over a list that
  /// can be 9,842 rows long.
  private var bookmarkedNumbers: Set<Int> {
    Set(bookmarks.map(\.number))
  }

  private var rfcs: [RFCMetadata] {
    library.list(
      filter: navigation.filter,
      searchText: navigation.searchText,
      bookmarked: bookmarkedNumbers,
      recentlyRead: recentOrder,
      downloaded: downloaded
    )
  }

  /// Selecting a row is a navigation, so it goes through the history rather than
  /// assigning the selection behind its back.
  private var selectionBinding: Binding<DocumentID?> {
    Binding(
      get: { navigation.selection },
      // Not `library.open(_:activation:in:)` like every other open: a selection
      // binding is handed the outcome, not the click, and Command-click on a
      // list row is the platform's multi-select chord rather than ours to take.
      set: { if let id = $0 { navigation.select(id) } }
    )
  }

  var body: some View {
    @Bindable var navigation = navigation
    let bookmarked = bookmarkedNumbers
    // Once, and shared by everything below: `rfcs` was read twice per body pass —
    // here and in the overlay — which is half of why the memoised list was worth
    // memoising.
    let rows = rfcs
    let trigger = ListWindow.triggerRow(limit: limit, total: rows.count).map { rows[$0].id }
    List(selection: selectionBinding) {
      ForEach(rows.prefix(limit)) { rfc in
        RFCRow(rfc: rfc, isBookmarked: bookmarked.contains(rfc.number))
          .tag(rfc.id)
          .onAppear {
            guard rfc.id == trigger else { return }
            limit = ListWindow.extendedLimit(from: limit, total: rows.count)
          }
      }
    }
    // Inset rather than plain: the selection is a rounded capsule with a margin
    // either side, the way every other macOS content list draws one. Plain fills
    // the row edge to edge and squares it off.
    .listStyle(.inset)
    .overlay {
      if rows.isEmpty, case .ready = library.indexState {
        ContentUnavailableView.search(text: navigation.searchText)
      }
    }
    .task(id: navigation.filter) {
      recentOrder = library.recentlyReadNumbers()
      downloaded = await library.downloadedNumbers()
      // After the two above, not before: both are inputs to the list the window
      // is being measured against.
      limit = ListWindow.initialLimit(covering: selectedRow())
    }
    .onChange(of: navigation.searchText) {
      limit = ListWindow.initialLimit(covering: selectedRow())
    }
    // Only ever wider. A selection arriving from outside the list — a deep link, a
    // citation, the Go to RFC palette — may sit far below the first page, and
    // `NavigationModel.open` resets the filter to `.all` precisely so nothing
    // hides it. Narrowing here instead would throw away a window the reader has
    // already scrolled down through.
    .onChange(of: navigation.selection) {
      limit = max(limit, ListWindow.initialLimit(covering: selectedRow()))
    }
  }

  /// Where the selected document sits in the list, if it is in it at all.
  ///
  /// A linear scan, but only on the three changes above rather than per body pass,
  /// and it compares two `Int`s per row.
  private func selectedRow() -> Int? {
    guard let selection = navigation.selection else { return nil }
    return rfcs.firstIndex { $0.id == selection }
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
