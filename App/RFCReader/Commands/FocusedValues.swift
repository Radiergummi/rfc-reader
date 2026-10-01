import SwiftUI

// Published by `ContentView` and read by `DocumentCommands`, both of which are
// iOS-only now: on macOS the menu finds its target through `ActiveReaderWindow`,
// because focused values do not resolve out of a hosted root.
#if !os(macOS)
  struct OpenDocumentActionKey: FocusedValueKey {
    typealias Value = () -> Void
  }

  struct NavigationModelKey: FocusedValueKey {
    typealias Value = NavigationModel
  }

  struct ReaderStateKey: FocusedValueKey {
    typealias Value = ReaderState
  }

  extension FocusedValues {
    var openDocumentAction: OpenDocumentActionKey.Value? {
      get { self[OpenDocumentActionKey.self] }
      set { self[OpenDocumentActionKey.self] = newValue }
    }

    var navigationModel: NavigationModel? {
      get { self[NavigationModelKey.self] }
      set { self[NavigationModelKey.self] = newValue }
    }

    var readerState: ReaderState? {
      get { self[ReaderStateKey.self] }
      set { self[ReaderStateKey.self] = newValue }
    }
  }
#endif
