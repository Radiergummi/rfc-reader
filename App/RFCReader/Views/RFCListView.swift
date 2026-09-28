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
    let window = rows.prefix(limit)
    let row = { (rfc: RFCMetadata, showsYear: Bool) in
      RFCRow(rfc: rfc, isBookmarked: bookmarked.contains(rfc.number), showsYear: showsYear)
        .tag(rfc.id)
        #if !os(macOS)
          .modifier(RowActions(rfc: rfc, isBookmarked: bookmarked.contains(rfc.number)))
        #endif
        .onAppear {
          guard rfc.id == trigger else { return }
          limit = ListWindow.extendedLimit(from: limit, total: rows.count)
        }
    }
    List(selection: $navigation.selection) {
      #if os(macOS)
        ForEach(window) { row($0, true) }
      #else
        // By year where the list is in order of publication, as Notes sections
        // its lists by date (#347). Over the window only: a later page's row may
        // join a year already on screen, which is above the reader by then.
        if YearSections.apply(to: navigation.filter, query: navigation.searchText) {
          ForEach(YearSections.sections(of: window)) { section in
            Section(String(section.year)) {
              ForEach(section.rfcs) { row($0, false) }
            }
            .sectionIndexLabel(String(section.year))
          }
        } else {
          ForEach(window) { row($0, true) }
        }
      #endif
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
    #if os(macOS)
      .listStyle(.inset)
    #else
      // On iOS, cards with a margin round them, as Notes' lists are (#346).
      .listStyle(.insetGrouped)
      .headerProminence(.increased)
      .listSectionIndexVisibility(.visible)
    #endif
    .overlay {
      if rows.isEmpty, library.indexState.isReady {
        ContentUnavailableView.search(text: navigation.searchText)
      }
    }
    .onChange(of: navigation.filter, initial: true) {
      limit = ListWindow.initialLimit(covering: selectedRow())
    }
    .onChange(of: navigation.listOptions) {
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
      // Narrows what this list shows, as Notes' field does inside a folder (#345).
      .searchable(text: $navigation.searchText, prompt: "Search \(navigation.filter.title)")
      .toolbar {
        LibraryBottomBar(navigation: navigation)
        ToolbarItem(placement: .primaryAction) { optionsMenu }
      }
      // The index could be refreshed only from the status line at the list's very
      // end (#348).
      .refreshable { await library.refreshIndex() }
    #endif
  }

  #if !os(macOS)
    /// How the list is shown, for this tab (#348).
    private var optionsMenu: some View {
      @Bindable var navigation = navigation
      return Menu {
        if ListOptions.canReorder(navigation.filter, query: navigation.searchText) {
          Picker("Sort", selection: $navigation.listOptions.order) {
            ForEach(ListOptions.Order.allCases, id: \.self) { order in
              Text(order.title)
            }
          }
        }
        Toggle("Show Obsolete", isOn: $navigation.listOptions.showsObsolete)
      } label: {
        Label("View Options", systemImage: "ellipsis")
      }
    }
  #endif

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
        Button("Retry") { Task(name: "Refresh index") { await library.refreshIndex() } }
          .buttonStyle(.borderless)
      }
    }
    .font(.caption)
    .foregroundStyle(.secondary)
  }
}

struct RFCRow: View {
  let rfc: RFCMetadata
  let isBookmarked: Bool
  /// False under a year's header, which already says it (#347).
  var showsYear = true

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      // On iOS the title leads, in bold, and what identifies it follows, as a
      // note's title leads its row in Notes (#346).
      #if os(macOS)
        designation
        title
      #else
        title.font(.headline)
        designation
      #endif
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

  private var designation: some View {
    HStack(alignment: .firstTextBaseline) {
      Text(rfc.id.displayName)
        .font(.subheadline.monospacedDigit())
        .foregroundStyle(.secondary)
      Spacer()
      if isBookmarked {
        Image(systemName: "bookmark.fill").font(.caption2).foregroundStyle(.tint)
      }
      if showsYear {
        Text(String(rfc.date.year)).font(.caption).foregroundStyle(.tertiary)
      }
    }
  }

  private var title: some View {
    Text(rfc.title)
      .lineLimit(2)
      .strikethrough(rfc.isObsolete, color: .secondary)
      // Typeset as the English it is. Under a German system language, iOS
      // hyphenated titles mid-word, as in "Key Exch-ange" (#346).
      .typesettingLanguage(.init(identifier: "en"))
  }
}

#if !os(macOS)
  /// What a list row offers beyond a tap (#348): a leading swipe to bookmark it, and
  /// a context menu previewing its abstract, as Notes previews a note.
  private struct RowActions: ViewModifier {
    let rfc: RFCMetadata
    let isBookmarked: Bool
    @Environment(\.modelContext) private var modelContext

    func body(content: Content) -> some View {
      content
        .swipeActions(edge: .leading) {
          Button(action: toggleBookmark) {
            Label(
              isBookmarked ? "Remove Bookmark" : "Bookmark",
              systemImage: isBookmarked ? "bookmark.slash" : "bookmark")
          }
          .tint(.accentColor)
        }
        .contextMenu {
          Button(action: toggleBookmark) {
            Label(
              isBookmarked ? "Remove Bookmark" : "Bookmark",
              systemImage: isBookmarked ? "bookmark.fill" : "bookmark")
          }
          ShareLink(
            item: RFCEditorEndpoints.infoPage(rfc.id),
            subject: Text("\(rfc.id.displayName): \(rfc.title)"))
        } preview: {
          preview
        }
    }

    private var preview: some View {
      VStack(alignment: .leading, spacing: 8) {
        Text(rfc.id.displayName)
          .font(.subheadline.monospacedDigit())
          .foregroundStyle(.secondary)
        Text(rfc.title).font(.headline)
        if let abstract = rfc.abstract {
          Text(abstract)
            .font(.callout)
            .foregroundStyle(.secondary)
            .lineLimit(12)
        }
      }
      .typesettingLanguage(.init(identifier: "en"))
      .padding()
      .frame(width: 340, alignment: .leading)
    }

    private func toggleBookmark() {
      let title = DocumentActions.bookmarkTitle(metadata: rfc, documentTitle: nil, id: rfc.id)
      BookmarkStore.toggle(rfc.id, title: title, in: modelContext)
    }
  }
#endif
