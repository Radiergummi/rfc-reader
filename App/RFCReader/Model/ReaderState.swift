import Foundation
import Observation
import RFCKit
import RFCReaderKit

/// What this window's reader is showing, for the parts of the window that are not
/// inside it.
///
/// All of this was `@State` on `DocumentView` while the reader, its toolbar and its
/// contents panel were one SwiftUI view. On macOS they are three: the toolbar is an
/// `NSToolbar` owned by the window, and the panel is its own `NSSplitViewItem` with
/// its own hosting controller. Views in different hosting controllers share nothing,
/// so the three meet here.
///
/// One per window, like `NavigationModel` — two tabs show two documents. iOS keeps
/// the single view tree, and holds one of these too rather than carrying a second
/// arrangement of the same state.
@Observable
final class ReaderState {
  /// Only the sections the storage actually holds; see `DocumentView.rebuild()`.
  var sections: [RFCKit.Section] = []
  var groups: [ReferenceGroup] = []
  /// Every BCP 14 requirement the document states, extracted once per document by
  /// `DocumentView` (#180): nil until it has been, which is after the body shows.
  var requirements: [Requirement]?
  /// What the open RFC can be saved as: PDF, and its grammar where it has one
  /// (#185). Set once the document has loaded.
  var exportFormats: [ExportFormat] = [.pdf]
  /// The window's reading mode and the sections it has expanded in place (#698). The
  /// mode stays from one document to the next; what was expanded does not.
  var folding = Folding() {
    didSet {
      // An entry revealed in one section's references is done with once the focus
      // moves: left, it would keep the next section's list the whole bibliography.
      if folding.focused != oldValue.focused { revealedReference = nil }
    }
  }
  /// What folding needs of the document on screen, for Next and Previous Section.
  var foldingIndex: FoldingIndex?
  /// In Focus, the References tab's groups with only what the focused section cites
  /// (#699); nil out of Focus, and for a section that cites nothing.
  var focusGroups: [ReferenceGroup]?

  /// Next Section and Previous Section, in Focus (#699). The reader's line goes to
  /// the new section's heading, which the text view does for any change of focus.
  func stepFocus(_ step: Folding.FocusStep) {
    guard let foldingIndex, let stepped = folding.focusing(step, in: foldingIndex) else { return }
    folding = stepped
  }

  /// Whether Next or Previous Section has somewhere to go.
  func canStepFocus(_ step: Folding.FocusStep) -> Bool {
    guard let foldingIndex else { return false }
    return folding.focusing(step, in: foldingIndex) != nil
  }
  /// What the Info pane shows, derived once per document by `DocumentView` (#25).
  var info: DocumentInfo?
  /// Which pane the inspector shows: the document's navigation, or what is known
  /// about it. Each has its own toolbar button, and they share the one slot beside
  /// the reader, as Pages' Format and Document do (`InspectorPane`).
  var pane: InspectorPane = .navigation
  /// Which tab the navigation pane is showing. The contents and references are both
  /// ways of navigating the document, so they share one pane.
  var tab: InspectorTab = .contents

  /// The anchor the reader is looking at: the contents' highlight.
  var currentAnchor: String?
  /// The same place as a section's `place` — its number, or `appendix-1` for an
  /// appendix numbered like a section (#429) — for the citation and the section link.
  /// Resolved by `DocumentView`, which has the document — rather than handing the
  /// document itself to a toolbar item that needs one string from it.
  var currentSection: String?

  /// Whether the document's body is here: what the toolbar title, printing and
  /// export need. The panel asks `canDescribe` instead.
  var hasDocument = false
  /// Whether the body is still on its way, from `DocumentSession`'s load state:
  /// without it, the navigation pane shows progress while this holds and says the
  /// document has not loaded once it does not (#325).
  var isLoading = false

  /// Whether there is anything to describe: the index's entry, which `DocumentView`
  /// derives as `info` the moment a document starts loading, or its body. The panel
  /// opens on it, so a document that is still loading, or failed to load or was
  /// offline, still has its Info (#325), and an open panel stays open from one
  /// document to the next.
  var canDescribe: Bool {
    InspectorPane.hasContent(.info, hasBody: hasDocument, isDescribed: info != nil)
  }

  /// Whether the reader's text has a selection: Edit ▸ Copy as Quote is grayed out
  /// without one, as Copy is (#186). Reported by the text view's coordinator.
  var hasSelection = false

  /// A document read beside this one, scrolling with it (#187); nil when it is
  /// read alone. Only the window's own reader has one: the reader beside it is
  /// `SideBySide`'s, and has only the coupling.
  var sideBySide: SideBySide?
  /// The side-by-side reading this reader scrolls in, whichever side it is.
  var coupling: ScrollCoupling?

  /// Opens `other` beside the document read, if one of the two obsoletes the other.
  func compare(_ metadata: RFCMetadata, with other: DocumentID, library: LibraryModel) {
    guard let pair = SideBySidePair(reading: metadata, with: other) else { return }
    guard sideBySide?.pair != pair else { return }
    let reading = SideBySide(pair, library: library)
    sideBySide = reading
    coupling = reading.coupling
    reading.align(library: library)
  }

  /// Closes the document beside, and reads this one alone again.
  func endComparison() {
    sideBySide = nil
    coupling = nil
  }

  /// The title the document gives itself, for the one caller the index cannot
  /// serve: `DocumentActions.bookmarkTitle` when `library.metadata` has nothing.
  /// Here for the same reason `currentSection` is — the toolbar needs one string
  /// out of a document it is not inside, and handing it the document instead would
  /// be a far larger thing to share for it.
  var documentTitle: String?

  /// The Internet-Draft the document was published from, for the More menu. Here
  /// for the same reason `documentTitle` is.
  var precedingDraft: URL?

  /// The 72-column original instead of the rendered document. Toolbar state, read
  /// by the reader.
  var showOriginal = false {
    didSet { titleOwnership.showsOriginal = showOriginal }
  }

  /// Why the RFC is read as its PDF or PostScript original, if it is (#207). Set by
  /// the reader as the load starts and ends, and again when the index arrives. A
  /// scan's page shows the header the index gives, so its title stays out of the
  /// toolbar.
  var publishedOriginal: PublishedOriginalPage.Status? {
    didSet { titleOwnership.showsPublishedOriginal = publishedOriginal?.kind == .scan }
  }

  /// Whether Print and Export have something to offer: a document on screen, read
  /// as its text.
  var offersPrintAndExport: Bool {
    PublishedOriginalPage.offersPrintAndExport(
      hasDocument: hasDocument, kind: publishedOriginal?.kind)
  }

  /// Who says how far the title has come into the toolbar, and the one place its
  /// state is pushed from (#281); see `ToolbarTitleOwnership`.
  @ObservationIgnored private var titleOwnership = ToolbarTitleOwnership() {
    didSet {
      if titleOwnership.state != oldValue.state { updateToolbarTitle(titleOwnership.state) }
    }
  }

  /// A document starts loading, and its header is on its way.
  func documentStartsLoading() {
    titleOwnership.beginLoading()
  }

  /// The document failed to load, and no header is coming.
  func documentFailedToLoad() {
    titleOwnership.failLoading()
  }

  /// The reader with a header on screen says where the title is, as it scrolls.
  func report(title state: ToolbarTitleState, from reader: AnyObject) {
    titleOwnership.report(state, from: ObjectIdentifier(reader))
  }

  /// That reader has gone away, and what it said goes with it.
  func releaseTitle(from reader: AnyObject) {
    titleOwnership.release(from: ObjectIdentifier(reader))
  }

  /// Moves the document's title into the toolbar, from 0 to 1 as its heading
  /// scrolls away, and names the section being read under it; see
  /// `ToolbarTitleReveal` and `RunningHeading`. The toolbar installs itself here.
  ///
  /// A callback, not a property the toolbar observes: it is called on every
  /// scroll tick the title moves in, and observation delivers a change a run-loop
  /// turn later, which leaves a title coupled to the scroll trailing behind it.
  ///
  /// Told the state at once when installed: only a change is pushed after that.
  @ObservationIgnored var updateToolbarTitle: (ToolbarTitleState) -> Void = { _ in } {
    didSet { updateToolbarTitle(titleOwnership.state) }
  }

  /// A request to show one bibliography entry in the panel.
  ///
  /// Not a bare `String?`, for the reason `NavigationModel.ScrollRequest` is not:
  /// the same citation clicked twice must reveal its entry twice.
  struct RevealedReference: Equatable {
    let anchor: String
    private let issue = UUID()
  }

  /// The entry a citation last asked the panel to show; see `reveal(reference:)`.
  var revealedReference: RevealedReference?

  /// Opens the panel. The panel is the window's split item on macOS and a SwiftUI
  /// presentation on iOS, so whichever owns it installs this, the way the toolbar
  /// installs `updateToolbarTitle`.
  @ObservationIgnored var openPanel: () -> Void = {}

  /// Shows a bibliography entry: what a citation of anything but an RFC links to
  /// (`DocumentTextBuilder.referenceScheme`).
  func reveal(reference anchor: String) {
    pane = .navigation
    tab = .references
    revealedReference = RevealedReference(anchor: anchor)
    openPanel()
  }

  /// Shows a tab of the navigation pane, opening the panel: what an App Intent asks
  /// for beside a document (#192).
  func show(_ tab: InspectorTab) {
    pane = .navigation
    self.tab = tab
    openPanel()
  }

  func clear() {
    titleOwnership.close()
    sections = []
    groups = []
    requirements = nil
    exportFormats = [.pdf]
    folding.expanded = []
    folding.openAsides = []
    folding.focused = nil
    foldingIndex = nil
    focusGroups = nil
    info = nil
    revealedReference = nil
    currentAnchor = nil
    currentSection = nil
    hasDocument = false
    publishedOriginal = nil
    isLoading = false
    hasSelection = false
    documentTitle = nil
    precedingDraft = nil
  }
}
