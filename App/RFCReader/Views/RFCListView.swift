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
  /// The collection the picker adds to, while it is on show (#349).
  @State private var addingTo: PickerTarget?
  #if !os(macOS)
    /// Whether the notices of the code the app adapts are on show.
    @State private var showsAcknowledgements = false
    @State private var showsSettings = false
  #endif

  private var rows: [LibraryRow] {
    navigation.listed?.rows ?? []
  }

  /// What the rows on show were made for. The tab's own filter, options and query
  /// change first and the rows follow (#597), so whatever is shaped by the rows —
  /// sections, moving, the card, the empty state — reads these, and the title and
  /// the controls read the tab's.
  private var shown: LibraryList {
    navigation.listed?.list
      ?? LibraryList(filter: navigation.filter, query: "", options: navigation.listOptions)
  }

  @Environment(\.undoManager) private var undoManager
  #if !os(macOS)
    @Environment(\.editMode) private var editMode
  #endif

  /// The collection the list shows, if it shows one.
  private var collection: UUID? {
    if case .collection(let identifier) = shown.filter { identifier } else { nil }
  }

  /// The working group whose card heads the list (#363): while its RFCs are listed
  /// unsearched.
  private var workingGroupCardAcronym: String? {
    guard case .workingGroup(let acronym) = shown.filter, shown.query.isUnsearchedQuery
    else { return nil }
    return acronym
  }

  /// A drag in the visible rows, resolved by their documents rather than their
  /// offsets: the rows on screen may hide obsolete documents or be only the first
  /// pages (`CollectionOrder.neighbors`).
  private func move(from source: IndexSet, to destination: Int, in visible: [LibraryRow]) {
    place(CollectionOrder.drop(from: source, to: destination, in: visible.map(\.id)))
  }

  private func place(_ drop: CollectionOrder.Drop<DocumentID>?) {
    guard let collection, let drop else { return }
    library.editCollections {
      try CollectionStore.move(
        drop.moved, in: collection, afterVisible: drop.above, beforeVisible: drop.below, in: $0)
    }
    navigation.listNow()
  }

  /// Out of the collection, undoably, back to the same place.
  private func remove(_ document: DocumentID) {
    guard let collection else { return }
    library.editCollections {
      try CollectionStore.remove(
        document, from: collection, undoManager: undoManager,
        onUndoFailure: library.collectionUndoFailed, in: $0)
    }
    navigation.listNow()
  }

  /// VoiceOver's Move Up and Move Down, one row at a time.
  private func step(_ row: LibraryRow, by offset: Int, in visible: [LibraryRow]) {
    place(CollectionOrder.step(row.id, by: offset, in: visible.map(\.id)))
  }

  var body: some View {
    @Bindable var navigation = navigation
    // Once, and shared by every row: `RFCRow` used to scan the whole bookmark list
    // itself, which is a linear search per row over a list that can be 9,842 rows
    // long.
    let bookmarked = library.bookmarkedDocuments
    // Only Available Offline's rows say where their bodies stand (#358).
    let showsOfflineState = shown.filter == .downloaded
    // Once, and shared by everything below and the overlay.
    let rows = self.rows
    let trigger = ListWindow.triggerRow(limit: limit, total: rows.count).map { rows[$0].id }
    // Selecting a row is a navigation: the setter goes through the history. Not
    // `library.open(_:activation:in:)` like every other open: a selection binding
    // is handed the outcome, not the click, and Command-click on a list row is the
    // platform's multi-select chord rather than ours to take.
    let window = rows.prefix(limit)
    let row = { (row: LibraryRow, showsYear: Bool) in
      OfflineStated(document: row.id, isShown: showsOfflineState) { offline in
        RFCRow(
          row: row, isBookmarked: bookmarked.contains(row.id), showsYear: showsYear,
          filter: shown.filter, offline: offline
        ) { library.downloadNow(row.id) }
      }
      .tag(row.id)
      // A combined element with no trait has the role AXUnknown on macOS, which
      // says nothing of what it is (#300). Here, where the row selects rather
      // than presses: elsewhere `RFCRow` is a button's label, and is a button.
      #if os(macOS)
        .accessibilityAddTraits(.isStaticText)
      #endif
      // An item provider rather than `.draggable`: it cooperates with `.onMove`,
      // which a collection's own list also uses (#349).
      .itemProvider { NSItemProvider(object: row.id.fileStem as NSString) }
      #if os(macOS)
        .modifier(
          MacRowActions(
            row: row, collection: collection, library: library, navigation: navigation,
            undoManager: undoManager, remove: remove))
      #else
        .modifier(RowActions(row: row, isBookmarked: bookmarked.contains(row.id)))
      #endif
      .onAppear {
        guard row.id == trigger else { return }
        limit = ListWindow.extendedLimit(from: limit, total: rows.count)
      }
    }
    // A collection in its own order can be rearranged and emptied (#349). Never
    // sectioned by year, so this is the branch a collection uses.
    let allowsMoving = shown.options.allowsMoving(in: shown.filter, query: shown.query)
    let visible = Array(window)
    let unsectioned = ForEach(window) { listed in
      row(listed, true)
        .accessibilityActions {
          if allowsMoving {
            Button("Move Up") { step(listed, by: -1, in: visible) }
            Button("Move Down") { step(listed, by: 1, in: visible) }
          }
        }
    }
    .onMove(perform: allowsMoving ? { move(from: $0, to: $1, in: visible) } : nil)
    .onDelete(
      perform: collection == nil
        ? nil
        : { offsets in offsets.map { visible[$0].id }.forEach(remove) })
    List(selection: $navigation.listSelection) {
      // A working group's card, above its RFCs while they are listed unsearched
      // (#363). Not a row: nothing to select.
      if let acronym = workingGroupCardAcronym {
        WorkingGroupCard(summary: library.workingGroupSummary(acronym))
          .listRowSeparator(.hidden)
          .selectionDisabled()
      }
      #if os(macOS)
        unsectioned
      #else
        // By year where the list is in order of publication, as Notes sections
        // its lists by date (#347). Over the window only: a later page's row may
        // join a year already on screen, which is above the reader by then.
        if YearSections.apply(to: shown.filter, query: shown.query) {
          ForEach(YearSections.sections(of: window)) { section in
            Section {
              ForEach(section.rows) { row($0, false) }
            } header: {
              Text(String(section.year))
                .levelWithCards()
            }
          }
        } else {
          unsectioned
        }
      #endif
      // Where Mail says when it last checked: after the last row, scrolled to
      // rather than pinned. Only once every row is in the window — after a
      // partial page it would read as the end of a list that goes on — and not
      // under an empty search, where the overlay already says what there is to
      // say.
      if limit >= rows.count, !(rows.isEmpty && navigation.listed != nil) {
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
    #endif
    .overlay {
      // Once the list is made: before, "No Documents" was a claim about a list
      // that had not arrived.
      if rows.isEmpty, navigation.listed != nil {
        // "No Results" only for a search: an empty Bookmarks list was told to
        // check its spelling.
        let isUnsearched = shown.query.isUnsearchedQuery
        if isUnsearched, let collection {
          ContentUnavailableView {
            Label("No Documents", systemImage: "folder")
          } description: {
            Text("Add RFCs from the reader, from any list, or here.")
          } actions: {
            Button("Add RFCs…") { addingTo = PickerTarget(id: collection) }
          }
        } else if isUnsearched, workingGroupCardAcronym == nil {
          // Not over a working group's card, which says what the group has.
          ContentUnavailableView(
            shown.filter.emptyTitle(in: library.collections),
            systemImage: shown.filter.systemImage)
        } else {
          ContentUnavailableView.search(text: shown.query)
        }
      }
    }
    .sheet(item: $addingTo) {
      // The list's undo manager, not the sheet's: on a Mac the sheet is a window
      // of its own, and what it registered went with it when it closed.
      CollectionPickerSheet(collection: $0.id, undoManager: undoManager)
    }
    #if os(macOS)
      // Delete takes the selected document out of the collection shown, and is
      // disabled everywhere else.
      .onDeleteCommand(
        perform: collection == nil
          ? nil
          : {
            if let selection = navigation.selection { remove(selection) }
          }
      )
      // The Mac's list has no toolbar of its own to put Add in.
      .safeAreaInset(edge: .bottom) {
        if let collection {
          HStack {
            Button {
              addingTo = PickerTarget(id: collection)
            } label: {
              Label("Add RFCs…", systemImage: "plus")
            }
            .buttonStyle(.borderless)
            Spacer()
          }
          .padding(8)
          .background(.bar)
        }
      }
    #endif
    #if !os(macOS)
      .onChange(of: navigation.filter) {
        // Edit belongs to a collection's list, and its button goes with it: left
        // on, a list beside the sidebar stayed in Edit with no way out.
        editMode?.wrappedValue = .inactive
      }
    #endif
    // On the rows' own filter, options and query rather than the tab's: those
    // change first, and the rows the window covers arrive after them (#597).
    .onChange(of: shown.filter, initial: true) {
      limit = ListWindow.initialLimit(covering: selectedRow())
    }
    // A new tab's first rows arrive after it appears, for the filter it already had
    // and maybe under a document it was opened on, which the window has to reach.
    .onChange(of: navigation.listed == nil) {
      limit = ListWindow.initialLimit(covering: selectedRow())
    }
    .onChange(of: shown.options) {
      limit = ListWindow.initialLimit(covering: selectedRow())
    }
    .onChange(of: navigation.appliedQuery) {
      limit = ListWindow.initialLimit(covering: selectedRow())
    }
    // Only ever wider. A selection arriving from outside the list — a deep link, a
    // citation, the Go to RFC palette — may sit far below the first page, and
    // `NavigationModel.open` resets the filter to `.all` precisely so nothing
    // hides it. Narrowing here instead would throw away a window the reader has
    // already scrolled down through.
    .onChange(of: navigation.listSelection) {
      limit = max(limit, ListWindow.initialLimit(covering: selectedRow()))
    }
    #if !os(macOS)
      .navigationTitle(library.title(for: navigation.filter))
      .navigationSubtitle(library.listSubtitle(for: navigation))
      // Inline, as Notes titles a folder. Large, the subtitle shrank to a caption
      // under it whenever the list was short enough not to scroll.
      .navigationBarTitleDisplayMode(.inline)
      // Narrows what this list shows, as Notes' field does inside a folder (#345).
      .filterSearchable(
        navigation: navigation,
        prompt: navigation.filter.searchPrompt(in: library.collections)
      )
      .onSubmit(of: .search) { navigation.applySearchWithoutPause() }
      .toolbar {
        LibraryBottomBar(navigation: navigation)
        ToolbarItem(placement: .primaryAction) { optionsMenu }
        // The tab's collection rather than the rows': a control follows the tab.
        if case .collection(let collection) = navigation.filter {
          ToolbarItem(placement: .primaryAction) {
            Button {
              addingTo = PickerTarget(id: collection)
            } label: {
              Label("Add", systemImage: "plus")
            }
          }
          ToolbarItem(placement: .topBarTrailing) { EditButton() }
        }
      }
      // The index could be refreshed only from the status line at the list's very
      // end (#348).
      .refreshable { await library.refreshIndex() }
      .sheet(isPresented: $showsAcknowledgements) { AcknowledgementsView() }
      .sheet(isPresented: $showsSettings) { SettingsScreen() }
    #endif
  }

  #if !os(macOS)
    /// How the list is shown, for this tab (#348).
    private var optionsMenu: some View {
      Menu {
        ListViewOptions(navigation: navigation)
        Section {
          // iOS has no Settings scene, and the reader's settings are the app's own
          // rather than the Settings app's (#703).
          Button("Settings", systemImage: "gearshape") {
            showsSettings = true
          }
          Button("Acknowledgements", systemImage: "doc.text") {
            showsAcknowledgements = true
          }
        }
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
    guard let selection = navigation.listSelection else { return nil }
    return rows.firstIndex { $0.id == selection }
  }
}

/// How a tab's list is shown (#348, #349): its order, or a collection's, and
/// whether obsolete documents are in it. The iOS list's View Options menu and the
/// Mac's View menu.
///
/// The one difference is each platform's convention for an order the list cannot
/// take — a search, or a list not in order of publication: the Mac's menu bar keeps
/// the item and disables it, where iOS leaves it out of the menu.
struct ListViewOptions: View {
  @Bindable var navigation: NavigationModel

  #if os(macOS)
    private let sortTitle: LocalizedStringKey = "Sort By"
  #else
    private let sortTitle: LocalizedStringKey = "Sort"
  #endif

  private var canReorder: Bool {
    ListOptions.canReorder(navigation.filter, query: navigation.appliedQuery)
  }

  var body: some View {
    if case .collection = navigation.filter {
      Picker(sortTitle, selection: $navigation.listOptions.collectionSort) {
        ForEach(ListOptions.CollectionSort.allCases, id: \.self) { Text(verbatim: $0.title()) }
      }
    } else {
      #if os(macOS)
        orderPicker.disabled(!canReorder)
      #else
        if canReorder { orderPicker }
      #endif
    }
    Toggle("Show Obsolete", isOn: $navigation.listOptions.showsObsolete)
  }

  private var orderPicker: some View {
    Picker(sortTitle, selection: $navigation.listOptions.order) {
      ForEach(ListOptions.Order.allCases, id: \.self) { Text(verbatim: $0.title()) }
    }
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
      case .failed(let kind, let message):
        Image(systemName: kind.symbol).foregroundStyle(.orange)
        // What went wrong in words first, as the reader says it of a document; the
        // error's own text, an HTTP status or where the XML broke, after it.
        VStack(alignment: .leading, spacing: 2) {
          Text(kind.recoverySuggestion(for: .index)).lineLimit(2)
          Text(message).lineLimit(2).foregroundStyle(.tertiary)
        }
        #if !os(macOS)
          if kind == .cellularDenied {
            Button("Open Settings", action: CellularSettings.open)
              .buttonStyle(.borderless)
          }
        #endif
        Button("Retry") { library.retryIndex() }
          .buttonStyle(.borderless)
      }
    }
    .font(.caption)
    .foregroundStyle(.secondary)
  }
}

/// A row that reads where its document's body stands itself, so a fetch starting or
/// ending redraws the rows rather than the whole list (#358). Reads nothing when not
/// `isShown`, so the rows of other lists do not redraw at all.
private struct OfflineStated<Content: View>: View {
  @Environment(LibraryModel.self) private var library
  let document: DocumentID
  let isShown: Bool
  @ViewBuilder let content: (OfflineRowState?) -> Content

  var body: some View {
    content(isShown ? library.offlineStatus.state(of: document) : nil)
  }
}

/// A library row: an RFC, or a BCP, STD or FYI bookmarked or read as itself
/// (#321), which shows the RFCs it names where an RFC shows its status and group.
struct RFCRow: View {
  let row: LibraryRow
  let isBookmarked: Bool
  /// False under a year's header, which already says it (#347).
  var showsYear = true
  /// The list's filter, whose fixed fields the row leaves out: PPPEXT's rows need
  /// not each say "pppext", nor the Internet Standards' each say "STD".
  var filter: LibraryFilter?
  /// In Available Offline, where the document's body stands while it is not on
  /// the device yet (#358).
  var offline: OfflineRowState?
  /// Download Now or Retry, beside `offline`: fetches on any path.
  var fetchNow: () -> Void = {}

  private var rfc: RFCMetadata? { row.rfc }

  private var status: PublicationStatus? {
    filter?.fixesStatus == true ? nil : rfc?.currentStatus
  }
  private var workingGroup: String? {
    filter?.fixesWorkingGroup == true ? nil : rfc?.workingGroup
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      #if os(macOS)
        designation
        title
        HStack(spacing: 6) {
          if let status {
            StatusBadge(status: status)
              .glossaryTooltip(.status(status))
          }
          if row.isObsolete {
            Text("Obsolete").font(.caption2).foregroundStyle(.secondary)
          }
          if let workingGroup {
            Text(workingGroup).font(.caption2).foregroundStyle(.tertiary)
          }
          if let memberList = row.memberList {
            Text(memberList).font(.caption2).foregroundStyle(.secondary)
          }
        }
      #else
        // The title leads, in bold, as a note's title leads its row in Notes
        // (#346), and everything else follows on one line beneath it, read from
        // the start: a gap between the parts rather than a separator, and
        // nothing pushed out to the far edge.
        title.font(.headline)
        HStack(alignment: .firstTextBaseline, spacing: 12) {
          Group {
            // Proportional digits: tabular ones are for a column, and the number
            // leads a line of text now rather than standing in one.
            // A narrow no-break space inside it, so "RFC" and its number read as
            // one thing beside the parts the wider gaps set apart.
            Text(row.id.displayName.replacing(" ", with: "\u{202F}"))
            if showsYear {
              Text(String(row.date.year))
            }
            // Spelled as the sidebar and the list's title spell it.
            if let workingGroup {
              Text(workingGroup.uppercased())
            }
            if row.isObsolete {
              Text("Obsolete")
            }
            if let memberList = row.memberList {
              Text(memberList)
            }
          }
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .lineLimit(1)
          if let status {
            StatusBadge(status: status)
              .glossaryTooltip(.status(status))
          }
          if isBookmarked {
            Image(systemName: "bookmark.fill").font(.caption).foregroundStyle(.tint)
          }
        }
      #endif
      if let offline {
        offlineLine(offline)
      }
    }
    .padding(.vertical, 2)
    // One element, not five: VoiceOver read the number, the year, the title, the
    // status and the group as separate stops per row (#156).
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(row.accessibilityLabel(isBookmarked: isBookmarked))
    .accessibilityValue(offline.map { Text(verbatim: $0.description()) } ?? Text(verbatim: ""))
    .accessibilityActions {
      // The row is one element, so its button is reached as an action of it.
      if let action = offline?.action() {
        Button(action: fetchNow) { Text(verbatim: action) }
      }
    }
  }

  /// What the body is waiting for, or that it is downloading or failed, with Download
  /// Now or Retry beside it.
  private func offlineLine(_ state: OfflineRowState) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 6) {
      Text(verbatim: state.description())
        .foregroundStyle(.secondary)
      if let action = state.action() {
        // Borderless, so it is pressed on its own rather than selecting the row.
        Button(action: fetchNow) { Text(verbatim: action) }
          .buttonStyle(.borderless)
      }
    }
    #if os(macOS)
      .font(.caption2)
    #else
      .font(.subheadline)
    #endif
  }

  #if os(macOS)
    private var designation: some View {
      HStack(alignment: .firstTextBaseline) {
        Text(row.id.displayName)
          .font(.subheadline.monospacedDigit())
          .foregroundStyle(.secondary)
        Spacer()
        if isBookmarked {
          Image(systemName: "bookmark.fill").font(.caption2).foregroundStyle(.tint)
        }
        if showsYear {
          Text(String(row.date.year)).font(.caption).foregroundStyle(.tertiary)
        }
      }
    }
  #endif

  private var title: some View {
    Text(row.title)
      .lineLimit(2)
      .strikethrough(row.isObsolete, color: .secondary)
      // Typeset as the English it is. Under a German system language, iOS
      // hyphenated titles mid-word, as in "Key Exch-ange" (#346).
      .typesettingLanguage(.init(identifier: "en"))
  }
}

/// A collection to add to, as a sheet's item (#349).
private struct PickerTarget: Identifiable {
  let id: UUID
}
