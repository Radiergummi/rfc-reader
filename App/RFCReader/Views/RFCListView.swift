import RFCKit
import RFCReaderKit
import SwiftUI

struct RFCListView: View {
  @Environment(LibraryModel.self) private var library
  @Environment(NavigationModel.self) private var navigation
  /// How many rows are handed to the `List`. See `ListWindow`: all 9,842 of them at
  /// once is one large diff on the main thread, and AppKit then scans every row to
  /// build its type-ahead strings — measurably, until it gives up and says so.
  @State private var limit = ListWindow.page

  private var rfcs: [RFCMetadata] {
    library.list(for: navigation)
  }

  var body: some View {
    @Bindable var navigation = navigation
    // Once, and shared by every row: `RFCRow` used to scan the whole bookmark list
    // itself, which is a linear search per row over a list that can be 9,842 rows
    // long.
    let bookmarked = library.bookmarkedNumbers
    // Once, and shared by everything below: `rfcs` was read twice per body pass —
    // here and in the overlay — which is half of why the memoised list was worth
    // memoising.
    let rows = rfcs
    let trigger = ListWindow.triggerRow(limit: limit, total: rows.count).map { rows[$0].id }
    // Selecting a row is a navigation: the setter goes through the history. Not
    // `library.open(_:activation:in:)` like every other open: a selection binding
    // is handed the outcome, not the click, and Command-click on a list row is the
    // platform's multi-select chord rather than ours to take.
    List(selection: $navigation.selection) {
      ForEach(rows.prefix(limit)) { rfc in
        RFCRow(rfc: rfc, isBookmarked: bookmarked.contains(rfc.number))
          .tag(rfc.id)
          .onAppear {
            guard rfc.id == trigger else { return }
            limit = ListWindow.extendedLimit(from: limit, total: rows.count)
          }
      }
      // Where Mail says when it last checked: after the last row, scrolled to
      // rather than pinned. Only once every row is in the window — after a
      // partial page it would read as the end of a list that goes on — and not
      // under an empty search, where the overlay already says what there is to
      // say.
      if limit >= rows.count, !(rows.isEmpty && library.indexState.isReady) {
        IndexStatusView()
          .frame(maxWidth: .infinity)
          .padding(.vertical, 8)
          .listRowSeparator(.hidden)
          .selectionDisabled()
      }
    }
    // Inset rather than plain: the selection is a rounded capsule with a margin
    // either side, the way every other macOS content list draws one. Plain fills
    // the row edge to edge and squares it off.
    .listStyle(.inset)
    .overlay {
      if rows.isEmpty, library.indexState.isReady {
        ContentUnavailableView.search(text: navigation.searchText)
      }
    }
    .onChange(of: navigation.filter, initial: true) {
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
    #if !os(macOS)
      .navigationTitle(navigation.filter.title)
      .navigationSubtitle(library.listSubtitle(for: navigation))
    #endif
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

/// Where the index stands: loading, when it was last updated, or why it failed
/// and a way to try again — the last of which is the only place a failed refresh
/// is reported at all.
struct IndexStatusView: View {
  @Environment(LibraryModel.self) private var library

  var body: some View {
    HStack(spacing: 6) {
      switch library.indexState {
      case .idle, .loading:
        ProgressView().controlSize(.mini)
        Text("Loading index…")
      case .ready(let updatedAt):
        Text("Updated \(updatedAt, format: .relative(presentation: .named))")
      case .failed(let message):
        Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)
        Text(message).lineLimit(2)
        Button("Retry") { Task { await library.refreshIndex() } }.buttonStyle(.borderless)
      }
    }
    .font(.caption)
    .foregroundStyle(.secondary)
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
    // One element, not five: VoiceOver read the number, the year, the title, the
    // status and the group as separate stops per row (#156).
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(rfc.accessibilityLabel(isBookmarked: isBookmarked))
  }
}
