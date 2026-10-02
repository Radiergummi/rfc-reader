import SwiftData
import SwiftUI

/// Everything a hosted root reads from the environment, as one value (#139).
///
/// A hosting controller sits outside every SwiftUI environment chain, so an
/// `@Environment(LibraryModel.self)` inside one that was not given the library is a
/// runtime trap with no compile-time warning. Every hosted root of the reader's is
/// therefore made with one of these and applies it with `readerEnvironment(_:)`, so
/// none of them can be given three of the four parts and not the fourth: the value
/// cannot be made without all of them. What the compiler cannot check is that a new
/// hosting controller applies it at all; one that hosts a view reading any of these
/// must, as every such host in `ReaderWindowController`, `ContentView`,
/// `RFCTextView` and `RFCTextViewCoordinator` does.
struct ReaderEnvironment {
  let library: LibraryModel
  /// The tab's own; see `NavigationModel`.
  let navigation: NavigationModel
  /// The window's own; see `ReaderState`.
  let reader: ReaderState
  /// The one container; see `AppData`.
  let container: ModelContainer

  /// The container is the library's, so it cannot be wired to another one.
  init(library: LibraryModel, navigation: NavigationModel, reader: ReaderState) {
    self.library = library
    self.navigation = navigation
    self.reader = reader
    container = library.container
  }
}

extension View {
  /// The whole of `environment`, for a hosted root's view.
  func readerEnvironment(_ environment: ReaderEnvironment) -> some View {
    self
      .environment(environment.library)
      .environment(environment.navigation)
      .environment(environment.reader)
      .modelContainer(environment.container)
  }
}
