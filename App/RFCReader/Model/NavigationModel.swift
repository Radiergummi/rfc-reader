import Observation
import RFCKit
import RFCReaderKit
import SwiftUI

/// Everything one tab is looking at: which document, which sidebar filter, what was
/// typed into search, and the back/forward stack that got it here.
///
/// One of these per tab — held by its `ReaderWindowController` on macOS, and as
/// `@State` in `ContentView` on iOS — which is what makes a tab a tab. All of this
/// used to live on `LibraryModel.shared`, so every window and tab in the process
/// shared one selection: opening an RFC in one tab switched every other tab to it.
/// `LibraryModel` keeps only what genuinely is process-wide — the index, the
/// document cache, the search index.
///
/// The stack itself is `NavigationHistory` in RFCReaderKit, under test. This type is
/// the observable shell around it, plus the bookkeeping SwiftUI needs.
@Observable
final class NavigationModel: Identifiable {
  nonisolated let id = UUID()

  private var history = NavigationHistory() {
    didSet { readerPath = ReaderPath(history) }
  }

  /// Where the reader has scrolled to in the current document, mirrored here so
  /// that navigating away can record it on the entry being left. `DocumentView`
  /// writes it as the reader scrolls; nothing reads it but the navigation methods.
  var visiblePosition: String?

  /// Takes the list inputs on entering a filter, not on a change of `value`: on
  /// iPhone, going back to the sidebar clears the selection and keeps `value`, so
  /// tapping the same filter again leaves `value` as it was.
  private var filterChoice = KeptSelection(LibraryFilter.all) {
    didSet {
      if filterChoice.enters(since: oldValue) { takeListInputs() }
    }
  }
  /// What is typed into search. The list follows `appliedQuery`, not this.
  var searchText = "" {
    didSet { followSearchText(pausing: true) }
  }
  /// The search text, trimmed, once typing pauses (#124): what the list is asked to
  /// search for. Read only to make the list; views read `appliedQuery`.
  private var requestedQuery = ""
  @ObservationIgnored private var pendingSearch: Task<Void, Never>?

  /// What the list shows, made off the main actor whenever one of its inputs changes
  /// (#597): this tab's filter, query, options and the inputs it took on entering the
  /// filter, and the library's index, bookmarks and collections. Views only read it.
  /// Until the next arrives the list keeps what it has, as Mail and Finder do; nil
  /// until the first, so an empty list is never claimed before it was made.
  private(set) var listed: ListedRows?
  @ObservationIgnored private var listing: Task<Void, Never>?

  /// What the full-text search found for a list (#37): the "In the text" rows under
  /// it. Made after the list, and again whenever the full-text index changes; until
  /// the next arrives this keeps what it has, for the list it was made for, which a
  /// view compares with the list it shows.
  private(set) var textFound: TextFound?
  @ObservationIgnored private var textSearching: Task<Void, Never>?

  struct TextFound {
    let list: LibraryList
    /// Nil when the search has nothing to say of the list: there is no index, or the
    /// list asks the text nothing (`LibraryModel.textSearch`).
    let found: TextIndexer.Found?
  }

  /// The query the list, its count and the sidebar's results are for: the one whose
  /// rows are on show.
  var appliedQuery: String { listed?.list.query ?? "" }
  /// The iOS list's view options, for this tab (#348).
  var listOptions = ListOptions()
  var isShowingGoToSheet = false
  /// The collection sheet on show, if any: creating one — perhaps to add a document
  /// to — or editing one (#349). On the model rather than a view's state so the
  /// sidebar, the Add to Collection menus and the Mac's File menu can all ask for
  /// it, and the one view that presents it is in the window.
  var collectionEditor: CollectionEditorMode?

  /// What Save as Collection… would keep (#355): the list on show as a query of the
  /// whole library (`LibraryList.savedQuery`). Nil, and the item disabled, while the
  /// list is not searched: there is nothing to keep that the sidebar doesn't list.
  var savedQuery: String? {
    guard let list = listed?.list, !list.query.isUnsearchedQuery else { return nil }
    // Not a search for a section, which a collection's list never shows.
    let query = list.savedQuery(in: library.collections)
    return CollectionStore.isValidQuery(query) ? query : nil
  }

  /// Whether the tab lists a collection made from a query (#355), which is in the
  /// whole library's order rather than one of its own.
  var listsDynamicCollection: Bool {
    guard case .collection(let identifier) = filter else { return false }
    return library.collections[identifier]?.isDynamic ?? false
  }

  /// Save as Collection…: the editor, with the query to keep. On the Mac through
  /// `ReaderWindowController.saveAsCollection()`, which opens the sidebar first.
  func saveAsCollection() {
    guard let savedQuery else { return }
    collectionEditor = .save(query: savedQuery)
  }
  /// The reading path sheet on show, if any (#189): asked for by a row's context
  /// menu or the Info pane, presented by `ReaderScene`, for the same reason.
  var readingPath: ReadingPathRequest?
  /// The glossary entry on show on iOS, asked for by a view that cannot present it:
  /// the reader header, hosted outside the view-controller hierarchy (#362).
  var glossaryTerm: Glossary.Term?
  /// The whole document's errata on show on iOS, asked for by the reader header for
  /// the same reason (#387).
  var errataShown: ErrataRequest?

  /// The library the list is computed from, and which the inputs below are taken
  /// from on entering a filter.
  @ObservationIgnored private let library: LibraryModel

  /// `listsDocuments` false for a navigation that shows no list: the reader beside a
  /// compared document (#187), which would otherwise list the library for nothing.
  init(library: LibraryModel, listsDocuments: Bool = true) {
    self.library = library
    if listsDocuments {
      followListInputs()
      followTextSearch()
    }
  }

  isolated deinit {
    listing?.cancel()
    textSearching?.cancel()
    pendingSearch?.cancel()
  }

  /// The Recently Read order, taken once when the filter is entered.
  ///
  /// Not live: opening or leaving a document writes its `updatedAt`, so an order
  /// kept in step with that re-sorted the list the click came from — the row just
  /// left jumped to the top and everything below it shifted down a place. Taken on
  /// entering instead, the order is whatever it was on arrival and stays put while
  /// it is being read through; coming back to the filter takes a fresh one, the
  /// same way `downloaded` beside it does.
  private(set) var recentOrder: [DocumentID] = []
  /// The RFCs available offline, as of entering the filter.
  private(set) var downloaded: Set<Int> = []

  /// Takes the inputs a list is computed from on entering a filter.
  private func takeListInputs() {
    recentOrder = library.recentlyRead()
    downloaded = library.availableOfflineNumbers
  }

  /// What the list lists: the last filter chosen, whether or not the sidebar still
  /// shows it as selected.
  var filter: LibraryFilter { filterChoice.value }

  /// The sidebar's `List(selection:)`, bound to directly.
  ///
  /// Nil when a collapsed split view has gone back to the sidebar. A Mac refuses
  /// it: the sidebar is always beside the list there, and shows which filter feeds
  /// it, so a click in its blank space or a Command-click must not leave it showing
  /// none.
  var sidebarSelection: LibraryFilter? {
    get { filterChoice.selection }
    set {
      #if os(macOS)
        guard newValue != nil else { return }
      #endif
      filterChoice.selection = newValue
    }
  }

  /// Leaves a collection that no longer exists (#349). A cleared selection stays
  /// cleared, so a collapsed sidebar does not push a list; a shown one moves to the
  /// fallback.
  func keepFilter(in snapshot: CollectionSnapshot) {
    let kept = KeptFilter.filter(filter, keeping: snapshot)
    guard kept != filter else { return }
    if filterChoice.selection == nil {
      filterChoice.replaceValue(kept)
    } else {
      sidebarSelection = kept
    }
  }

  /// The document list's `List(selection:)`, bound to directly, and what the reader
  /// shows.
  ///
  /// Setting a row is `select(_:)`. Setting nil — a collapsed split view going back
  /// to the list, or a Mac deselecting the row — hides the document and leaves the
  /// history alone, so Back and Forward still work (#261). The selection used to be
  /// `history.current`, which never becomes nil again, and every list bound to it
  /// needed a workaround of its own for the nil a pop writes.
  var selection: DocumentID? {
    get { history.shown?.id }
    set {
      if let newValue {
        select(newValue)
      } else {
        // A jump a script waits on is not coming: its reader goes.
        updateRequests(outcome: .interrupted) { $0.hide(in: &history) }
      }
    }
  }

  /// The document list's selection: `selection`, except that on iOS it is the root of
  /// the stack of readers rather than the reader on top (#263). A citation pushes a
  /// reader and leaves the row that opened the stack selected: a collapsed split
  /// view that saw its list's selection change took it for a new row tapped and
  /// emptied the stack's path as it pushed, so the cited RFC never slid in and Back
  /// went to the list (measured, #679).
  var listSelection: DocumentID? {
    get {
      #if os(macOS)
        selection
      #else
        readerPath.root?.id
      #endif
    }
    set { selection = newValue }
  }

  /// The document the history holds, shown or not. A collapsed split view that has
  /// gone back to its list hides the document and still holds it, so a link to it
  /// belongs in this tab: routing reads this, not `selection` (#256).
  var heldDocument: DocumentID? { history.current?.id }

  /// The RFC whose text the tab's reader shows (#656): `selection`, or the first
  /// member of the BCP, STD or FYI selected; nil while a series waits for the index.
  /// What acts on the text -- Print, Export, Cite, a collection -- acts on this, and
  /// what keeps the place -- Bookmark, Recently Read, the history -- on `selection`.
  var shown: DocumentID? { selection.flatMap(library.documentShown) }

  /// What the reader on screen is asked to scroll to: `requests.current`, published
  /// only when it changes.
  private(set) var scrollRequest: ScrollRequest?

  /// How a jump within the document ended, for whoever waits on it: a script's
  /// `jump to section`, which reports all but the first as an error (#762).
  enum JumpOutcome {
    /// The reader went there.
    case landed
    /// The document holds no such place.
    case noSuchPlace
    /// There was no document to jump in: none on screen, or it failed to load.
    case notShown
    /// The document was hidden, the tab went somewhere else, or another jump was
    /// asked for, before the reader made it.
    case interrupted
  }

  /// The scroll request, and whoever waits for the jump it asked for: a script,
  /// whose next command must find the jump in the history (#482).
  @ObservationIgnored private var requests = ScrollRequests<(JumpOutcome) -> Void>()

  /// Makes `change` to the requests, publishes the request, and then tells the
  /// waiter whose wait the change ended, if it ended one, that its jump ended as
  /// `outcome`.
  private func updateRequests(
    outcome: JumpOutcome,
    _ change: (inout ScrollRequests<(JumpOutcome) -> Void>) -> ((JumpOutcome) -> Void)?
  ) {
    let ended = change(&requests)
    if scrollRequest != requests.current { scrollRequest = requests.current }
    ended?(outcome)
  }

  var canGoBack: Bool { history.canGoBack }
  var canGoForward: Bool { history.canGoForward }
  /// Where Back returns to, straight after a jump within the document on screen.
  var returnOffer: HistoryEntry? { history.returnOffer }

  func settleReturnOffer() {
    history.settleReturnOffer()
  }

  // MARK: - Navigation

  /// A link from outside the current document: the sidebar, a deep link, a citation
  /// in the prose, or Go to RFC. A citation, or anything else followed inside the
  /// reader, arrives as `.citation`, which on iOS pushes a reader (#263).
  ///
  /// A BCP, STD or FYI is opened as itself, so it is bookmarked and recorded as the
  /// series; its reader shows its first member (#656).
  func open(_ link: RFCLink, arrival: HistoryEntry.Arrival = .root) {
    let route = OpenRoute.route(link, arrival: arrival, selected: selection, shown: shown)
    guard route.reveals else {
      follow(route)
      return
    }
    // The list's own selected row: on iOS the root of the stack of readers, which a
    // jump in a reader a citation pushed leaves where it is (#263).
    let row = route.row(selected: listSelection)
    let list = listOnShow
    let reveals = route.reveals(selected: listSelection, among: list.rows)
    follow(route)
    if reveals {
      sidebarSelection = .all
      searchText = ""
      // Only where it is what hides the row: it is the reader's choice for the tab.
      if let row, library.metadata(row)?.isObsolete == true {
        listOptions.showsObsolete = true
      }
    } else if sidebarSelection != list.filter {
      // A collapsed sidebar pushes the list the row is on show in, and the reader.
      sidebarSelection = list.filter
    }
  }

  /// The list the reader sees, and its rows if they are those the inputs ask for
  /// now: nil while a new filter's list is still being made, or typing has not
  /// paused for the search, when the rows on show are about to be replaced.
  ///
  /// The filter's list, but where a collapsed sidebar is on screen in its place
  /// (iOS) and searched: that shows the whole library's results, which All lists
  /// with the query kept (#345).
  private var listOnShow: (filter: LibraryFilter, rows: [DocumentID]?) {
    let searchesLibrary = sidebarSelection == nil && !appliedQuery.isUnsearchedQuery
    let shownFilter: LibraryFilter = searchesLibrary ? .all : filter
    guard AppliedSearch.query(for: searchText) == requestedQuery, let request = request(),
      shows(request), let listed
    else { return (shownFilter, nil) }
    return (shownFilter, (searchesLibrary ? listed.librarySearch : listed.rows).map(\.id))
  }

  private func follow(_ route: OpenRoute) {
    switch route {
    case .jump(let place, _): jump(toSection: place)
    case .navigate(let entry): go(to: entry)
    }
  }

  func open(_ id: DocumentID, section: String? = nil) {
    open(RFCLink(id: id, section: section))
  }

  /// Searches the whole library: a question asked from one document, such as a
  /// keyword chosen in the Info pane (#25), is about every RFC, not about the
  /// collection the list happens to show.
  func search(_ text: String) {
    sidebarSelection = .all
    searchText = text
    applySearchWithoutPause()
  }

  // MARK: - Search

  /// Applies the search text without waiting for a pause in typing: Return in the
  /// field, or a search asked for with a click. The list still follows once its
  /// rows are made.
  func applySearchWithoutPause() {
    followSearchText(pausing: false)
  }

  /// Sets the search text and applies it before returning, searching on the main
  /// actor: for a script, which reads the list straight after setting the text.
  func setSearchTextSynchronously(_ text: String) {
    searchText = text
    pendingSearch?.cancel()
    pendingSearch = nil
    requestedQuery = AppliedSearch.query(for: text)
    listNow()
  }

  /// Lists what the inputs ask for before returning, on the main actor: for a
  /// script, and for a drag or a delete in a collection's list, whose rows `List`
  /// must have before the gesture ends or it puts the row back and moves it again.
  func listNow() {
    guard let request = request(), !shows(request),
      let made = library.listedNow(request.list, hits: knownHits(for: request))
    else { return }
    listed = made
  }

  /// The rows the inputs ask for, for a script, which reads the list straight after
  /// changing it: the rows on show when they are those, and otherwise made on the
  /// spot, leaving the list on show to its own listing.
  func rowsNow() -> [LibraryRow] {
    guard let request = request() else { return [] }
    if shows(request), let listed { return listed.rows }
    return library.listedNow(request.list, hits: knownHits(for: request))?.rows ?? []
  }

  /// Applies the search text as `AppliedSearch` says to: after a pause in typing,
  /// or at once when it is cleared.
  private func followSearchText(pausing: Bool) {
    pendingSearch?.cancel()
    pendingSearch = nil
    switch AppliedSearch.step(applying: searchText, over: requestedQuery, pausing: pausing) {
    case nil:
      // Typed back to the query asked for: nothing is left to apply.
      return
    case .apply(let query):
      requestedQuery = query
    case .search(let query, let delay):
      pendingSearch = Task(name: "Apply search") { [weak self] in
        guard await Debounce.outlasted(delay) else { return }
        self?.requestedQuery = query
      }
    }
  }

  // MARK: - The list

  /// A list asked for, over the index it is to be made over.
  private struct ListRequest: Equatable, Sendable {
    let list: LibraryList
    let indexVersion: Int
  }

  /// What the inputs ask for, read so that only what this filter lists from is
  /// observed (`LibraryList.reading`). Nil while there is no index.
  private func request() -> ListRequest? {
    guard library.index != nil else { return nil }
    return ListRequest(
      list: LibraryList.reading(filter, query: requestedQuery, options: listOptions, from: self),
      indexVersion: library.indexVersion)
  }

  /// Whether the list on show is what `request` asks for (`ListedRows.shows`).
  private func shows(_ request: ListRequest) -> Bool {
    listed?.shows(request.list, indexVersion: request.indexVersion) ?? false
  }

  /// The hits the list on show found, if `request` can list from them
  /// (`ListedRows.hits(for:indexVersion:)`).
  private func knownHits(for request: ListRequest) -> [RFCMetadata]? {
    listed?.hits(for: request.list, indexVersion: request.indexVersion)
  }

  /// Lists again whenever an input of the list changes: `Observations` yields what
  /// is asked for after each change, and the latest when a listing ends, so typing
  /// or clicking through filters faster than a listing takes makes one per pause
  /// rather than one per change.
  private func followListInputs() {
    let requests = Observations { [weak self] in self?.request() }
    listing = Task(name: "List") { [weak self] in
      for await request in requests {
        guard let request, let self, !self.shows(request) else { continue }
        let made = await self.library.listed(request.list, hits: self.knownHits(for: request))
        // Overtaken by a newer request, which comes next, or by `listNow()`.
        guard let made, !Task.isCancelled, self.request() == request, !self.shows(request)
        else { continue }
        self.listed = made
      }
    }
  }

  /// A full-text search asked for: the list on show, over the full-text index as it
  /// is now.
  private struct TextRequest: Equatable {
    let list: LibraryList
    let textIndexVersion: Int
  }

  private func textRequest() -> TextRequest? {
    guard let list = listed?.list else { return nil }
    return TextRequest(list: list, textIndexVersion: library.textIndexVersion)
  }

  /// Searches the text again whenever the list on show or the full-text index
  /// changes, as `followListInputs` lists again.
  private func followTextSearch() {
    let requests = Observations { [weak self] in self?.textRequest() }
    textSearching = Task(name: "Search the text") { [weak self] in
      for await request in requests {
        guard let request, let self else { continue }
        let found = await self.library.textSearch(request.list)
        // Kept while the index changed under it, as the first pass changes it every
        // few documents: it is newer than what is on show, and the next search follows.
        guard !Task.isCancelled, self.textRequest()?.list == request.list else { continue }
        self.textFound = TextFound(list: request.list, found: found)
      }
    }
  }

  /// A section the full-text search found (#37): its document, at the section, or a
  /// jump to the section where the document is on screen, as `open` routes it. Like
  /// `select(_:)`, it leaves the filter and the search alone, which the hit is in.
  func select(_ hit: SectionHit) {
    let link = RFCLink(id: hit.document, anchor: hit.anchor)
    follow(OpenRoute.route(link, selected: selection, shown: shown))
  }

  /// A row picked in the document list.
  ///
  /// Unlike `open`, it leaves the filter alone. The row is in the list the reader
  /// is looking at by construction, so a narrowed filter cannot be hiding it, and
  /// resetting to `.all` would swap the Bookmarks list they were working in for
  /// the whole library with that one row highlighted somewhere inside it.
  ///
  /// A series row, which Bookmarks and Recently Read can show (#321), opens the
  /// series, as `open` does: its reader shows its first member (#656).
  func select(_ id: DocumentID) {
    go(to: HistoryEntry(id: id))
  }

  /// A jump within the document already open — a section link in the prose, a row
  /// in the table of contents, or `jump to section`. Handed to the reader, which
  /// records it through `recordJump(to:in:)` where its document holds the place.
  /// `whenSettled` runs once it has, or once the reader has done what else it will
  /// with the place: after the document loads, if it is still loading.
  func jump(
    toSection section: String, whenSettled done: @escaping (JumpOutcome) -> Void = { _ in }
  ) {
    // With no document on screen this jump's wait ends at once; with one, the jump
    // it replaces is the one whose wait ends, unmade.
    updateRequests(outcome: selection != nil ? .interrupted : .notShown) {
      $0.jump(to: section, inDocumentOnScreen: selection != nil, waiter: done)
    }
  }

  /// The reader has done what it will with `request`, where that recorded nothing:
  /// a bibliography entry shown, a place the document does not hold, or a document
  /// that failed to load.
  func settle(_ request: ScrollRequest, as outcome: JumpOutcome) {
    updateRequests(outcome: outcome) { $0.settle(request) }
  }

  /// A place the document on screen holds: its own history entry, so Back undoes
  /// it, unless the reader is already there. Compared in `places`' spelling, so a
  /// section's number and its anchor are one place (#482).
  func recordJump(to section: String, in places: DocumentPlaces) {
    guard let id = selection else { return }
    go(to: HistoryEntry(id: id, section: section, arrival: .citation), in: places, ending: .landed)
  }

  func goBack() {
    #if os(macOS)
      guard let place = history.goBack(leaving: visiblePosition) else { return }
      arrive(at: place)
    #else
      let path = readerPath
      guard let place = history.goBack(leaving: visiblePosition) else { return }
      // A step back to the reader below pops the one on top, and shows that reader
      // where it was left (#263).
      if path.pops(to: readerPath) {
        arriveKept(at: place)
      } else {
        arrive(at: place)
      }
    #endif
  }

  func goForward() {
    guard let place = history.goForward(leaving: visiblePosition) else { return }
    arrive(at: place)
  }

  /// `outcome` is how a jump this ends the wait for ended: only the reader recording
  /// it is the jump made; anywhere else the tab goes, it was not (#762).
  private func go(
    to place: HistoryEntry, in places: DocumentPlaces? = nil,
    ending outcome: JumpOutcome = .interrupted
  ) {
    var arrived: HistoryEntry?
    updateRequests(outcome: outcome) {
      let went = $0.go(to: place, in: &history, leaving: visiblePosition, places: places)
      arrived = went.arrived
      return went.ended
    }
    if let arrived { visiblePosition = arrived.section }
  }

  private func arrive(at place: HistoryEntry) {
    updateRequests(outcome: .interrupted) { $0.arrive(at: place.section) }
    visiblePosition = place.section
  }

  /// At a place in a reader the stack kept, which is where it was left: nothing to
  /// scroll to, unless the reader was let go and is made again.
  private func arriveKept(at place: HistoryEntry) {
    updateRequests(outcome: .interrupted) { $0.arrive(at: place.section, inKeptReader: true) }
    visiblePosition = place.section
  }

  // MARK: - The readers stacked on iOS (#263)

  /// The readers stacked in this tab's detail column on iOS: the root, and one for
  /// each citation of another RFC followed since. The Mac has one reader. Kept as
  /// the history changes, since every reader asks it on every scroll tick through
  /// `shows(_:at:)`.
  private(set) var readerPath = ReaderPath(NavigationHistory())

  /// Whether the reader of `id` at `depth` in the stack is the one on screen, whose
  /// the window's reader state is. `depth` is nil for a reader that is not stacked,
  /// the Mac's, which is on screen while its document is selected.
  func shows(_ id: DocumentID, at depth: Int?) -> Bool {
    guard let depth else { return selection == id }
    return readerPath.isTop(id, at: depth)
  }

  /// Whether the tab still holds the reader of `id` at `depth`, on screen or, on
  /// iOS, kept below the top of the stack.
  func holds(_ id: DocumentID, at depth: Int?) -> Bool {
    guard let depth else { return selection == id }
    return readerPath.holds(id, at: depth)
  }

  /// The stack's own back, the system back button or a swipe from the edge, which
  /// cut its path back to `pushed`: the history steps back past each reader popped,
  /// and the one shown is where it was left.
  func popReaders(toPushed pushed: [ReaderPath.Reader]) {
    guard let place = history.popReaders(toPushed: pushed, leaving: visiblePosition) else {
      return
    }
    arriveKept(at: place)
  }

  // MARK: - Across launches

  /// What this tab keeps across launches (#155), with its reader's inspector tab.
  func snapshot(inspectorTab: InspectorTab, layout: WindowLayout? = nil) -> SceneSnapshot {
    SceneSnapshot(
      history: history.snapshot(), filter: filter, inspectorTab: inspectorTab.rawValue,
      layout: layout)
  }

  /// Puts the tab back as `snapshot` left it, and its inspector tab into `reader`.
  /// Nothing is asked to scroll: the document opens at its reading position, which
  /// is kept with it. A collection deleted since leaves for the fallback, as one
  /// deleted while the tab is open does.
  func restore(_ snapshot: SceneSnapshot, into reader: ReaderState) {
    history = NavigationHistory(snapshot.history)
    sidebarSelection = KeptFilter.filter(snapshot.filter, keeping: library.collections)
    reader.tab = snapshot.inspectorTab.flatMap(InspectorTab.init(rawValue:)) ?? reader.tab
  }
}

/// What this tab's list may list from: the inputs it took on entering the filter,
/// and the library's bookmarks and collections as they stand.
extension NavigationModel: ListSources {
  var bookmarked: Set<DocumentID> { library.bookmarkedDocuments }
  var recentlyRead: [DocumentID] { recentOrder }

  func members(of collection: UUID) -> [Int] {
    library.collections[collection]?.rfcNumbers ?? []
  }

  func collection(named name: String) -> UUID? {
    library.collections.collection(named: name)?.id
  }

  func query(of collection: UUID) -> String? {
    library.collections[collection]?.query
  }
}
