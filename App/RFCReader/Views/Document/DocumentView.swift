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
    // Read here, above the reader's own `openURL`, which follows links in the app:
    // the toolbar sits inside it, and reading it there opened rfc-editor.org's own
    // page as the RFC it names.
    @Environment(\.openURL) private var systemOpenURL
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
  #endif
  @AppStorage("readingFontSize") private var fontSize = 17.0
  @AppStorage("preferOriginalText") private var preferOriginalText = false
  @AppStorage("underlineLinks") private var underlineLinks = false
  @AppStorage("readerMeasure") private var measure = MeasurePreference.recommended
  /// The system's text size, which the reader follows (#153). The Mac has no
  /// Dynamic Type, and reports the default size.
  @Environment(\.dynamicTypeSize) private var textSize
  /// Bold Text. UIKit applies it to the system font by itself, as it makes the
  /// font, and a built document's fonts are made once: a change is a reason to
  /// build again, never an input to the style.
  @Environment(\.legibilityWeight) private var legibilityWeight

  let id: DocumentID

  /// The fetch, the build, and the state they leave the reader in. The document is
  /// built only there — never in `body`, which would rebuild on every redraw.
  @State private var session: DocumentSession
  @State private var originalText: String?

  init(id: DocumentID) {
    self.id = id
    _session = State(initialValue: DocumentSession(id: id))
  }
  #if !os(macOS)
    @State private var showsInspector = false

    /// Whether the panel is a sheet over the reader rather than a column beside it.
    private var isCompact: Bool { horizontalSizeClass == .compact }
  #endif
  /// Where the reader is, written the moment tracking computes it. This is the
  /// value; `ReaderState.currentAnchor` is its observable mirror, which lags it by
  /// a main-actor hop. Anything that cannot afford that lag — persisting the
  /// reading position on the way out — reads the box. The place across a rebuild
  /// is finer than a section, and the coordinator keeps that itself.
  @State private var lastVisibleAnchor = VisibleAnchorBox()
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

  private var buildInputs: BuildInputs {
    BuildInputs(
      hasDocument: session.state.document != nil, fontSize: fontSize,
      underlineLinks: underlineLinks,
      textSize: textSize, legibilityWeight: legibilityWeight, column: column)
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
        // The designation as the title, and what it is called beneath it.
        .navigationSubtitle(
          DocumentActions.subtitle(metadata: metadata, documentTitle: reader.documentTitle) ?? ""
        )
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
          DocumentToolbar(
            id: id, metadata: metadata, library: library, navigation: navigation,
            reader: reader, isBookmarked: library.bookmarkedDocuments.contains(id),
            openURL: systemOpenURL, showsInspector: $showsInspector)
        }
        // An overlay rather than an inset: it floats over the text and takes no
        // layout, so it cannot disturb the column, which is derived from this
        // view's frame.
        .overlay(alignment: .bottom) {
          returnButton.animation(.snappy, value: visibleReturn)
        }
        // Long enough to decide, without sitting over the text for good. Not under
        // VoiceOver, where a control that leaves on a timer may be gone before it
        // is reached: there it stays until the next navigation replaces it.
        .task(id: visibleReturn) {
          guard visibleReturn != nil, !voiceOverEnabled else { return }
          try? await Task.sleep(for: .seconds(8))
          guard !Task.isCancelled else { return }
          navigation.settleReturnOffer()
        }
        // iOS keeps the inspector as a column beside the reader where there is
        // room for one. In compact width it is a sheet, and a `.sheet` of our own
        // rather than the one `.inspector` turns itself into: that one, swiped
        // away, set the binding back to false but dropped the next request to
        // show it, so the panel's buttons opened it only on every other tap.
        .inspector(isPresented: isCompact ? .constant(false) : $showsInspector) {
          PanelHost(isPresented: $showsInspector, closesAfterChoice: false)
          .inspectorColumnWidth(min: 260, ideal: 320)
        }
        .sheet(isPresented: isCompact ? $showsInspector : .constant(false)) {
          PanelHost(isPresented: $showsInspector, closesAfterChoice: true)
          .presentationDetents([.medium, .large])
        }
      #endif
      .onAppear {
        if !session.hasStartedLoading { startLoad() }
        #if !os(macOS)
          reader.openPanel = { [isPresented = $showsInspector] in
            withAnimation(.snappy) { isPresented.wrappedValue = true }
          }
        #endif
      }
      .onChange(of: buildInputs, initial: true) {
        // Captures the reader, not the view; see `DocumentSession.startLoad`.
        session.requestBuild(for: buildInputs) { [reader, navigation, id] built, document in
          // A replaced reader lives on through its fade (`ReaderHost`), and its
          // rebuild must not list its sections under the next document.
          guard navigation.selection == id else { return }
          Self.listSections(of: document, in: built, into: reader)
        }
      }
      // The index state, not the metadata: a refresh can change a series' members
      // without changing this document's entry, and comparing the state is cheaper
      // on a body the reader re-evaluates on every section crossing.
      .onChange(of: library.indexState) { deriveInfo() }
      .onChange(of: navigation.scrollRequest) { _, request in
        jump(toSection: request?.section, animated: true)
      }
      .onDisappear(perform: saveReadingPosition)
      .environment(\.openURL, OpenURLAction(handler: handleLink))
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
      #endif
  }

  @ViewBuilder
  private var states: some View {
    if reader.showOriginal {
      // At the size the reader sets its body, the system's text size included, so
      // switching to the original does not drop someone back to 17 pt.
      OriginalTextView(
        text: originalText,
        fontSize: ReadingStyle(bodySize: fontSize, textSize: textSize).bodySize
      )
      .task { originalText = try? await library.originalText(for: id) }
      // No header to show the title here, so the toolbar shows it throughout.
      // On `hasDocument` rather than on appearing: loading a document clears
      // the title back to hidden after this view may already have appeared.
      .onChange(of: reader.hasDocument, initial: true) { reader.updateToolbarTitle(.shown) }
    } else if let document = session.state.document, let built = session.state.built {
      let headerIdentity = DocumentHeaderView.Identity(header: document.header, metadata: metadata)
      RFCTextView(
        built: built,
        bibliography: reader.groups,
        measure: measure,
        documentID: id,
        lastVisibleAnchor: lastVisibleAnchor,
        scrollTarget: scrollTarget,
        onScrollHandled: { scrollTarget = nil },
        onVisibleAnchorChange: {
          reader.currentAnchor = $0
          // Resolved here, where the document is: the toolbar's citation and
          // section link need the number, and on macOS the toolbar is in the
          // window rather than in this view. Through the map rather than
          // `document.section(anchor:)`, which searches the section tree
          // depth first — 305 sections on RFC 9110 — and this runs on every
          // section crossing while scrolling.
          reader.currentSection = session.sectionNumbers[$0]
          // Recorded on the history entry when navigating away, so coming
          // back returns here rather than to the top of the document.
          navigation.visiblePosition = $0
        },
        onLink: openInApp,
        onToolbarTitle: { reader.updateToolbarTitle($0) },
        heading: heading,
        headerIdentity: headerIdentity,
        // Hosted outside the storage, so it needs the environment handed to
        // it: the banner's links to newer RFCs go through `LibraryModel`.
        header: {
          DocumentHeaderView(
            library: library, navigation: navigation, identity: headerIdentity, heading: heading
          )
          .padding(.top, 16)
          .padding(.bottom, 12)
          // Outside the padding, so the heading is measured from the top of the
          // hosted view, which is where the coordinator places it.
          .coordinateSpace(.named(DocumentHeaderView.coordinateSpace))
        }
      )
      #if !os(macOS)
        // To the bottom edge of the screen, under the home indicator, rather than
        // stopping above it at a hard edge with a blank strip below. The text view
        // makes that strip room to scroll the last line clear of it. Vertical
        // only: the column is derived from the width, which this leaves alone.
        .ignoresSafeArea(.container, edges: .bottom)
      #endif
      .onAppear {
        // Deep link or restored reading position.
        if let request = navigation.scrollRequest {
          jump(toSection: request.section, animated: false)
        } else if let saved = ReadingPositionStore.stored(for: id, in: modelContext)?.anchor,
          document.section(anchor: saved) != nil
        {
          scrollTarget = ReaderScrollTarget(anchor: saved, animated: false)
        }
      }
    } else if let failure = session.state.failure {
      ContentUnavailableView {
        Label("Couldn't load \(id.displayName)", systemImage: "wifi.exclamationmark")
      } description: {
        Text(failure.message)
      } actions: {
        Button("Try Again") { startLoad() }
        Link("Open on rfc-editor.org", destination: RFCEditorEndpoints.infoPage(id))
      }
    } else {
      ProgressView("Loading \(id.displayName)…")
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
  }

  #if !os(macOS)
    /// Where a tap on the return offer goes, while it is on show.
    ///
    /// In a single column only: beside other columns, the back/forward pair is in
    /// the bar.
    private var visibleReturn: Place? {
      horizontalSizeClass == .compact ? navigation.returnOffer : nil
    }

    /// "Back to §4.2" after following a link within the document (#254). In a
    /// single column there is no back/forward pair, and the system back button
    /// leaves the document.
    @ViewBuilder
    private var returnButton: some View {
      if let offer = visibleReturn {
        Button {
          navigation.goBack()
        } label: {
          Label(
            ReturnOffer.title(for: offer, sectionNumbers: session.sectionNumbers),
            systemImage: "arrow.uturn.backward")
        }
        .buttonStyle(.glass)
        .padding(.bottom, 16)
        .transition(.move(edge: .bottom).combined(with: .opacity))
      }
    }

  #endif

  // MARK: - Actions

  /// Fetches the document, with the reader's panel made ready for it first.
  ///
  /// Once per view, plus Try Again after a failure: the view is made per document
  /// (`.id(selection)`), and appearing again keeps what it loaded.
  private func startLoad() {
    // The scene's `ReaderState` must not carry the previous document's place into
    // this one; `install()` reports the real anchor a moment later.
    reader.clear()
    reader.showOriginal = preferOriginalText
    // Before the fetch, not after: the index knows the document before its body
    // arrives, so the tab is ready the moment the panel is.
    deriveInfo()
    // Captures what it writes to, not the view; see `DocumentSession.startLoad`.
    session.startLoad(from: library) { [reader, library, navigation, modelContext, id] loaded in
      // Not over the next document's reader state; see `requestBuild`'s caller.
      guard navigation.selection == id else { return }
      reader.groups = ReferenceGroup.groups(in: loaded)
      reader.info = Self.info(for: id, authors: loaded.header.authors, in: library)
      // Here rather than on appearing: once per opening, since each is a view of
      // its own (`.id(selection)`) and a collapsed split view's spurious
      // disappear and appear is not another one (#260). And only once the
      // document is here, so one that failed to open is not listed as read.
      ReadingPositionStore.markAsRead(id, in: modelContext)
      reader.documentTitle = loaded.header.title
      reader.precedingDraft = loaded.header.precedingDraft
      reader.hasDocument = true
    }
  }

  /// What the Info pane shows. Again whenever the index loads or refreshes: a document
  /// opened before the index finished loading has none to show until it does. And
  /// again once the document is here, whose own authors carry the contact details
  /// their chips open.
  private func deriveInfo() {
    reader.info = Self.info(
      for: id, authors: session.state.document?.header.authors, in: library)
  }

  /// Static, so the load's callback can derive it without capturing the view.
  private static func info(
    for id: DocumentID, authors: [Author]?, in library: LibraryModel
  ) -> DocumentInfo? {
    library.metadata(id).map { DocumentInfo($0, authors: authors, in: library.index) }
  }

  /// The sections the storage actually holds, straight from the index the builder
  /// just emitted — rather than re-deriving "is this a bibliography?" from the model
  /// and hoping the two rules stay in step. A contents row that has no anchor is a
  /// destination `scroll(to:)` cannot reach.
  ///
  /// No place to restore here: the coordinator carries the line at the top of the
  /// viewport into the new storage itself, which a section anchor — all this view is
  /// told — could only approximate to the section's heading.
  private static func listSections(
    of document: RFCDocument, in built: BuiltDocument, into reader: ReaderState
  ) {
    // Taken once: `AnchorIndex.sections` filters, sorts and re-indexes every
    // anchor in the document, so asking inside the filter would rebuild the whole
    // index once per section.
    let sections = built.anchors.sections
    reader.sections = document.allSections.filter { sections.offset(of: $0.anchor) != nil }
  }

  /// Off the main actor, and structured: unlike a detached task, it inherits the
  /// caller's priority and its cancellation (#129). The builder never checks for
  /// cancellation, so a build that has started runs to the end;
  /// `DocumentSession.requestBuild` is what discards a canceled one.
  /// `DocumentPreview` builds through it too.
  @concurrent
  static func build(_ document: RFCDocument, style: ReadingStyle) async -> BuiltDocument {
    DocumentTextBuilder.build(document, style: style)
  }

  /// Resolves a section number or an anchor to the anchor the reader scrolls to.
  private func jump(toSection section: String?, animated: Bool) {
    guard let section, let document = session.state.document else { return }
    scrollTarget = ReaderScrollTarget(
      anchor: document.anchor(forPlace: section), animated: animated)
  }

  /// Cross references arrive as URLs from the attributed text; anything else goes to the system.
  ///
  /// No modifiers here: SwiftUI's `openURL` carries no event, so a Cmd-click that
  /// arrives this way follows the link in place. The text view's own delegate reads
  /// the modifiers and is the path a click on a reference actually takes.
  private func handleLink(_ url: URL) -> OpenURLAction.Result {
    openInApp(url, activation: .here) ? .handled : .systemAction
  }

  /// The same decision as `handleLink`, as a `Bool`: the text view's delegate wants
  /// to know whether to fall back to its own action, and `OpenURLAction.Result` is
  /// not `Equatable`.
  ///
  /// Where the click goes is decided in `LinkDestination`, which is testable; this
  /// is only the one effect per answer.
  private func openInApp(_ url: URL, activation: LinkActivation) -> Bool {
    switch LinkDestination.resolve(url, from: id, activation: activation) {
    case .jump(let section):
      navigation.jump(toSection: section)
    case .reference(let anchor):
      reader.reveal(reference: anchor)
    case .document(let link):
      library.open(link, activation: activation, in: navigation)
    case .unhandled:
      return false
    }
    return true
  }

  private func saveReadingPosition() {
    // Nothing to save for a document that never showed its text — one that failed
    // to load, or was left before it did — and saving no place would erase the one
    // stored, and list a document that never opened as read.
    guard let anchor = lastVisibleAnchor.anchor else { return }
    // The anchor alone for now: the reader reports the section on screen, not the
    // offset within it, so a place is saved at the anchor itself (#152).
    ReadingPositionStore.save(ReadingPlace(anchor: anchor, offset: 0), for: id, in: modelContext)
  }
}
