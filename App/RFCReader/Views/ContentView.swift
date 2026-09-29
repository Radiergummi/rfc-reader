import RFCKit
import RFCReaderKit
import SwiftData
import SwiftUI

// macOS has no `WindowGroup`, so nothing on that platform instantiates this view:
// the window's content is an `NSSplitViewController` built by
// `ReaderWindowController`, because only a split view controller that is the
// window's own root gets AppKit to confine the tab bar and split the toolbar.
#if !os(macOS)
  struct ContentView: View {
    @Environment(LibraryModel.self) private var library
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var columnVisibility = NavigationSplitViewVisibility.all
    /// This scene's own navigation state. `@State` here is what makes a tab a tab:
    /// every window and tab instantiates `ContentView` afresh, so each gets its own
    /// selection, filter, search text and back/forward stack. Shared library state —
    /// the index, the cache — stays on the environment's `LibraryModel`.
    @State private var navigation = NavigationModel(library: .shared)
    /// What the reader is showing, shared with the panel. One per scene, for the same
    /// reason `NavigationModel` is.
    @State private var reader = ReaderState()
    /// The link this window was asked to open (#158), held until it has appeared.
    @State private var requestedLink: RFCLink?
    @State private var hasAppeared = false
    /// The one-time warning that bookmarks this session will not be kept (#152).
    @State private var showsStoreWarning = false

    /// Short enough to survive a tab: the document's designation, not its title.
    private var windowTitle: String {
      navigation.selection?.displayName ?? library.title(for: navigation.filter)
    }

    var body: some View {
      @Bindable var navigation = navigation
      NavigationSplitView(columnVisibility: $columnVisibility) {
        SidebarView()
          .navigationSplitViewColumnWidth(min: 200, ideal: 240)
      } content: {
        RFCListView()
          .navigationSplitViewColumnWidth(min: 280, ideal: 360)
      } detail: {
        // The detail column takes no `navigationSplitViewColumnWidth` — the
        // modifier applies to the sidebar and content columns only — so the
        // reader's floor comes from its own frame, inside `DocumentView`. Put
        // here it would bound the reader and its panel together, which is how the
        // contents panel came to leave the text 190 pt wide.
        if let selection = navigation.selection {
          DocumentView(id: selection)
            .id(selection)
        } else {
          EmptyDetailView()
        }
      }
      // The scene's title, for the app switcher and iPad's window controls. It
      // reaches no column's bar: each column titles itself, the list included
      // (#246).
      .navigationTitle(windowTitle)
      // A window asked for with a link (#158): addressed to this scene, so it opens
      // here rather than going through `route`, which picks a scene for a link that
      // names none.
      //
      // Held until the scene has appeared if it comes first: appearing clears a
      // compact sidebar's selection, which would otherwise undo the open and leave
      // the new window on the sidebar rather than the document.
      .onContinueUserActivity(SceneRequest.activityType) { activity in
        guard let link = SceneRequest.link(from: activity.userInfo) else { return }
        if hasAppeared {
          navigation.open(link, in: library.index)
        } else {
          requestedLink = link
        }
      }
      // On the split view rather than on `DocumentView`: macOS gives the detail
      // column no leading toolbar slot — a `.navigation` item declared down there is
      // silently dropped — and scene-level navigation belongs beside the sidebar
      // toggle anyway, not with the document's own actions.
      //
      // Always present, dimmed when there is nowhere to go, as Safari does. A pair
      // that appears and vanishes with the history shifts everything beside it.
      //
      // Only beside other columns, though. In a single column, as on an iPhone,
      // it sat beside the system back button and took the room the reader's title
      // needed (#245); the system button leaves the document there, and "Back to
      // §…" returns from a jump within it (#254).
      .toolbar {
        if horizontalSizeClass == .regular {
          ToolbarItem(placement: .navigation) {
            ControlGroup {
              HistoryButtons()
            }
            .controlGroupStyle(.navigation)
          }
        }
      }
      .onAppear {
        // Collapsed, the sidebar is a list of push rows, and a filter selected
        // before anything was tapped reads as a tap left behind. The list still
        // lists it: `filter` keeps its value. Before registering, which may open a
        // waiting link and reveal it in the list.
        if horizontalSizeClass == .compact { navigation.sidebarSelection = nil }
        library.register(navigation)
        hasAppeared = true
        if let link = requestedLink {
          requestedLink = nil
          navigation.open(link, in: library.index)
        }
      }
      // Side by side, the sidebar shows which filter feeds the list.
      .onChange(of: horizontalSizeClass) {
        if horizontalSizeClass == .regular, navigation.sidebarSelection == nil {
          navigation.sidebarSelection = navigation.filter
        }
      }
      .onDisappear { library.unregister(navigation) }
      // Once, when the bookmarks store fell back to memory (#152). Continue only:
      // an iOS app does not quit itself.
      .onAppear {
        if AppData.claimStoreWarning() {
          showsStoreWarning = true
        }
      }
      .alert(AppData.storeWarning.title, isPresented: $showsStoreWarning) {
        Button("Continue", role: .cancel) {}
      } message: {
        Text(AppData.storeWarning.message)
      }
      // Any navigation in this tab makes it the one an untargeted deep link lands in.
      .onChange(of: navigation.selection) {
        library.activate(navigation)
        // Nothing on screen: the panel must not go on describing the document
        // that was.
        if navigation.selection == nil { reader.clear() }
      }
      .sheet(isPresented: $navigation.isShowingGoToSheet) {
        GoToDocumentSheet()
      }
      .sheet(item: $navigation.collectionEditor) { mode in
        CollectionEditorSheet(mode: mode)
      }
      .focusedSceneValue(\.openDocumentAction) {
        navigation.isShowingGoToSheet = true
      }
      .focusedSceneValue(\.navigationModel, navigation)
      // Outermost, and it has to be: an environment value reaches what is *inside*
      // the modifier that sets it, and a presentation is the content of the
      // modifier that presents it. Written on the split view, this covered the
      // three columns and missed the sheet above it — so ⌘L crashed the app on
      // `GoToDocumentSheet`'s `@Environment(NavigationModel.self)` lookup, which is
      // a runtime trap with no compile-time warning. Out here it covers both, and
      // the next presentation added to this view as well.
      .environment(navigation)
      .environment(reader)
    }
  }
#endif

struct EmptyDetailView: View {
  @Environment(NavigationModel.self) private var navigation

  var body: some View {
    ContentUnavailableView {
      Label("Pick an RFC", systemImage: "doc.text.magnifyingglass")
    } description: {
      Text("Browse the sidebar, search, or jump straight to a number.")
    } actions: {
      Button("Go to RFC…") { navigation.isShowingGoToSheet = true }
        .keyboardShortcut("l", modifiers: .command)
    }
  }
}

#if !os(macOS)
  /// Command-L style jump: accepts a number, `RFC 9110`, `BCP 14`, or any RFC Editor / Datatracker URL.
  ///
  /// iOS only. The Mac has `QuickOpenPalette`, because a form in a sheet is the right
  /// shape for a phone and the wrong one for ⌘L on a desktop (#26).
  struct GoToDocumentSheet: View {
    @Environment(LibraryModel.self) private var library
    @Environment(NavigationModel.self) private var navigation
    @Environment(\.dismiss) private var dismiss
    @State private var input = ""
    @FocusState private var focused: Bool

    private var resolved: RFCLink? {
      DocumentReference.link(from: input)
    }

    var body: some View {
      NavigationStack {
        Form {
          TextField("RFC number or link", text: $input)
            .focused($focused)
            .onSubmit(open)
            .keyboardType(.numbersAndPunctuation)
            .textInputAutocapitalization(.never)
          status
        }
        .navigationTitle("Go to RFC")
        .toolbar {
          ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
          ToolbarItem(placement: .confirmationAction) {
            Button("Open", action: open).disabled(resolved == nil)
          }
        }
      }
      .onAppear { focused = true }
    }

    /// What the typed text resolves to, or what it would take to resolve: the one
    /// line under the field that turns a blind text box into something that tells
    /// the reader whether it understood them.
    @ViewBuilder
    private var status: some View {
      if let link = resolved, let metadata = library.metadata(link.id) {
        Text("\(link.id.displayName) — \(metadata.title)")
      } else if !input.isEmpty {
        Text("Not something I recognise as an RFC.")
      } else {
        Text("A number, RFC 9110, BCP 14, or an rfc-editor.org link.")
      }
    }

    private func open() {
      guard let link = resolved else { return }
      library.open(link, activation: .current, in: navigation)
      dismiss()
    }
  }
#endif
