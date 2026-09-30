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
  /// The query the list, its count and the sidebar's results are computed for: the
  /// search text, trimmed, once typing pauses and its hits are ready (#124). Until
  /// then the list keeps the results it has, as Mail and Finder do.
  private(set) var appliedQuery = ""
  @ObservationIgnored private var pendingSearch: Task<Void, Never>?
  /// The iOS list's view options, for this tab (#348).
  var listOptions = ListOptions()
  var isShowingGoToSheet = false
  /// The collection sheet on show, if any: creating one — perhaps to add a document
  /// to — or editing one (#349). On the model rather than a view's state so the
  /// sidebar, the Add to Collection menus and the Mac's File menu can all ask for
  /// it, and the one view that presents it is in the window.
  var collectionEditor: CollectionEditorMode?

  /// The library the list is computed from, and which the inputs below are taken
  /// from on entering a filter.
  @ObservationIgnored private let library: LibraryModel

  init(library: LibraryModel) {
    self.library = library
  }

  /// The Recently Read order, taken once when the filter is entered.
  ///
  /// Not live: opening or leaving a document writes its `updatedAt`, so an order
  /// kept in step with that re-sorted the list the click came from — the row just
  /// left jumped to the top and everything below it shifted down a place. Taken on
  /// entering instead, the order is whatever it was on arrival and stays put while
  /// it is being read through; coming back to the filter takes a fresh one, the
  /// same way `downloaded` beside it does.
  private(set) var recentOrder: [Int] = []
  /// The RFCs available offline, as of entering the filter.
  private(set) var downloaded: Set<Int> = []

  /// Takes the inputs a list is computed from on entering a filter.
  private func takeListInputs() {
    recentOrder = library.recentlyReadNumbers()
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
  private(set) var scrollRequest: ScrollRequest?

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
    var id = link.id
    // BCP/STD links open their first member RFC.
    if id.series != .rfc, let first = index?.series(id)?.members.first {
      id = first
    }
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
  /// field, or a search asked for with a click. The list still follows once the
  /// query's hits are ready.
  func applySearchWithoutPause() {
    followSearchText(pausing: false)
  }

  /// Sets the search text and applies it before returning, searching on the main
  /// actor: for a script, which reads the list straight after setting the text.
  func setSearchTextSynchronously(_ text: String) {
    searchText = text
    pendingSearch?.cancel()
    pendingSearch = nil
    appliedQuery = AppliedSearch.query(for: text)
  }

  /// Applies the search text as `AppliedSearch` says to: after a pause in typing,
  /// or at once when it is cleared.
  private func followSearchText(pausing: Bool) {
    pendingSearch?.cancel()
    pendingSearch = nil
    switch AppliedSearch.step(applying: searchText, over: appliedQuery, pausing: pausing) {
    case nil:
      // Typed back to the query on show: nothing is left to apply.
      return
    case .apply(let query):
      appliedQuery = query
    case .search(let query, let delay):
      pendingSearch = Task(name: "Apply search") { [library] in
        if delay > .zero {
          do {
            try await Task.sleep(for: delay)
          } catch {
            return
          }
        }
        await library.prepareSearch(query)
        guard !Task.isCancelled else { return }
        appliedQuery = query
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
  /// It also skips the BCP/STD resolution `open` does, because every row the list
  /// can emit is already an RFC: `LibraryModel.list` draws from `index.rfcs` and,
  /// for `.series`, from the members those entries resolve to. A list that could
  /// show a series row would have to come back through `open`.
  func select(_ id: DocumentID) {
    go(to: HistoryEntry(id: id))
  }

  /// A jump within the document already open — a section link in the prose, a row
  /// in the table of contents, or `jump to section`. Handed to the reader, which
  /// records it through `jump(toSection:in:)` where its document holds the place.
  func jump(toSection section: String) {
    guard selection != nil else { return }
    scrollRequest = ScrollRequest(section: section, isUnrecorded: true)
  }

  /// A place the document on screen holds: its own history entry, so Back undoes
  /// it, unless the reader is already there. Compared in `places`' spelling, so a
  /// section's number and its anchor are one place (#482).
  func jump(toSection section: String, in places: DocumentPlaces) {
    guard let id = selection else { return }
    go(to: HistoryEntry(id: id, section: section), in: places)
  }

  func goBack() {
    guard let place = history.goBack(leaving: visiblePosition) else { return }
    arrive(at: place)
  }

  func goForward() {
    guard let place = history.goForward(leaving: visiblePosition) else { return }
    arrive(at: place)
  }

  private func go(to place: HistoryEntry, in places: DocumentPlaces? = nil) {
    guard let place = history.go(to: place, leaving: visiblePosition, in: places) else { return }
    arrive(at: place)
  }

  private func arrive(at place: HistoryEntry) {
    scrollRequest = place.section.map { ScrollRequest(section: $0) }
    visiblePosition = place.section
  }
}
