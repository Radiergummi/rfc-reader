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
@MainActor
final class ReaderState {
  /// Only the sections the storage actually holds; see `DocumentView.rebuild()`.
  var sections: [RFCKit.Section] = []
  var groups: [ReferenceGroup] = []
  /// Which of the two the panel is showing. Both are ways of navigating the
  /// document, so they share one panel rather than competing for the toolbar.
  var tab: InspectorTab = .contents

  /// The anchor the reader is looking at: the contents' highlight.
  var currentAnchor: String?
  /// The same place as a section number, for the citation and the section link.
  /// Resolved by `DocumentView`, which has the document — rather than handing the
  /// document itself to a toolbar item that needs one string from it.
  var currentSection: String?

  /// Whether there is anything to describe. The panel draws nothing without it.
  var hasDocument = false

  /// The title the document gives itself, for the one caller the index cannot
  /// serve: `DocumentActions.bookmarkTitle` when `library.metadata` has nothing.
  /// Here for the same reason `currentSection` is — the toolbar needs one string
  /// out of a document it is not inside, and handing it the document instead would
  /// be a far larger thing to share for it.
  var documentTitle: String?

  /// The 72-column original instead of the rendered document. Toolbar state, read
  /// by the reader.
  var showOriginal = false

  func clear() {
    sections = []
    groups = []
    currentAnchor = nil
    currentSection = nil
    hasDocument = false
    documentTitle = nil
  }
}
