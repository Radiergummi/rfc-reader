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
  /// The same place as a section number, for the citation and the section link.
  /// Resolved by `DocumentView`, which has the document — rather than handing the
  /// document itself to a toolbar item that needs one string from it.
  var currentSection: String?

  /// Whether there is anything to describe. The panel draws nothing without it.
  var hasDocument = false

  /// Whether the reader's text has a selection: Edit ▸ Copy as Quote is grayed out
  /// without one, as Copy is (#186). Reported by the text view's coordinator.
  var hasSelection = false

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
  var showOriginal = false

  /// Moves the document's title into the toolbar, from 0 to 1 as its heading
  /// scrolls away, and names the section being read under it; see
  /// `ToolbarTitleReveal` and `RunningHeading`. The toolbar installs itself here.
  ///
  /// A callback, not a property the toolbar observes: it is called on every
  /// scroll tick the title moves in, and observation delivers a change a run-loop
  /// turn later, which leaves a title coupled to the scroll trailing behind it.
  @ObservationIgnored var updateToolbarTitle: (ToolbarTitleState) -> Void = { _ in }

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

  func clear() {
    // The next document starts at its top, under its own header, until the reader
    // reports otherwise.
    updateToolbarTitle(.hidden)
    sections = []
    groups = []
    requirements = nil
    info = nil
    revealedReference = nil
    currentAnchor = nil
    currentSection = nil
    hasDocument = false
    hasSelection = false
    documentTitle = nil
    precedingDraft = nil
  }
}
