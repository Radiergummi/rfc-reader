import RFCKit
import RFCReaderKit
import SwiftData
import SwiftUI

/// The reader. Renders an `RFCDocument` natively and handles every in-document link.
struct DocumentView: View {
  @Environment(LibraryModel.self) private var library
  @Environment(NavigationModel.self) private var navigation
  /// Shared with the window's toolbar and its contents panel, which on macOS are
  /// not inside this view any more.
  @Environment(ReaderState.self) private var reader
  @Environment(\.modelContext) private var modelContext
  #if !os(macOS)
    @Environment(\.sceneChrome) private var chrome
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    @Environment(\.scenePhase) private var scenePhase
  #endif
  @AppStorage(ReaderPreferences.fontSizeKey) private var fontSize = ReaderPreferences
    .defaultFontSize
  @AppStorage(ReaderPreferences.preferOriginalTextKey) private var preferOriginalText =
    ReaderPreferences.defaultPreferOriginalText
  @AppStorage(ReaderPreferences.underlineLinksKey) private var underlineLinks =
    ReaderPreferences.defaultUnderlineLinks
  @AppStorage(ReaderPreferences.measureKey) private var measure = ReaderPreferences.defaultMeasure
  @AppStorage(ReaderPreferences.drawDiagramsKey) private var drawDiagrams =
    ReaderPreferences.defaultDrawDiagrams
  /// The system's text size, which the reader follows (#153). The Mac has no
  /// Dynamic Type, and reports the default size.
  @Environment(\.dynamicTypeSize) private var textSize
  /// Bold Text. UIKit applies it to the system font by itself, as it makes the
  /// font, and a built document's fonts are made once: a change is a reason to
  /// build again, never an input to the style.
  @Environment(\.legibilityWeight) private var legibilityWeight

  let id: DocumentID
  /// The reader's place in the tab's stack of readers on iOS (#263), from 0 at the
  /// root; nil on the Mac, whose one reader is not stacked.
  let depth: Int?

  /// The fetch, the build, and the state they leave the reader in. The document is
  /// built only there — never in `body`, which would rebuild on every redraw.
  @State private var session: DocumentSession
  /// The text of the build the reader's folding index was made of (#699).
  @State private var foldedText: NSAttributedString?
  /// Whether a new column comes from a resize still under way; see `ReaderResize`.
  @State private var resize = ReaderResize()

  /// Whether the window's reader state is this reader's. On the Mac it is while the
  /// reader is selected. On iOS a reader the stack keeps below its top gives it up
  /// to the readers pushed over it, and takes it back once it is on top again
  /// (#263): until then it shows what it showed, the original text or not and what
  /// was unfolded, kept in `keptOriginal` and `keptFolding`.
  @State private var ownsReader: Bool
  @State private var keptOriginal = false
  @State private var keptFolding = Folding()
  /// Whether the text view went from view under a reader pushed over it, rather than
  /// going: it stays where it was, and coming back into view is not arriving.
  @State private var isCovered = false

  #if os(macOS)
    init(id: DocumentID) {
      self.id = id
      depth = nil
      _session = State(initialValue: DocumentSession(id: id, depth: nil))
      _ownsReader = State(initialValue: true)
    }
  #else
    /// A reader in the tab's stack. The panel is the stack's, so that an open panel
    /// stays open from one reader to the next.
    init(id: DocumentID, depth: Int, showsInspector: Binding<Bool>) {
      self.id = id
      self.depth = depth
      _session = State(initialValue: DocumentSession(id: id, depth: depth))
      _ownsReader = State(initialValue: false)
      _showsInspector = showsInspector
    }
  #endif

  /// Whether this is the reader on screen, whose the window's reader state is.
  private var isShown: Bool { navigation.shows(id, at: depth) }

  /// Whether what the window's reader state says is this reader's to show: it is on
  /// screen, and has put its own there.
  private var showsReaderState: Bool { ownsReader && isShown }

  /// The original text or the rendered document: the window's choice while the
  /// reader state is this reader's, and what it last was otherwise.
  private var showsOriginal: Bool { showsReaderState ? reader.showOriginal : keptOriginal }

  #if !os(macOS)
    @Binding private var showsInspector: Bool
    /// Export and Print, and the sheets they present.
    @State private var output = DocumentOutput()

    /// Whether the panel is a sheet over the reader rather than a column beside it.
    private var isCompact: Bool { chrome.isCollapsed }
    /// Whether reading on has put the bars away; see `ReaderChrome`.
    @State private var barsHidden = false
  #endif

  /// Whether reading on may hide the bars: on iPhone, where they cost the most of
  /// the screen, and not under VoiceOver, where a control that leaves may be gone
  /// before it is reached. Beside other columns the bars are a small part of it.
  /// Not on an iPad in a compact width either, Slide Over or a narrow split: that
  /// is where a keyboard is, and the bottom bar's shortcuts leave with its items.
  private var hidesChrome: Bool {
    #if os(macOS)
      false
    #else
      isCompact && UIDevice.current.userInterfaceIdiom == .phone && !voiceOverEnabled
    #endif
  }
  /// Where the reader is, written the moment tracking computes it. This is the
  /// value; `ReaderState.currentAnchor` is its observable mirror, which lags it by
  /// a main-actor hop. Anything that cannot afford that lag — persisting the
  /// reading position on the way out — reads the box. The place across a rebuild
  /// is finer than a section, and the coordinator keeps that itself.
  @State private var lastVisibleAnchor = VisibleAnchorBox()
  @State private var placeSaver = ReadingPlaceSaver()
  /// Where the reader was when the text view last went — turning Original Text on
  /// takes it away — so that it comes back there (#449). Nil until it has gone with
  /// a place, which it has once the text has shown.
  @State private var placeLeft: ReaderPlaceLeft?
  @State private var heading = HeadingBox()
  /// The pane's full width — the whole of it, panel or no panel — and nil until the
  /// geometry reader has run.
  ///
  /// The column is derived from this rather than stored beside it. Artwork scaling
  /// and table shape are measured against the column, so it has to be settled
  /// *before* the first build or the document is built against a guess and
  /// immediately thrown away. It is a pure function of the width and the measure
  /// preference (`ReaderLayout`), so this view can work it out for itself rather
  /// than waiting to be told by the text view it has not created yet — which is
  /// why nothing is built until the geometry reader has run once.
  @State private var paneWidth: CGFloat?
  #if os(macOS)
    /// How far the toolbar reaches over the pane, which the published-original page
    /// starts below (#207).
    @State private var toolbarInset: CGFloat = 0
  #endif

  /// Derived from the pane's width and the measure preference, and nothing else.
  ///
  /// The panel does not appear here and must not: on macOS the reader's pane spans
  /// it — the panel is a full-height inspector item drawn over the top — so the
  /// column is the same number whether it is showing or not. That is what keeps
  /// opening it from re-wrapping the document and — via `BuildInputs` — from
  /// rebuilding it and losing the reader's place. What the panel overlaps, it
  /// covers, and closing it uncovers.
  private var column: CGFloat? {
    paneWidth.map { ReaderLayout.column(forWidth: $0, measure: measure) }
  }

  private var metadata: RFCMetadata? { library.metadata(id) }

  private var positions: ReadingPositionKeeper {
    ReadingPositionKeeper(id: id, context: modelContext)
  }

  private var buildInputs: BuildInputs {
    BuildInputs(
      hasDocument: session.state.document != nil, fontSize: fontSize,
      underlineLinks: underlineLinks,
      textSize: textSize, legibilityWeight: legibilityWeight, column: column,
      choices: library.presentationChoices(for: id, drawsDiagrams: drawDiagrams))
  }

  /// The folding index of the build on screen, and in Focus the References tab's
  /// groups, filtered to what its section cites (#699). Only for the reader on
  /// screen, whose the reader state is, and only in Focus, which alone needs them;
  /// not over the original text, which nothing folds.
  private func updateFolding() {
    guard showsReaderState else { return }
    guard reader.folding.mode == .focus, !reader.showOriginal, let built = session.state.built
    else {
      // Only where there is something to clear: every write notifies, and the panel
      // would redraw on every disclosure the outline turns.
      if reader.foldingIndex != nil { reader.foldingIndex = nil }
      if reader.focusGroups != nil { reader.focusGroups = nil }
      foldedText = nil
      return
    }
    // Held, and compared by reference: a new build can be allocated where the old
    // one was, and an identifier alone would take it for the old one.
    if reader.foldingIndex == nil || foldedText !== built.text {
      reader.foldingIndex = FoldingIndex(built)
      foldedText = built.text
    }
    guard let index = reader.foldingIndex, let anchor = reader.folding.focusedAnchor(in: index)
    else { return }
    let cited = FocusCitations.entries(citedIn: anchor, in: built, index: index)
    let groups = FocusCitations.groups(reader.groups, citing: cited)
    // A section that cites nothing lists the whole bibliography, rather than saying
    // the document has none.
    reader.focusGroups = groups.isEmpty ? nil : groups
  }

  /// The reader, and on macOS only the reader.
  ///
  /// There is no `.toolbar` and no panel in this view on macOS: both belong to the
  /// window. The toolbar is an `NSToolbar` with our own delegate (`ReaderToolbar`),
  /// because only a delegate-owned toolbar can carry the tracking separator that
  /// splits it at the panel's edge; the panel is an `NSSplitViewItem`, because only
  /// a real split item makes AppKit confine the tab bar and draw the glass.
  ///
  /// The overlay this replaces is worth remembering: `.inspector` put the reader
  /// beside the panel, and `.safeAreaBar` reserved layout space — so opening it
  /// widened the window, which widened the pane, which changed the column, which
  /// rebuilt the document and lost the reader's place. The split item avoids all of
  /// that by a different route: the reader's frame spans the panel, and the inset
  /// it reports is ignored in the representable.
  var body: some View {
    content
      .navigationTitle(id.displayName)
      #if !os(macOS)
        .modifier(
          IOSDocumentChrome(
            id: id, metadata: metadata, document: session.state.document, library: library,
            navigation: navigation, reader: reader, showsInspector: $showsInspector,
            barsHidden: $barsHidden, output: output, isShown: showsReaderState))
      #endif
      .onAppear {
        if !session.hasStartedLoading {
          startLoad()
          if isShown { ownsReader = true }
        } else {
          takeReaderState()
        }
        #if !os(macOS)
          reader.openPanel = { [isPresented = $showsInspector] in
            withAnimation(.snappy) { isPresented.wrappedValue = true }
          }
        #endif
      }
      // What Focus needs of the build: its folding index, and what its section cites
      // (#699).
      // By identifier, as a trigger only: comparing the texts themselves would compare
      // every character on every update. `updateFolding` compares the build itself.
      .onChange(of: session.state.built.map { ObjectIdentifier($0.text) }, initial: true) {
        updateFolding()
      }
      .onChange(of: reader.folding) {
        if showsReaderState { keptFolding = reader.folding }
        updateFolding()
      }
      .onChange(of: reader.showOriginal) {
        if showsReaderState { keptOriginal = reader.showOriginal }
        updateFolding()
      }
      // On iOS, covered by a reader pushed over it, or on top again once that one
      // is popped (#263).
      .onChange(of: isShown) { _, shown in
        guard depth != nil else { return }
        if shown {
          takeReaderState()
        } else {
          ownsReader = false
        }
      }
      // Into the window's reader state, for the panel beside the reader (#325):
      // how a load ends. `startLoad` says it began, after clearing that state. Not
      // for a reader under the top of the stack, which says it on top again
      // (`DocumentSession.reinstate`).
      .onChange(of: session.state.isLoading) { _, isLoading in
        guard isShown else { return }
        reader.isLoading = isLoading
      }
      .onChange(of: buildInputs, initial: true) {
        session.requestBuild(
          for: buildInputs, resizeIsLive: resize.isLive, into: reader, navigation: navigation)
      }
      // The index state, not the metadata: a refresh can change a series' members
      // without changing this document's entry, and comparing the state is cheaper
      // on a body the reader re-evaluates on every section crossing.
      .onChange(of: library.indexState) {
        session.deriveInfo(into: reader, library: library, navigation: navigation)
        session.markPublishedOriginal(into: reader, library: library, navigation: navigation)
      }
      // A pack installed while the document is open can make it a pointer (#316).
      .onChange(of: library.pointersInPack) {
        session.markPublishedOriginal(into: reader, library: library, navigation: navigation)
      }
      .onChange(of: library.revisions) {
        session.deriveInfo(into: reader, library: library, navigation: navigation)
      }
      .onChange(of: navigation.scrollRequest) { _, request in
        // Not while fading out over the next document's reader, nor under the top
        // of the stack: the request is the reader on screen's. A return to a reader
        // the stack kept finds it where it was left (#263).
        guard isShown, let request, !request.isToKeptReader else { return }
        if request.isUnrecorded {
          follow(request, animated: true)
        } else {
          jump(toSection: request.section, animated: request.isAnimated, revealingReferences: true)
        }
      }
      // Not only on the way out: quitting, or iOS ending an app in the background,
      // takes the reader with no `onDisappear` (#155). So the place is saved once
      // the reader stops, and when the app goes.
      .onAppear {
        // Not the view, and the box weakly: the box holds this.
        let box = lastVisibleAnchor
        box.placeDidChange = { [positions, placeSaver, weak box] in
          placeSaver.schedule {
            if let box { positions.save(box) }
          }
        }
      }
      #if os(macOS)
        // Hosted outside any scene, so no `scenePhase` reaches here: the app's quit.
        .onReceive(
          NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)
        ) { _ in saveNow() }
      #else
        // The scene's phase, not the app's: an iPad window swiped away goes to the
        // background alone.
        .onChange(of: scenePhase) {
          if scenePhase == .background { saveNow() }
        }
      #endif
      .onDisappear {
        // A report after this, during the fade-out, would save the document left
        // over the one now read.
        lastVisibleAnchor.placeDidChange = {}
        saveNow()
      }
  }

  private func saveNow() {
    placeSaver.cancel()
    positions.save(lastVisibleAnchor)
  }

  @State private var scrollTarget: ReaderScrollTarget?

  /// The width channel. It wraps everything, including the loading state, so the
  /// column is known before there is a document to build.
  ///
  /// The floor is here rather than on the split view's detail column, where it
  /// guarded the reader *and* the panel together and so let the panel take all but
  /// 190 pt of it. This is the reader alone.
  private var content: some View {
    states
      .onGeometryChange(for: CGFloat.self) {
        $0.size.width
      } action: { width in
        guard width > 0 else { return }
        paneWidth = width
      }
      #if os(macOS)
        // Constant, panel or no panel. Adding the panel's width here is what made
        // the window jump wider every time it opened: the floor rose by 320, and
        // macOS grew the window to satisfy it.
        .frame(minWidth: ReaderLayout.minimumPaneWidth)
      #else
        // Which size changes are a rotation, so their new column builds at once.
        .background {
          SizeTransitionObserver(resize: resize)
          .accessibilityHidden(true)
        }
      #endif
  }

  @ViewBuilder
  private var states: some View {
    if let metadata,
      let page = PublishedOriginalPage(
        id, formats: metadata.formats, showsOriginal: showsOriginal,
        text: session.state.document, pointerInPack: library.pointersInPack.contains(id))
    {
      originalOnly(page, metadata: metadata)
    } else if showsOriginal {
      // At the size the reader sets its body, the system's text size included, so
      // switching to the original does not drop someone back to 17 pt.
      OriginalTextView(
        text: session.originalText,
        failure: session.originalTextFailure,
        fontSize: ReadingStyle(bodySize: fontSize, textSize: textSize).bodySize,
        tryAgain: { session.startOriginalTextLoad(from: library) }
      )
      .onAppear {
        if !session.hasStartedOriginalTextLoad { session.startOriginalTextLoad(from: library) }
      }
    } else if let document = session.state.document, let built = session.state.built {
      let headerIdentity = DocumentHeaderView.Identity(
        header: document.header, metadata: metadata,
        revisions: metadata.map { library.revisionsSummary(for: $0.id) })
      RFCTextView(
        built: built,
        bibliography: reader.groups,
        measure: measure,
        documentID: id,
        lastVisibleAnchor: lastVisibleAnchor,
        scrollTarget: scrollTarget,
        onScrollHandled: { scrollTarget = nil },
        onVisibleAnchorChange: {
          // Not while fading out, nor under the top of the stack: the reader state
          // is the reader on screen's.
          guard isShown else { return }
          reader.currentAnchor = $0
          // Resolved here, where the document is: the toolbar's citation and
          // section link need the place, and on macOS the toolbar is in the
          // window rather than in this view. Through the map rather than
          // `document.section(anchor:)`, which searches the section tree
          // depth first — 305 sections on RFC 9110 — and this runs on every
          // section crossing while scrolling.
          reader.currentSection = session.sectionPlaces[$0]
          // Recorded on the history entry when navigating away, so coming
          // back returns here rather than to the top of the document.
          navigation.visiblePosition = $0
        },
        onLink: openInApp,
        // Not while fading out over the next document's reader, as the load's
        // and the build's callbacks guard: the title is the selected document's.
        onToolbarTitle: { state, source in
          guard isShown else { return }
          reader.report(title: state, from: source)
        },
        onToolbarTitleReleased: { reader.releaseTitle(from: $0) },
        onSelectionChange: {
          guard isShown else { return }
          reader.hasSelection = $0
        },
        onChoosePresentation: { library.choose($1, for: $0, in: id) },
        hidesChrome: hidesChrome,
        onChromeHidden: setBarsHidden,
        // Not while fading out, nor under the top of the stack until the reader
        // state is this reader's again: it is the reader on screen's.
        folding: showsReaderState ? reader.folding : nil,
        onFoldingChange: {
          guard isShown else { return }
          reader.folding = $0
        },
        isShown: showsReaderState,
        heading: heading,
        headerIdentity: headerIdentity,
        // Hosted outside the storage, given the environment by the text view.
        header: {
          DocumentHeaderView(identity: headerIdentity, heading: heading)
            .padding(.top, 16)
            .padding(.bottom, 12)
            // Outside the padding, so the heading is measured from the top of the
            // hosted view, which is where the coordinator places it.
            .coordinateSpace(.named(DocumentHeaderView.coordinateSpace))
        }
      )
      #if !os(macOS)
        // Under the top bar, so it is glass over the text rather than a solid
        // strip above it, and its going moves nothing; and to the bottom edge of
        // the screen, under the home indicator, rather than stopping above it at a
        // hard edge with a blank strip below. The text view makes both strips
        // insets, room to scroll the text clear of them. Vertical only: the column
        // is derived from the width, which this leaves alone.
        .ignoresSafeArea(.container, edges: .vertical)
      #endif
      .onAppear {
        // Back on top of the stack, the text view is the one that was covered,
        // where it was left (#263).
        if isCovered {
          isCovered = false
          return
        }
        // Deep link or restored reading position — or, when the text view is made
        // again, where the reader was (#449).
        let arrival = ReaderArrival.onAppear(
          pendingAnchor: scrollTarget?.anchor, placeLeft: placeLeft,
          request: navigation.scrollRequest,
          // Any anchor, not only a section's: a place is saved at the nearest anchor
          // of any kind (`ReadingPlace`), a paragraph's as often as not.
          stored: positions.stored()?.place.flatMap { saved in
            saved.anchor.flatMap(built.anchors.offset(of:)) != nil ? saved : nil
          })
        switch arrival {
        case .place(let anchor):
          scrollTarget = ReaderScrollTarget(anchor: anchor, animated: false)
        case .request(let request) where request.isUnrecorded:
          follow(request, animated: false)
        case .request(let request):
          jump(toSection: request.section, animated: false)
        case .stored(let saved):
          if let anchor = saved.anchor {
            scrollTarget = ReaderScrollTarget(anchor: anchor, animated: false, offset: saved.offset)
          }
        case .stay:
          break
        }
      }
      .onDisappear {
        // Covered by a reader pushed over it, the text view stays (#263).
        if depth != nil, !isShown {
          isCovered = true
          return
        }
        placeLeft =
          lastVisibleAnchor.isAheadOfSections ? .top : lastVisibleAnchor.anchor.map { .section($0) }
      }
    } else if let failure = session.state.failure {
      ContentUnavailableView {
        Label("Couldn't load \(id.displayName)", systemImage: failure.kind.symbol)
      } description: {
        Text(failure.message)
        Text(failure.kind.recoverySuggestion(for: .document))
      } actions: {
        Button("Try Again") { startLoad() }
        Link("Open on rfc-editor.org", destination: RFCEditorEndpoints.infoPage(id))
      }
    } else if session.state.showsProgress(isDue: session.isProgressDue) {
      ProgressView("Loading \(id.displayName)…")
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    } else {
      // Nothing yet, for a moment: a document in the cache normally builds before
      // the delay is up, and appears with no flash of progress (#263).
      Color.clear
    }
  }

  /// An RFC that is its PDF or PostScript original (#207): the header the index
  /// gives, and the original to open, rather than an error or a text that only says
  /// where the original is.
  ///
  /// Laid out as the reader lays out a document: the header at the top of the
  /// column, padded as `RFCTextView` pads it, and the notice below it, centered in
  /// the same column.
  private func originalOnly(_ page: PublishedOriginalPage, metadata: RFCMetadata) -> some View {
    let name = page.original.format.displayName
    return ScrollView {
      VStack(alignment: .leading, spacing: 0) {
        DocumentHeaderView(
          identity: DocumentHeaderView.Identity(
            header: DocumentHeader(id: id, title: metadata.title),
            metadata: metadata,
            revisions: library.revisionsSummary(for: metadata.id)),
          heading: heading
        )
        .padding(.top, 16)
        .padding(.bottom, 12)
        ContentUnavailableView {
          Label("Published as \(name)", systemImage: "doc.richtext")
        } description: {
          Text(page.explanation)
        } actions: {
          Link("Open the Original (\(name))", destination: page.original.url)
            // The reader's own handler would read the file's URL as a link to this
            // RFC, and open it here again.
            .environment(\.openURL, OpenURLAction { _ in .systemAction })
        }
        // Its own height, so it does not fill the pane and push itself down.
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity)
      }
      // The column `RFCTextView` sets its header and text in, centered in the pane
      // as its gutters center it.
      .frame(width: column)
      .frame(maxWidth: .infinity)
      .padding(.bottom, ReaderLayout.margin)
    }
    #if os(macOS)
      // The reader's hosted root refuses the safe area, so the scroll view would
      // start under the toolbar; the reader's own scroll view is AppKit's, and
      // insets itself by as much.
      .contentMargins(.top, toolbarInset, for: .scrollContent)
      .background(ToolbarInsetReader { toolbarInset = $0 })
    #endif
  }

  /// On iOS only; the Mac's toolbar is the window's, and stays.
  private func setBarsHidden(_ hidden: Bool) {
    #if !os(macOS)
      withAnimation(.easeInOut(duration: 0.25)) { barsHidden = hidden }
    #endif
  }

  // MARK: - Actions

  /// Fetches the document, with the reader's panel made ready for it first.
  private func startLoad() {
    keptOriginal = preferOriginalText
    session.open(
      into: reader, library: library, navigation: navigation, positions: positions,
      showsOriginal: preferOriginalText)
  }

  /// Resolves a section number or an anchor to the anchor the reader scrolls to.
  ///
  /// An anchor the body does not hold scrolls nowhere: a document already open stays
  /// where the reader is, and one just opened stays at its top (#276). In a document
  /// already open, a place naming a bibliography entry shows it; see
  /// `LinkDestination.landing(at:in:bibliography:anchors:)`.
  private func jump(toSection section: String?, animated: Bool, revealingReferences: Bool = false) {
    guard let section else { return }
    switch landing(at: section) {
    case .reference(let anchor) where revealingReferences:
      reader.reveal(reference: anchor)
    case .reference(let anchor), .jump(let anchor):
      scrollTarget = ReaderScrollTarget(anchor: anchor, animated: animated)
    case .document, .unhandled, nil:
      break
    }
  }

  /// A link to a place in this document, which has no entry in the history yet: one
  /// the document holds gets its entry, so Back returns from it, and scrolls through
  /// it; an entry of the bibliography is shown; anything else moves nothing, and
  /// leaves the history as it is. False while there is no build to look in.
  @discardableResult
  private func follow(_ place: String, animated: Bool = true) -> Bool {
    // Not while fading out over the next document's reader, nor under the top of
    // the stack: the place is the reader on screen's.
    guard isShown, let document = session.state.document,
      let built = session.state.built
    else { return false }
    switch landing(at: place) {
    case .jump(let anchor):
      navigation.recordJump(
        to: anchor, in: DocumentPlaces(document: document, anchors: built.anchors),
        animated: animated)
    case .reference(let anchor):
      reader.reveal(reference: anchor)
    case .document, .unhandled, nil:
      break
    }
    return true
  }

  /// A place handed over unrecorded, settled once followed. Without a build it
  /// waits for the text to appear, and is followed there, unanimated.
  private func follow(_ request: NavigationModel.ScrollRequest, animated: Bool) {
    if follow(request.section, animated: animated) {
      navigation.settle(request)
    }
  }

  /// Takes the window's reader state back, for a reader the stack kept below its top
  /// that is on top again (#263): the readers pushed over it had it.
  private func takeReaderState() {
    guard !ownsReader, isShown, session.hasStartedLoading else { return }
    session.reinstate(
      into: reader, library: library, navigation: navigation, showsOriginal: keptOriginal,
      folding: keptFolding)
    ownsReader = true
    updateFolding()
  }

  /// Nil while there is no build to find the place in.
  private func landing(at place: String) -> LinkDestination? {
    guard let document = session.state.document, let built = session.state.built else {
      return nil
    }
    return LinkDestination.landing(
      at: place, in: document, bibliography: reader.groups, anchors: built.anchors)
  }

  /// Cross references arrive as URLs from the attributed text, through the text
  /// view's delegate, which reads the click's modifiers; it falls back to its own
  /// action, the system's, when this returns false.
  ///
  /// The reader sets no `openURL` of its own: everything else under it that opens a
  /// URL — the failed load's link, the iOS toolbar and panel — is a page on the web,
  /// and an override here read rfc-editor.org's pages as the RFCs they name, and
  /// reopened the document instead of the browser (#450).
  ///
  /// Where the click goes is decided in `LinkDestination`, which is testable; this
  /// is only the one effect per answer.
  private func openInApp(_ url: URL, activation: LinkActivation) -> Bool {
    switch LinkDestination.resolve(url, from: id, activation: activation) {
    case .jump(let section):
      follow(section)
    case .reference(let anchor):
      reader.reveal(reference: anchor)
    case .document(let link):
      library.open(link, activation: activation, in: navigation, arrival: .citation)
    case .unhandled:
      return false
    }
    return true
  }
}

#if os(macOS)
  /// Reports how far the window's toolbar reaches over this view: the distance from
  /// its top down to the window's `contentLayoutRect`. SwiftUI cannot say, since
  /// the reader's hosted root refuses the safe area.
  private struct ToolbarInsetReader: NSViewRepresentable {
    let report: (CGFloat) -> Void

    func makeNSView(context: Context) -> ReaderView { ReaderView() }

    func updateNSView(_ view: ReaderView, context: Context) {
      view.report = report
    }

    final class ReaderView: NSView {
      var report: (CGFloat) -> Void = { _ in }
      private var reported: CGFloat?

      override func layout() {
        super.layout()
        guard let window else { return }
        let top = convert(NSPoint(x: 0, y: bounds.maxY), to: nil).y
        let inset = max(0, top - window.contentLayoutRect.maxY)
        guard inset != reported else { return }
        reported = inset
        // Not during the layout pass that measured it.
        Task { @MainActor [report] in report(inset) }
      }
    }
  }
#endif
