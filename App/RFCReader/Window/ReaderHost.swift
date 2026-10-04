#if os(macOS)
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
          DocumentView(id: selection)
            .id(selection)
            // Faded only when the change is animated: following a document preview
            // (`RFCTextViewCoordinator.documentCrossFade`). Every other open cuts.
            .transition(.opacity)
        } else {
          EmptyDetailView()
        }
      }
      .readerScene(library: library, navigation: navigation, reader: reader)
    }
  }
#endif
