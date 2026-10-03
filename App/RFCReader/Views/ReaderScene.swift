import RFCReaderKit
import SwiftUI

/// What a reader scene does in SwiftUI on both platforms: iOS's `ContentView` and
/// the Mac's `ReaderHost` apply it to what they show.
///
/// Only the SwiftUI part. The rest of a scene's life is each platform's own: iOS
/// registers the tab with the library as the view appears and hands the models
/// down the environment, where the Mac's `ReaderWindowController` registers it as
/// the window is made and hands every hosted root its models explicitly, a hosted
/// root being outside the environment chain.
struct ReaderScene: ViewModifier {
  let library: LibraryModel
  @Bindable var navigation: NavigationModel
  let reader: ReaderState

  func body(content: Content) -> some View {
    content
      // Any navigation in this tab makes it the most recently used, where an
      // untargeted deep link lands when no tab is preferred over it -- on macOS
      // `LibraryModel.route` prefers the tab of the window that was key last.
      .onChange(of: navigation.selection) {
        library.activate(navigation)
        // A deselected row leaves nothing on screen, and the panel and the toolbar
        // must not go on describing the document that was.
        if navigation.selection == nil { reader.clear() }
      }
      // Declared by a view that is in the window, as a presentation has to be.
      .sheet(item: $navigation.collectionEditor) { mode in
        CollectionEditorSheet(mode: mode)
      }
      .sheet(item: $navigation.readingPath) { request in
        ReadingPathSheet(root: request.root)
      }
      #if os(iOS)
        // For the reader header, which cannot present on iOS; see `GlossaryPresentation`.
        .sheet(item: $navigation.glossaryTerm) { term in
          GlossarySheet(term: term)
        }
      #endif
  }
}

extension View {
  func readerScene(library: LibraryModel, navigation: NavigationModel, reader: ReaderState)
    -> some View
  {
    modifier(ReaderScene(library: library, navigation: navigation, reader: reader))
  }
}
