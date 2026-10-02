import RFCKit
import RFCReaderKit
import SwiftData
import SwiftUI

struct SidebarView: View {
  @Environment(LibraryModel.self) private var library
  @Environment(NavigationModel.self) private var navigation
  #if !os(macOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.editMode) private var editMode
  #endif
  // Which sections are open, kept across launches (#344).
  @AppStorage("sidebar.libraryExpanded") private var libraryExpanded = true
  @AppStorage("sidebar.browseExpanded") private var browseExpanded = true
  @AppStorage("sidebar.workingGroupsExpanded") private var workingGroupsExpanded = true
  @AppStorage("sidebar.collectionsExpanded") private var collectionsExpanded = true
  /// The collection whose deletion is being confirmed (#349).
  @State private var deleting: CollectionSnapshot.Entry?
  /// The store warning, shown again from the sidebar's unsaved-session row (#318).
  @State private var showsStoreWarning = false

  var body: some View {
    List(selection: Bindable(navigation).sidebarSelection) {
      #if os(macOS)
        places
      #else
        if isSearchingInPlace {
          searchResults
        } else {
          places
        }
      #endif
    }
    .navigationTitle("RFCs")
    #if os(macOS)
      // Search lives on the sidebar, not on the list it filters, and not in the
      // toolbar: the toolbar's trailing end belongs to the panel's toggle, and the
      // document's section of it is the wrong place for something that filters the
      // library. The text it binds to lives on `NavigationModel`, so `RFCListView`
      // filters on it exactly as before.
      //
      // Written out rather than `.searchable`, which draws nothing here: the
      // sidebar is its own hosting controller now, with no `NavigationSplitView`
      // around it to give `.sidebar` placement a meaning. Measured — the window
      // contained no text field at all.
      .safeAreaInset(edge: .top) {
        VStack(alignment: .leading, spacing: 6) {
          SidebarSearchField(navigation: navigation, library: library)
          // The field keeps the query as typed; the filters it sets are named
          // under it, each removable (#21). `NSSearchField` draws no tokens.
          SearchFilterChips(navigation: navigation)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
      }
    // New Collection is File > New Collection… on the Mac, and a toolbar button
    // at the trailing edge of the sidebar's section (`ReaderToolbar`), never in the
    // sidebar itself: a fixed button at its foot read as out of place (#349).
    #else
      // Beside Edit, as Notes keeps New Folder (#349).
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button {
            navigation.collectionEditor = .create(adding: nil)
          } label: {
            Label("New Collection", systemImage: "folder.badge.plus")
          }
        }
        if !library.collections.collections.isEmpty {
          ToolbarItem(placement: .topBarTrailing) { EditButton() }
        }
      }
      // Edit leaves with the last collection, since its button does.
      .onChange(of: library.collections.collections.isEmpty) {
        if library.collections.collections.isEmpty { editMode?.wrappedValue = .inactive }
      }
      // The list has a field of its own as well, which narrows the filter it
      // shows; this one searches the library (#345). Both bind the one text.
      .filterSearchable(navigation: navigation, prompt: "Search")
      .onSubmit(of: .search) { navigation.applySearchWithoutPause() }
      .toolbar { LibraryBottomBar(navigation: navigation) }
      .overlay {
        if isSearchingInPlace, library.indexState.isReady,
          navigation.listed?.librarySearch.isEmpty == true
        {
          ContentUnavailableView.search(text: navigation.appliedQuery)
        }
      }
      // Coming back from a list is leaving the search that list was narrowed by,
      // as it is in Notes. Otherwise the sidebar comes back showing the whole
      // library searched for what narrowed Bookmarks.
      .onAppear {
        if horizontalSizeClass == .compact { navigation.searchText = "" }
      }
      // A list of places, titled the way Notes' folders are (#343).
      .navigationBarTitleDisplayMode(.large)
    #endif
    .labelStyle(SidebarLabelStyle())
    .alert(AppData.storeWarning.title, isPresented: $showsStoreWarning) {
      Button("OK", role: .cancel) {}
    } message: {
      Text(AppData.storeWarning.message)
    }
    .confirmationDialog(
      "Delete “\(deleting?.name ?? "")”?",
      isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
      titleVisibility: .visible,
      presenting: deleting
    ) { entry in
      Button("Delete Collection", role: .destructive) {
        library.editCollections { try CollectionStore.delete(entry.id, in: $0) }
      }
    } message: { entry in
      // The count the sidebar shows, in words that agree with it: "The 1
      // documents" was what a one-document collection said.
      let count = library.count(of: entry) ?? entry.rfcNumbers.count
      Text(
        "It holds ^[\(count) document](inflect: true). Only the collection is removed; the documents stay in the library."
      )
    }
  }

  @ViewBuilder
  private var places: some View {
    group("Library", isExpanded: $libraryExpanded) {
      row(.bookmarks)
      row(.recent)
      row(.downloaded)
      // While the store is in memory, and only then: the launch alert says so once,
      // and a session can run for hours after it (#318). Here, where someone looks
      // when they wonder where their bookmarks went.
      if AppData.isStoredInMemory {
        Button {
          showsStoreWarning = true
        } label: {
          Label {
            Text("Not saved in this session")
          } icon: {
            // On the icon itself, or `SidebarLabelStyle` draws it in the accent
            // color on iOS, as it does the places: this is a status, not a place.
            Image(systemName: "exclamationmark.triangle")
              .foregroundStyle(.secondary)
          }
          .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .help(AppData.storeWarning.message)
      }
    }
    if !library.collections.collections.isEmpty {
      group("Collections", isExpanded: $collectionsExpanded) {
        ForEach(library.collections.collections) { entry in
          collectionRow(entry)
        }
        .onMove(perform: moveCollections)
        #if !os(macOS)
          .onDelete { offsets in
            deleting = offsets.first.map { library.collections.collections[$0] }
          }
        #endif
      }
    }
    group("Browse", isExpanded: $browseExpanded) {
      row(.all)
      row(.standards)
      row(.bestCurrentPractice)
      ForEach([PublicationStream.ietf, .irtf, .iab, .independent], id: \.self) { stream in
        row(.stream(stream))
      }
    }
    if !library.topWorkingGroups.isEmpty {
      group("Working Groups", isExpanded: $workingGroupsExpanded) {
        ForEach(library.topWorkingGroups, id: \.self) { group in
          row(.workingGroup(group))
        }
      }
    }
    // Not on iOS, where the sidebar is a list of places to go and this puts
    // documents among them (#343). It is the top of All RFCs anyway.
    #if os(macOS)
      justPublished
    #endif
  }

  /// A section that collapses (#344).
  ///
  /// On iOS the header is drawn here rather than by `Section(isExpanded:)`, whose
  /// header could not be made to look like Notes': `.headerProminence(.increased)`
  /// left it small and gray, its toggle came out black where Notes' is a dimmed
  /// gray, and it sat inset from the cards' edge, where Notes' is level with it.
  @ViewBuilder
  private func group<Content: View>(
    _ title: String, isExpanded: Binding<Bool>, @ViewBuilder content: () -> Content
  ) -> some View {
    #if os(macOS)
      Section(title, isExpanded: isExpanded, content: content)
    #else
      Section {
        if isExpanded.wrappedValue { content() }
      } header: {
        Button {
          withAnimation(.snappy) { isExpanded.wrappedValue.toggle() }
        } label: {
          HStack {
            Text(title)
              .font(.title2.weight(.semibold))
              // The label color itself: `.primary` resolves against the
              // header's own style, which is gray.
              .foregroundStyle(Color(uiColor: .label))
            Spacer()
            Image(systemName: "chevron.down.circle.fill")
              // Notes' size and gray, measured on the same phone: 17 pt across,
              // in a gray a step darker than `systemGray2`.
              .font(.body)
              .foregroundStyle(.white, Color(uiColor: .systemGray))
              .rotationEffect(.degrees(isExpanded.wrappedValue ? 0 : -90))
          }
        }
        .buttonStyle(.plain)
        .levelWithCards()
        .accessibilityValue(isExpanded.wrappedValue ? "Expanded" : "Collapsed")
        .accessibilityAddTraits(.isHeader)
      }
    #endif
  }

  #if !os(macOS)
    /// Whether the sidebar lists what was searched for rather than its places.
    ///
    /// Only collapsed: side by side, the list beside it shows the results. On an
    /// iPhone the list is not on screen, and the field searched for nothing anyone
    /// could see.
    private var isSearchingInPlace: Bool {
      horizontalSizeClass == .compact
        && !navigation.appliedQuery.isUnsearchedQuery
    }

    /// The first results, and the way to all of them in All RFCs, which keeps the
    /// query: the list is windowed (`ListWindow`) and this is not.
    @ViewBuilder
    private var searchResults: some View {
      let results = navigation.listed?.librarySearch ?? []
      let bookmarked = library.bookmarkedNumbers
      Section {
        ForEach(results.prefix(Self.searchResultLimit)) { rfc in
          Button {
            library.open(rfc.id, activation: .current, in: navigation)
          } label: {
            RFCRow(rfc: rfc, isBookmarked: bookmarked.contains(rfc.number))
          }
          .buttonStyle(.plain)
        }
        if results.count > Self.searchResultLimit {
          Button("Show All \(results.count.formatted()) Results") {
            navigation.sidebarSelection = .all
          }
        }
      }
    }

    private static let searchResultLimit = 50
  #endif

  private func row(_ filter: LibraryFilter) -> some View {
    HStack {
      Label(library.title(for: filter), systemImage: filter.systemImage)
      #if os(macOS)
        accessories(count: nil)
      #else
        accessories(count: count(filter))
      #endif
    }
    .tag(filter)
  }

  /// The count and, collapsed, the chevron, after a row's label. Nothing on a Mac.
  @ViewBuilder
  private func accessories(count: Int?) -> some View {
    #if !os(macOS)
      Spacer()
      // Written out rather than `.badge`, which would draw after the chevron.
      if let count {
        Text(count, format: .number)
          .foregroundStyle(.secondary)
          .monospacedDigit()
      }
      // Collapsed, a row pushes the list, and nothing said so: the rows are
      // selection-tagged rather than `NavigationLink`s, which is what draws the
      // system's own chevron.
      if horizontalSizeClass == .compact {
        Image(systemName: "chevron.forward")
          .font(.footnote.weight(.semibold))
          .foregroundStyle(.tertiary)
          .accessibilityHidden(true)
      }
    #endif
  }

  // MARK: - Collections

  private func collectionRow(_ entry: CollectionSnapshot.Entry) -> some View {
    let filter = LibraryFilter.collection(entry.id)
    return HStack {
      Label {
        Text(entry.name)
      } icon: {
        CollectionFolderIcon(color: entry.color)
      }
      #if os(macOS)
        accessories(count: nil)
      #else
        accessories(count: library.count(of: entry))
      #endif
    }
    // List rows dropped here join the collection at its end.
    .dropDestination(for: String.self) { keys, _ in
      let documents = keys.compactMap(DocumentID.init(fileStem:))
      guard !documents.isEmpty else { return false }
      library.editCollections { context in
        for document in documents {
          try CollectionStore.add(document, to: entry.id, in: context)
        }
      }
      return true
    }
    .tag(filter)
    .contextMenu {
      // The editor holds the name and the color both: one place to change either.
      Button("Edit…") { navigation.collectionEditor = .edit(entry.id) }
      Divider()
      Button("Delete…", role: .destructive) { deleting = entry }
    }
  }

  private func moveCollections(from source: IndexSet, to destination: Int) {
    let identifiers = library.collections.collections.map(\.id)
    guard let drop = CollectionOrder.drop(from: source, to: destination, in: identifiers) else {
      return
    }
    library.editCollections {
      try CollectionStore.moveCollection(
        drop.moved, afterVisible: drop.above, beforeVisible: drop.below, in: $0)
    }
  }

  #if !os(macOS)
    /// How many documents a row leads to (#344): the index's own count, or the
    /// reader's data for the Library rows. Nil while the index loads, and for a
    /// filter it lists nothing in.
    private func count(_ filter: LibraryFilter) -> Int? {
      switch filter {
      case .bookmarks: library.bookmarkedNumbers.count
      case .downloaded: library.downloadedNumbers.count
      case .recent: library.recentlyReadCount
      default: library.indexCounts[filter]
      }
    }
  #endif

  #if os(macOS)
    @ViewBuilder
    private var justPublished: some View {
      if !library.recent.isEmpty {
        Section("Just Published") {
          ForEach(library.recent.prefix(5)) { recent in
            Button {
              library.open(recent.id, activation: .current, in: navigation)
            } label: {
              VStack(alignment: .leading, spacing: 2) {
                Text(recent.id.displayName).font(.caption).foregroundStyle(.secondary)
                Text(recent.title).lineLimit(2)
              }
            }
            .buttonStyle(.plain)
          }
        }
      }
    }
  #endif
}

/// Gives every sidebar row's icon a column of its own, so the titles line up however
/// wide the glyph is.
///
/// `Label` sizes the icon to the symbol and leaves it at that. Most of the sidebar's
/// symbols carry enough of their own whitespace to look spaced anyway; the wide ones
/// do not, and `person.3` — 28 pt against `bookmark`'s 14 — ran straight into its
/// title. Spacing alone would fix that row and leave the titles on a ragged edge, so
/// the icon gets a fixed column instead and the two problems go away together.
private struct SidebarLabelStyle: LabelStyle {
  func makeBody(configuration: Configuration) -> some View {
    Row(icon: configuration.icon, title: configuration.title)
  }

  private struct Row: View {
    let icon: LabelStyleConfiguration.Icon
    let title: LabelStyleConfiguration.Title
    /// Wide enough for the widest symbol the sidebar uses, and scaled with the
    /// text so the column still holds at larger accessibility sizes.
    ///
    /// On iOS wider and further from the title, where Notes sets its folder names,
    /// measured on the same phone: the titles started 11 pt short of Notes'.
    #if os(macOS)
      @ScaledMetric(relativeTo: .body) private var column: CGFloat = 22
      private let spacing: CGFloat = 6
    #else
      @ScaledMetric(relativeTo: .body) private var column: CGFloat = 28
      @ScaledMetric(relativeTo: .body) private var spacing: CGFloat = 12
    #endif

    var body: some View {
      HStack(spacing: spacing) {
        icon
          .frame(width: column)
          #if !os(macOS)
            // In the accent color, as Notes draws its folders (#343). Not on
            // macOS, whose sidebar tints its icons already and turns them white
            // on a selected row, which an explicit style would override.
            .foregroundStyle(.tint)
          #endif
        title
      }
    }
  }
}

/// A collection's folder, in its color (#349).
private struct CollectionFolderIcon: View {
  let color: CollectionColor

  #if os(macOS)
    @Environment(\.backgroundProminence) private var prominence
  #endif

  var body: some View {
    Image(systemName: "folder")
      .foregroundStyle(style)
  }

  /// On a Mac a row drawn with the accent behind it turns its icons white, and an
  /// explicit color would override that: `.primary` there follows the row. Only
  /// that row — a selection in an inactive window or an unfocused sidebar is drawn
  /// gray, and keeps the folder's color, as Finder's tags do.
  private var style: AnyShapeStyle {
    #if os(macOS)
      if prominence == .increased { return AnyShapeStyle(.primary) }
    #endif
    return AnyShapeStyle(color.color)
  }
}
