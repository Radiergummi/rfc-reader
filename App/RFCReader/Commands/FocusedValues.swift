import SwiftUI

// Published by `ContentView` and read by `DocumentCommands` and `HelpCommands`, on iOS only: on macOS
// the menu finds its target through `ActiveReaderWindow`, because focused values do
// not resolve out of a hosted root.
#if !os(macOS)
  struct OpenDocumentActionKey: FocusedValueKey {
    typealias Value = () -> Void
  }

  struct ShowHelpActionKey: FocusedValueKey {
    typealias Value = () -> Void
  }

  struct NavigationModelKey: FocusedValueKey {
    typealias Value = NavigationModel
  }

  struct ReaderStateKey: FocusedValueKey {
    typealias Value = ReaderState
  }

  struct SearchLibraryActionKey: FocusedValueKey {
    typealias Value = () -> Void
  }

  struct ShowSidebarActionKey: FocusedValueKey {
    typealias Value = () -> Void
  }

  struct ExportDocumentActionKey: FocusedValueKey {
    typealias Value = (_ section: String?) -> Void
  }

  struct PrintDocumentActionKey: FocusedValueKey {
    typealias Value = () -> Void
  }

  struct ShowsInspectorKey: FocusedValueKey {
    typealias Value = Binding<Bool>
  }

  extension FocusedValues {
    var openDocumentAction: OpenDocumentActionKey.Value? {
      get { self[OpenDocumentActionKey.self] }
      set { self[OpenDocumentActionKey.self] = newValue }
    }

    /// Presents the help in the focused scene (#780).
    var showHelpAction: ShowHelpActionKey.Value? {
      get { self[ShowHelpActionKey.self] }
      set { self[ShowHelpActionKey.self] = newValue }
    }

    var navigationModel: NavigationModel? {
      get { self[NavigationModelKey.self] }
      set { self[NavigationModelKey.self] = newValue }
    }

    var readerState: ReaderState? {
      get { self[ReaderStateKey.self] }
      set { self[ReaderStateKey.self] = newValue }
    }

    /// Puts the focus in the sidebar's search field (#764); nil where the sidebar
    /// cannot be shown.
    var searchLibraryAction: SearchLibraryActionKey.Value? {
      get { self[SearchLibraryActionKey.self] }
      set { self[SearchLibraryActionKey.self] = newValue }
    }

    /// Shows the sidebar beside the other columns (#1063), as New Collection… and
    /// Save as Collection… do first; nil in a single column, where it is where Back
    /// leads.
    var showSidebarAction: ShowSidebarActionKey.Value? {
      get { self[ShowSidebarActionKey.self] }
      set { self[ShowSidebarActionKey.self] = newValue }
    }

    /// File ▸ Export… and Export Current Section… (#764): the formats offered, then
    /// Save to Files, for the whole document or the section with this anchor. The
    /// reader on screen's, which holds its `DocumentOutput`.
    var exportDocumentAction: ExportDocumentActionKey.Value? {
      get { self[ExportDocumentActionKey.self] }
      set { self[ExportDocumentActionKey.self] = newValue }
    }

    /// File ▸ Print… (#764): the reader on screen's print sheet.
    var printDocumentAction: PrintDocumentActionKey.Value? {
      get { self[PrintDocumentActionKey.self] }
      set { self[PrintDocumentActionKey.self] = newValue }
    }

    /// Whether the scene's panel is open, for View ▸ Show Contents and Show Info
    /// (#764).
    var showsInspector: ShowsInspectorKey.Value? {
      get { self[ShowsInspectorKey.self] }
      set { self[ShowsInspectorKey.self] = newValue }
    }
  }
#endif
