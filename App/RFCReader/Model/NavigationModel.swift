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
  var searchText = ""
  var isShowingGoToSheet = false

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
  var returnOffer: Place? { history.returnOffer }

  func settleReturnOffer() {
    history.settleReturnOffer()
  }

  // MARK: - Navigation

  /// A link from outside the current document: the sidebar, a deep link, a citation
  /// in the prose, or the Go to RFC sheet.
  func open(_ link: RFCLink, in index: RFCIndex?) {
    var id = link.id
    // BCP/STD links open their first member RFC.
    if id.series != .rfc, let first = index?.series(id)?.members.first {
      id = first
    }
    go(to: Place(id: id, section: link.section))
    // As before the split: an explicit open reveals the document in the list,
    // which a narrowed filter may be hiding.
    sidebarSelection = .all
  }

  func open(_ id: DocumentID, section: String? = nil, in index: RFCIndex?) {
    open(RFCLink(id: id, section: section), in: index)
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
    go(to: Place(id: id))
  }

  /// A jump within the document already open — a section link in the prose, or a
  /// row in the table of contents. Its own history entry, so Back undoes it.
  func jump(toSection section: String) {
    guard let id = selection else { return }
    go(to: Place(id: id, section: section))
  }

  func goBack() {
    guard let place = history.goBack(leaving: visiblePosition) else { return }
    arrive(at: place)
  }

  func goForward() {
    guard let place = history.goForward(leaving: visiblePosition) else { return }
    arrive(at: place)
  }

  private func go(to place: Place) {
    let before = history.current
    history.go(to: place, leaving: visiblePosition)
    guard history.current != before else { return }
    arrive(at: place)
  }

  private func arrive(at place: Place) {
    scrollRequest = place.section.map { ScrollRequest(section: $0) }
    visiblePosition = place.section
  }
}
