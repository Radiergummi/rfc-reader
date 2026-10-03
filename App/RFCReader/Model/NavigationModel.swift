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
  /// A request to scroll somewhere, carrying its own identity.
  ///
  /// Not a bare `String?`: a reader can navigate to the same section twice in a row
  /// — back, then forward again, or the same contents row clicked twice — and an
  /// `onChange` watching the section alone would see no change and never scroll.
  struct ScrollRequest: Equatable {
    let section: String
    /// A place in the document on screen, which has no entry in the history yet:
    /// the reader gives it one if its document holds the place, and otherwise moves
    /// nothing (#276). Only the reader can tell, having the build, and only it can
    /// say that `4.2` and `section-4.2` are the same place (#482).
    var isUnrecorded = false
    /// False for a jump the reader makes as its text appears: a document just
    /// loaded opens at the place rather than animating there from its top.
    var isAnimated = true
    private let issue = UUID()
  }

  nonisolated let id = UUID()

  private var history = NavigationHistory()

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
  /// The reading path sheet on show, if any (#189): asked for by a row's context
  /// menu or the Info pane, presented by `ReaderScene`, for the same reason.
  var readingPath: ReadingPathRequest?
  /// The glossary entry on show on iOS, asked for by a view that cannot present it:
  /// the reader header, hosted outside the view-controller hierarchy (#362).
  var glossaryTerm: Glossary.Term?

  /// The library the list is computed from, and which the inputs below are taken
  /// from on entering a filter.
  @ObservationIgnored private let library: LibraryModel

  init(library: LibraryModel) {
    self.library = library
    followListInputs()
  }

  isolated deinit {
    listing?.cancel()
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
    takeDownloaded()
  }

  /// Takes the RFCs available offline again, without the rest of the list inputs:
  /// for the first set the library reads, which a tab made before it took empty.
  func takeDownloaded() {
    downloaded = library.downloadedNumbers
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
        history.hide()
      }
    }
  }
  /// The document the history holds, shown or not. A collapsed split view that has
  /// gone back to its list hides the document and still holds it, so a link to it
  /// belongs in this tab: routing reads this, not `selection` (#256).
  var heldDocument: DocumentID? { history.current?.id }

  private(set) var scrollRequest: ScrollRequest? {
    didSet {
      // A jump waited on is done once the reader has recorded it, which replaces
      // it with the request to scroll there, or once anything else replaces it
      // before the reader got to it.
      if let waiting = jumpWaiter, waiting.request != scrollRequest {
        jumpWaiter = nil
        waiting.done()
      }
    }
  }

  /// Whoever waits for the unrecorded jump requested last: a script, whose next
  /// command must find the jump in the history (#482).
  @ObservationIgnored private var jumpWaiter: (request: ScrollRequest, done: () -> Void)?

  var canGoBack: Bool { history.canGoBack }
  var canGoForward: Bool { history.canGoForward }
  /// Where Back returns to, straight after a jump within the document on screen.
  var returnOffer: HistoryEntry? { history.returnOffer }

  func settleReturnOffer() {
    history.settleReturnOffer()
  }

  // MARK: - Navigation

  /// A link from outside the current document: the sidebar, a deep link, a citation
  /// in the prose, or Go to RFC.
  func open(_ link: RFCLink, in index: RFCIndex?) {
    let id = Self.resolved(link.id, in: index)
    // A place in the document on screen is a jump within it, which the reader
    // resolves: an anchor may name nothing in its body, as the RFC Editor's
    // `#page-12` doesn't, or an entry the reader shows rather than scrolls to (#276),
    // and only the reader can tell a section's number from its anchor (#482). An
    // anchor leaves the list as it is.
    if let place = link.place, id == selection {
      jump(toSection: place)
      guard link.section != nil else { return }
    } else {
      go(to: HistoryEntry(id: id, section: link.place))
    }
    // As before the split: an explicit open reveals the document in the list,
    // which a narrowed filter may be hiding.
    sidebarSelection = .all
  }

  func open(_ id: DocumentID, section: String? = nil, in index: RFCIndex?) {
    open(RFCLink(id: id, section: section), in: index)
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

  /// A row picked in the document list.
  ///
  /// Unlike `open`, it leaves the filter alone. The row is in the list the reader
  /// is looking at by construction, so a narrowed filter cannot be hiding it, and
  /// resetting to `.all` would swap the Bookmarks list they were working in for
  /// the whole library with that one row highlighted somewhere inside it.
  ///
  /// A series row, which Bookmarks and Recently Read can show (#321), opens its
  /// first member RFC, as `open` does: the series has no document of its own.
  func select(_ id: DocumentID) {
    go(to: HistoryEntry(id: Self.resolved(id, in: library.index)))
  }

  /// A BCP, STD or FYI as the RFC it opens: its first member.
  private static func resolved(_ id: DocumentID, in index: RFCIndex?) -> DocumentID {
    guard id.series != .rfc, let first = index?.series(id)?.members.first else { return id }
    return first
  }

  /// A jump within the document already open — a section link in the prose, a row
  /// in the table of contents, or `jump to section`. Handed to the reader, which
  /// records it through `recordJump(to:in:)` where its document holds the place.
  /// `whenSettled` runs once it has, or once the reader has done what else it will
  /// with the place: after the document loads, if it is still loading.
  func jump(toSection section: String, whenSettled done: @escaping () -> Void = {}) {
    guard selection != nil else {
      done()
      return
    }
    let request = ScrollRequest(section: section, isUnrecorded: true)
    scrollRequest = request
    jumpWaiter = (request, done)
  }

  /// The reader has done what it will with `request`, where that recorded nothing:
  /// a bibliography entry shown, a place the document does not hold, or a document
  /// that failed to load.
  func settle(_ request: ScrollRequest) {
    guard let waiting = jumpWaiter, waiting.request == request else { return }
    jumpWaiter = nil
    waiting.done()
  }

  /// A place the document on screen holds: its own history entry, so Back undoes
  /// it, unless the reader is already there. Compared in `places`' spelling, so a
  /// section's number and its anchor are one place (#482).
  func recordJump(to section: String, in places: DocumentPlaces, animated: Bool = true) {
    guard let id = selection else { return }
    go(to: HistoryEntry(id: id, section: section), in: places, animated: animated)
  }

  func goBack() {
    guard let place = history.goBack(leaving: visiblePosition) else { return }
    arrive(at: place)
  }

  func goForward() {
    guard let place = history.goForward(leaving: visiblePosition) else { return }
    arrive(at: place)
  }

  private func go(
    to place: HistoryEntry, in places: DocumentPlaces? = nil, animated: Bool = true
  ) {
    let reopening = history.shown == nil
    guard let place = history.go(to: place, leaving: visiblePosition, in: places) else {
      // The hidden document reopened from its row: nowhere to move, and nothing to
      // scroll to. The last request is an earlier arrival's, and the reader made
      // again for the document took it over its reading position (#508). A reader
      // still on screen keeps its own, which may be a jump a script waits on.
      if reopening { scrollRequest = nil }
      return
    }
    arrive(at: place, animated: animated)
  }

  private func arrive(at place: HistoryEntry, animated: Bool = true) {
    scrollRequest = place.section.map { ScrollRequest(section: $0, isAnimated: animated) }
    visiblePosition = place.section
  }

  // MARK: - Across launches

  /// What this tab keeps across launches (#155), with its reader's inspector tab.
  func snapshot(inspectorTab: InspectorTab) -> SceneSnapshot {
    SceneSnapshot(history: history.snapshot(), filter: filter, inspectorTab: inspectorTab.rawValue)
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
}
