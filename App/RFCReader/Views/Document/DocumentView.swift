import RFCKit
import RFCReaderKit
import SwiftData
import SwiftUI
import os

/// The reader. Renders an `RFCDocument` natively and handles every in-document link.
struct DocumentView: View {
  @Environment(LibraryModel.self) private var library
  @Environment(NavigationModel.self) private var navigation
  /// Shared with the window's toolbar and its contents panel, which on macOS are
  /// not inside this view any more.
  @Environment(ReaderState.self) private var reader
  @Environment(\.modelContext) private var modelContext
  #if !os(macOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
  #endif
  @AppStorage(ReaderPreferences.fontSizeKey) private var fontSize = ReaderPreferences
    .defaultFontSize
  @AppStorage(ReaderPreferences.preferOriginalTextKey) private var preferOriginalText =
    ReaderPreferences.defaultPreferOriginalText
  @AppStorage(ReaderPreferences.underlineLinksKey) private var underlineLinks =
    ReaderPreferences.defaultUnderlineLinks
  @AppStorage(ReaderPreferences.measureKey) private var measure = ReaderPreferences.defaultMeasure
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
  /// Whether a new column comes from a resize still under way; see `ReaderResize`.
  @State private var resize = ReaderResize()

  init(id: DocumentID) {
    self.id = id
    _session = State(initialValue: DocumentSession(id: id))
  }
  #if !os(macOS)
    @State private var showsInspector = false
    /// Whether a print is being prepared or its sheet is up; see `printDocument()`.
    @State private var isPrinting = false
    /// A finished export, while Save to Files is showing it (#376).
    @State private var exported: ExportedFile?
    /// Whether an export is being made or Save to Files is up; see `exportDocument(as:)`.
    @State private var isExporting = false

    /// Whether the panel is a sheet over the reader rather than a column beside it.
    private var isCompact: Bool { horizontalSizeClass == .compact }
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
        .navigationBarTitleDisplayMode(.inline)
        // The designation over what it is called, in the bar once the header has
        // scrolled away. The navigation title stays, for the back button and the
        // app switcher.
        .toolbar {
          ToolbarItem(placement: .principal) {
            DocumentTitle(
              title: id.displayName,
              subtitle: DocumentActions.subtitle(
                metadata: metadata, documentTitle: reader.documentTitle) ?? "",
              reader: reader)
          }
        }
        .toolbar {
          DocumentToolbar(
            id: id, metadata: metadata, library: library, navigation: navigation,
            reader: reader, isBookmarked: library.bookmarkedDocuments.contains(id),
            showsInspector: $showsInspector,
            exportDocument: exportDocument(as:), printDocument: printDocument,
            showsBottomBar: !barsHidden)
        }
        // The top bar, which leaves the status bar; the bottom one goes by losing
        // its items (`DocumentToolbar.showsBottomBar`). The reader runs under both,
        // so neither moves it.
        .toolbarVisibility(barsHidden ? .hidden : .automatic, for: .navigationBar)
        // The original text has no reader to bring them back with a tap, and the
        // reader made afresh on the way back starts with them showing.
        .onChange(of: reader.showOriginal) { barsHidden = false }
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
        .fileExporter(
          isPresented: Binding(
            get: { exported != nil },
            set: {
              if !$0 {
                exported = nil
                isExporting = false
              }
            }),
          document: exported,
          contentType: (exported?.format ?? .pdf).contentType,
          defaultFilename: ExportFormat.fileStem(for: id)
        ) { _ in
          exported = nil
          isExporting = false
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
      // Into the window's reader state, for the panel beside the reader (#325):
      // how a load ends. `startLoad` says it began, after clearing that state.
      .onChange(of: session.state.isLoading) { _, isLoading in
        reader.isLoading = isLoading
      }
      .onChange(of: buildInputs, initial: true) {
        // Captures the reader, not the view; see `DocumentSession.startLoad`.
        session.requestBuild(for: buildInputs, resizeIsLive: resize.isLive) {
          [reader, navigation, id] built, document in
          // A replaced reader lives on through its fade (`ReaderHost`), and its
          // rebuild must not list its sections under the next document.
          guard navigation.selection == id else { return }
          Self.listSections(of: document, in: built, into: reader)
        }
      }
      // The index state, not the metadata: a refresh can change a series' members
      // without changing this document's entry, and comparing the state is cheaper
      // on a body the reader re-evaluates on every section crossing.
      .onChange(of: library.indexState) {
        deriveInfo()
        markPublishedOriginal()
      }
      .onChange(of: library.revisions) { deriveInfo() }
      .onChange(of: navigation.scrollRequest) { _, request in
        // Not while fading out over the next document's reader: the request is
        // the selected document's.
        guard navigation.selection == id, let request else { return }
        if request.isUnrecorded {
          follow(request, animated: true)
        } else {
          jump(toSection: request.section, animated: request.isAnimated, revealingReferences: true)
        }
      }
      .onDisappear(perform: saveReadingPosition)
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
        id, formats: metadata.formats, showsOriginal: reader.showOriginal,
        text: session.state.document)
    {
      originalOnly(page, metadata: metadata)
    } else if reader.showOriginal {
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
          // Not while fading out: the reader state is the selected document's.
          guard navigation.selection == id else { return }
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
          guard navigation.selection == id else { return }
          reader.report(title: state, from: source)
        },
        onToolbarTitleReleased: { reader.releaseTitle(from: $0) },
        onSelectionChange: {
          guard navigation.selection == id else { return }
          reader.hasSelection = $0
        },
        hidesChrome: hidesChrome,
        onChromeHidden: setBarsHidden,
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
        // Under the top bar, so it is glass over the text rather than a solid
        // strip above it, and its going moves nothing; and to the bottom edge of
        // the screen, under the home indicator, rather than stopping above it at a
        // hard edge with a blank strip below. The text view makes both strips
        // insets, room to scroll the text clear of them. Vertical only: the column
        // is derived from the width, which this leaves alone.
        .ignoresSafeArea(.container, edges: .vertical)
      #endif
      .onAppear {
        // Deep link or restored reading position — or, when the text view is made
        // again, where the reader was (#449).
        let arrival = ReaderArrival.onAppear(
          pendingAnchor: scrollTarget?.anchor, placeLeft: placeLeft,
          request: navigation.scrollRequest,
          // Any anchor, not only a section's: a place is saved at the nearest anchor
          // of any kind (`ReadingPlace`), a paragraph's as often as not.
          stored: storedPosition()?.place.flatMap { saved in
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
    } else {
      ProgressView("Loading \(id.displayName)…")
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
          library: library, navigation: navigation,
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

  #if !os(macOS)
    /// Save to Files, with the document in `format` (#376). Laid out for the region's
    /// paper, as a print is.
    private func exportDocument(as format: ExportFormat) {
      // A second tap while the file is made would make it again, and present Save to
      // Files over the first.
      guard !isExporting else { return }
      isExporting = true
      Task {
        guard
          let data = try? await DocumentExport.data(
            for: id, as: format, paperSize: PrintLayout.paperSize(for: .current),
            library: library)
        else {
          isExporting = false
          return
        }
        exported = ExportedFile(data: data, format: format)
      }
    }

    /// The system's print sheet, with the document laid out for paper (#375). Laid
    /// out for the region's paper; the sheet scales it to whatever paper is chosen.
    private func printDocument() {
      // A second tap while the PDF is built would build it again and present the
      // shared controller twice.
      guard !isPrinting else { return }
      isPrinting = true
      let original = reader.showOriginal
      Task {
        guard
          let data = try? await DocumentPDF.make(
            for: id, original: original, paperSize: PrintLayout.paperSize(for: .current),
            library: library)
        else {
          isPrinting = false
          return
        }
        let info = UIPrintInfo.printInfo()
        info.jobName = PrintFurniture.documentTitle(
          id: id, title: reader.documentTitle ?? library.metadata(id)?.title)
        info.outputType = .general
        let controller = UIPrintInteractionController.shared
        controller.printInfo = info
        controller.printingItem = data
        controller.present(animated: true) { _, _, _ in isPrinting = false }
      }
    }

    /// Where a tap on the return offer goes, while it is on show.
    ///
    /// In a single column only: beside other columns, the back/forward pair is in
    /// the bar.
    private var visibleReturn: HistoryEntry? {
      horizontalSizeClass == .compact ? navigation.returnOffer : nil
    }

    /// "Back to § 4.2" after following a link within the document (#254). In a
    /// single column there is no back/forward pair, and the system back button
    /// leaves the document.
    @ViewBuilder
    private var returnButton: some View {
      if let offer = visibleReturn {
        Button {
          navigation.goBack()
        } label: {
          Label(
            ReturnOffer.title(for: offer, in: session.state.document),
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
    reader.isLoading = true
    // Its header is on its way until the reader reports, so the title stays out of
    // the toolbar rather than showing and then dropping (#281).
    reader.documentStartsLoading()
    markPublishedOriginal()
    // Before the fetch, not after: the index knows the document before its body
    // arrives, so the tab is ready the moment the panel is.
    deriveInfo()
    // A scan has no text to fetch (#207): its page is the index's.
    guard PublishedOriginalPage.loadsText(id, formats: metadata?.formats) else {
      session.skipLoad()
      reader.isLoading = false
      return
    }
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
      do {
        try ReadingPositionStore.markOpened(id, in: modelContext)
      } catch {
        readerLog.error(
          "marking \(id.displayName, privacy: .public) as read failed: \(String(describing: error), privacy: .public)"
        )
      }
      reader.documentTitle = loaded.header.title
      reader.precedingDraft = loaded.header.precedingDraft
      reader.hasDocument = true
      reader.publishedOriginal = Self.publishedOriginal(id, text: loaded, in: library)
      // Last and apart, so the first build does not wait for it; and, like the
      // rest, not written over the next document's reader state.
      Task(name: "Extract requirements") { [reader, navigation, id] in
        let requirements = await Self.requirements(in: loaded)
        guard navigation.selection == id else { return }
        reader.requirements = requirements
      }
    } failed: { [reader, navigation, id] in
      // No header is coming, so the toolbar names the RFC that failed; unless it is
      // a scan (`publishedOriginal`), whose page shows the header.
      guard navigation.selection == id else { return }
      reader.documentFailedToLoad()
      // A jump waiting for the text is not coming.
      if let request = navigation.scrollRequest { navigation.settle(request) }
    }
  }

  /// Why this RFC is read as its original, if it is (#207): as the load starts, and
  /// again when the index loads, which may be after the fetch ended.
  private func markPublishedOriginal() {
    // Not while fading out: the reader state is the selected document's.
    guard navigation.selection == id else { return }
    reader.publishedOriginal = Self.publishedOriginal(
      id, text: session.state.document, in: library)
  }

  /// Static, so the load's callback can ask it without capturing the view.
  private static func publishedOriginal(
    _ id: DocumentID, text document: RFCDocument?, in library: LibraryModel
  ) -> PublishedOriginalPage.Status? {
    library.metadata(id).flatMap {
      PublishedOriginalPage.Status(id, formats: $0.formats, text: document)
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
    library.metadata(id).map {
      DocumentInfo(
        $0, authors: authors, in: library.index,
        revisions: library.revisionsSummary(for: $0.id))
    }
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

  /// The Requirements tab's rows (#180), off the main actor: every sentence of the
  /// document is split and read for key words.
  @concurrent
  private static func requirements(in document: RFCDocument) async -> [Requirement] {
    Requirements.extract(from: document)
  }

  /// Off the main actor, and structured: unlike a detached task, it inherits the
  /// caller's priority and its cancellation (#129). The builder never checks for
  /// cancellation, so a build that has started runs to the end;
  /// `DocumentSession.requestBuild` is what discards a canceled one.
  /// `DocumentPreview` builds through it too.
  @concurrent
  static func build(_ document: RFCDocument, style: ReadingStyle) async -> BuiltDocument {
    let name = document.header.id?.displayName ?? "untitled"
    return signposter.withIntervalSignpost(
      "Build document", id: signposter.makeSignpostID(), "\(name, privacy: .public)"
    ) {
      DocumentTextBuilder.build(document, style: style)
    }
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
    // Not while fading out over the next document's reader: the place is the
    // selected document's.
    guard navigation.selection == id, let document = session.state.document,
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
    do {
      try ReadingPositionStore.save(
        lastVisibleAnchor.place ?? ReadingPlace(anchor: anchor, offset: 0), for: id,
        in: modelContext)
    } catch {
      readerLog.error(
        "saving the position failed: \(String(describing: error), privacy: .public)")
    }
  }

  /// Nil when the fetch fails, which is logged: the reader opens at the top, as it
  /// does for a document never read.
  private func storedPosition() -> ReadingPosition? {
    do {
      return try ReadingPositionStore.position(for: id, in: modelContext)
    } catch {
      readerLog.error(
        "reading the position failed: \(String(describing: error), privacy: .public)")
      return nil
    }
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
