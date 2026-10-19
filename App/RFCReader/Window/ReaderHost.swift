#if os(macOS)
  import RFCKit
  import SwiftUI

  /// What the detail column of `NavigationSplitView` used to hold, and the scene's
  /// SwiftUI part (`ReaderScene`): a presentation has to be declared by a view that
  /// is actually in the window, and there is no scene to declare it on.
  struct ReaderHost: View {
    @Environment(LibraryModel.self) private var library
    @Environment(NavigationModel.self) private var navigation
    @Environment(ReaderState.self) private var reader

    var body: some View {
      Group {
        if let selection = navigation.selection {
          // A BCP, STD or FYI shows its first member, once the index names it (#656).
          if let shown = library.documentShown(for: selection) {
            DocumentView(id: .rfc(shown), identity: .rfc(selection))
              // Made again when the RFC shown changes for the same selection, as an
              // index arriving after one that failed changes a series' (#656).
              .id([selection, shown])
              // Faded only when the change is animated: following a document preview
              // (`RFCTextViewCoordinator.documentCrossFade`). Every other open cuts.
              .transition(.opacity)
          } else {
            ProgressView("Loading \(selection.displayName)…")
              .frame(maxWidth: .infinity, maxHeight: .infinity)
          }
        } else if let draft = navigation.shownDraft {
          // A draft has no row to select (#728).
          DocumentView(id: .draft(draft))
            .id(draft)
            .transition(.opacity)
        } else {
          EmptyDetailView()
        }
      }
      .readerScene(library: library, navigation: navigation, reader: reader)
    }
  }
#endif
