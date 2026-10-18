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
    /// The scene's, which this view hands on to everything inside it with the tab's
    /// own state, as a `ReaderEnvironment` applied at the end of `body`.
    let library: LibraryModel
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @State private var columnVisibility = NavigationSplitViewVisibility.all
    /// The reader's panel, the tab's rather than each reader's, so that an open panel
    /// stays open from one reader in the stack to the next (#263).
    @State private var showsInspector = false
    /// This scene's own navigation state. `@State` here is what makes a tab a tab:
    /// every window and tab instantiates `ContentView` afresh, so each gets its own
    /// selection, filter, search text and back/forward stack. Shared library state —
    /// the index, the cache — stays on `LibraryModel`. `.shared` because a property
    /// initializer cannot read `library`: this is a composition root, where the
    /// app's state is made.
    @State private var navigation = NavigationModel(library: .shared)
    /// What the reader is showing, shared with the panel. One per scene, for the same
    /// reason `NavigationModel` is.
    @State private var reader = ReaderState()
    /// The link this window was asked to open (#158), held until it has appeared.
    @State private var requestedLink: RFCLink?
    @State private var hasAppeared = false
    /// This scene's `SceneSnapshot`, kept by the system with the scene (#155).
    @SceneStorage("scene") private var sceneSnapshot: Data?
    /// The one-time warning that bookmarks this session will not be kept (#152).
    @State private var showsStoreWarning = false
    /// The help, while Help in the menu bar has it on show (#780).
    @State private var helpTarget: HelpTarget?
    /// The reader's own text size, which ⌘= steps (#153).
    @AppStorage(ReaderPreferences.fontSizeKey) private var fontSize = ReaderPreferences
      .defaultFontSize

    /// Short enough to survive a tab: the document's designation, not its title.
    private var windowTitle: String {
      navigation.selection?.displayName ?? library.title(for: navigation.filter)
    }

    /// The scene's chrome, worked out here once and read by every view inside it
    /// that lays itself out by it (#257).
    private var chrome: SceneChrome {
      SceneChrome(horizontal: horizontalSizeClass, vertical: verticalSizeClass)
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
        //
        // A stack of readers, which a citation of another RFC pushes onto (#263).
        ReaderStack(showsInspector: $showsInspector)
      }
      // The panel, a column beside the reader where there is room for one; in
      // compact width the reader on top presents it as a sheet (`IOSDocumentChrome`).
      // Here rather than on a reader or on the stack, both measured (#679): on the
      // root view of a `NavigationStack`, `.inspector` takes away that view's whole
      // navigation bar, its title and its toolbar; on the stack, it stops the stack
      // from popping when its path is shortened, so Back left the reader on screen.
      .inspector(isPresented: chrome.isCollapsed ? .constant(false) : $showsInspector) {
        PanelHost(
          isPresented: $showsInspector, closesAfterChoice: false,
          readingPathAfterClosing: .constant(nil)
        )
        .inspectorColumnWidth(min: 260, ideal: 320)
      }
      .environment(\.sceneChrome, chrome)
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
          navigation.open(link)
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
        // Once, before anything else moves the tab: where it was when the app last
        // ran (#155). A link it was asked to open comes after, and wins.
        if !hasAppeared, let data = sceneSnapshot,
          let snapshot = SceneSnapshot.decoded(from: data)
        {
          navigation.restore(snapshot, into: reader)
        }
        // Collapsed, the sidebar is a list of push rows, and a filter selected
        // before anything was tapped reads as a tap left behind. The list still
        // lists it: `filter` keeps its value. Before registering, which may open a
        // waiting link and reveal it in the list.
        if chrome.isCollapsed { navigation.sidebarSelection = nil }
        library.register(navigation)
        hasAppeared = true
        if let link = requestedLink {
          requestedLink = nil
          navigation.open(link)
        }
      }
      // Side by side, the sidebar shows which filter feeds the list.
      .onChange(of: horizontalSizeClass) {
        if horizontalSizeClass == .regular, navigation.sidebarSelection == nil {
          navigation.sidebarSelection = navigation.filter
        }
      }
      // Written as the tab changes: SwiftUI keeps the scene's storage, and writing it
      // costs a comparison and an encode.
      .onChange(of: navigation.snapshot(inspectorTab: reader.tab)) { _, snapshot in
        guard hasAppeared else { return }
        sceneSnapshot = snapshot.encoded()
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
      .readerScene(library: library, navigation: navigation, reader: reader)
      .sheet(isPresented: $navigation.isShowingGoToSheet) {
        GoToDocumentSheet(library: library, navigation: navigation)
      }
      .sheet(item: $helpTarget) { target in
        HelpSheet(target: target)
      }
      // ⌘K opens Go to RFC too, where most apps with a palette put it. The menu's
      // item holds ⌘L, and one item gets one shortcut, so this invisible button
      // carries the other, drawn transparent and kept out of VoiceOver's way.
      .background {
        Button("Go to RFC") { navigation.isShowingGoToSheet = true }
          .keyboardShortcut(ReaderShortcut.quickOpen.keyboardShortcut)
          .opacity(0)
          .allowsHitTesting(false)
          .accessibilityHidden(true)
      }
      // ⌘= enlarges the text as View ▸ Bigger's ⌘+ does (#153): on a US keyboard
      // "+" takes Shift, and ⌘= is the chord people press. Invisible for the same
      // reason as ⌘K's; on the Mac, SwiftUI left a hidden menu item out of the menu
      // with its shortcut, measured.
      .background {
        Button("Bigger") { fontSize = ReaderPreferences.fontSize(steppingUp: fontSize) }
          .keyboardShortcut(ReaderShortcut.biggerAlternate.keyboardShortcut)
          .opacity(0)
          .allowsHitTesting(false)
          .accessibilityHidden(true)
      }
      .focusedSceneValue(\.openDocumentAction) {
        navigation.isShowingGoToSheet = true
      }
      .focusedSceneValue(\.showHelpAction) {
        // Not again while it is on show: a new target would dismiss and present it.
        if helpTarget == nil { helpTarget = HelpTarget() }
      }
      .focusedSceneValue(\.navigationModel, navigation)
      .focusedSceneValue(\.readerState, reader)
      // Outermost, and it has to be: an environment value reaches what is *inside*
      // the modifier that sets it, and a presentation is the content of the
      // modifier that presents it. Written on the split view, this covered the
      // three columns and missed the sheet above it — so ⌘L crashed the app on
      // `GoToDocumentSheet`'s `@Environment(NavigationModel.self)` lookup, which is
      // a runtime trap with no compile-time warning. Out here it covers both, and
      // the next presentation added to this view as well.
      .readerEnvironment(
        ReaderEnvironment(
          library: library, navigation: navigation, reader: reader))
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
        .keyboardShortcut(ReaderShortcut.goToRFC.keyboardShortcut)
      PrimerLink()
    }
  }
}

#if !os(macOS)
  /// Command-L style jump to an RFC by its number, typed on the number pad (#579):
  /// the search field beside the button already finds by keyword, so this lists the
  /// RFC with the number typed and nothing else, with no search to wait for.
  ///
  /// iOS only. The Mac has `QuickOpenPalette`, which takes a series, title words and
  /// links as well, because a form in a sheet is the right shape for a phone and the
  /// wrong one for ⌘L on a desktop (#26).
  struct GoToDocumentSheet: View {
    let library: LibraryModel
    let navigation: NavigationModel
    /// What the field shows: the digits of what was typed, written back when a
    /// paste or an iPad's keyboard brings anything else, which a binding through a
    /// filter would leave on screen when the digits did not change.
    @State private var text = ""
    @State private var results = QuickOpenResults()
    @FocusState private var focused: Bool

    var body: some View {
      NavigationStack {
        Form {
          TextField(QuickOpenResults.numberPlaceholder(), text: $text)
            .focused($focused)
            .keyboardType(.numberPad)
            // A hardware keyboard's Return; the number pad has none, and Open is
            // in the bar.
            .onSubmit(openSelection)
          if !results.rows.isEmpty {
            Section {
              ForEach(results.rows, id: \.self) { row in
                self.row(for: row.link)
              }
            }
          }
        }
        .navigationTitle("Go to RFC")
        .toolbar {
          ToolbarItem(placement: .cancellationAction) {
            Button("Cancel", action: close)
          }
          ToolbarItem(placement: .confirmationAction) {
            Button("Open", action: openSelection)
              .disabled(results.openable == nil)
          }
        }
      }
      .onChange(of: text) {
        let digits = QuickOpenResults.digits(in: text)
        if digits != text {
          text = digits
        }
        results.show(number: digits)
      }
      .onAppear {
        focused = true
        // The check at launch alone goes stale in an app left open for weeks; the
        // registries answer Look Up (`LookUpIdentifierIntent`).
        library.refreshRegistriesIfDue()
      }
    }

    private func row(for link: RFCLink) -> some View {
      let title = QuickOpenResults.title(
        library.metadata(link.id)?.title, isIndexLoaded: library.index != nil)
      return Button {
        open(link)
      } label: {
        HStack(spacing: 12) {
          Text(link.id.displayName)
            .fontWeight(.semibold)
            .monospacedDigit()
          Text(title)
            .lineLimit(1)
            .foregroundStyle(.secondary)
        }
      }
      .tint(.primary)
    }

    private func openSelection() {
      if let link = results.openable {
        open(link)
      }
    }

    private func open(_ link: RFCLink) {
      library.open(link, activation: .current, in: navigation)
      close()
    }

    private func close() {
      navigation.isShowingGoToSheet = false
    }
  }
#endif
