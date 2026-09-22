import RFCKit
import RFCReaderKit
import SwiftData
import SwiftUI

/// The reader. Renders an `RFCDocument` natively and handles every in-document link.
struct DocumentView: View {
    @Environment(LibraryModel.self) private var library
    @Environment(NavigationModel.self) private var navigation
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var systemOpenURL
    @Query private var bookmarks: [Bookmark]
    @AppStorage("readingFontSize") private var fontSize = 17.0
    @AppStorage("preferOriginalText") private var preferOriginalText = false

    let id: DocumentID

    @State private var document: RFCDocument?
    /// The document as one attributed string plus its anchor index. Built only in
    /// `rebuild()` — never in `body`, which would rebuild on every redraw.
    @State private var built: BuiltDocument?
    @State private var originalText: String?
    @State private var loadError: String?
    @State private var showOriginal = false
    @State private var showTableOfContents = false
    /// Which of the two the inspector is showing. Both are ways of navigating the
    /// document, so they share one panel rather than competing for the toolbar.
    @State private var inspectorTab = InspectorTab.contents
    /// The two lists the inspector shows. Derived once when a document loads: the
    /// inspector's body re-evaluates on every section crossing while scrolling, and
    /// both of these walk every section and block of the document.
    @State private var bodySections: [RFCKit.Section] = []
    @State private var referenceGroups: [ReferenceGroup] = []
    /// Where the reader is, written the moment tracking computes it. This is the
    /// value; `visibleAnchor` below is its SwiftUI-observable mirror, which lags it
    /// by a main-actor hop. Anything that cannot afford that lag — persisting the
    /// reading position on the way out, restoring the place across a rebuild — reads
    /// the box.
    @State private var lastVisibleAnchor = VisibleAnchorBox()
    /// The same value, for the parts of `body` that have to redraw when it changes:
    /// the table of contents' highlight and the "copy link to this section" item.
    @State private var visibleAnchor: String?
    /// The pane's full width — the whole of it, panel or no panel — and nil until the
    /// geometry reader has run.
    ///
    /// The column is derived from this rather than stored beside it. Artwork scaling
    /// and table shape are measured against the column, so it has to be settled
    /// *before* the first build or the document is built against a guess and
    /// immediately thrown away. It is a pure function of the width (`ReaderLayout`),
    /// so this view can work it out for itself rather than waiting to be told by the
    /// text view it has not created yet — which is why nothing is built until the
    /// geometry reader has run once.
    @State private var paneWidth: CGFloat?

    /// How wide the contents panel is drawn, and how much of the pane it covers.
    private static let panelWidth: CGFloat = 320

    /// One glass-grouped toolbar button: the toggle's own footprint, which stays out
    /// on the panel and so is not part of what the spacer below has to reserve.
    private static let toggleGroupWidth: CGFloat = 56

    /// Derived from the pane's width, and nothing else.
    ///
    /// The panel does not appear here and must not: it is an overlay, so it takes no
    /// width from the pane, and the column is the same number whether it is showing
    /// or not. That is what keeps opening it from re-wrapping the document and — via
    /// `BuildInputs` — from rebuilding it and losing the reader's place. What the
    /// panel overlaps, it covers, and closing it uncovers.
    private var column: CGFloat? {
        paneWidth.map { ReaderLayout.column(forWidth: $0) }
    }

    private var metadata: RFCMetadata? { library.metadata(id) }
    private var isBookmarked: Bool { bookmarks.contains { $0.number == id.number } }

    /// Everything a build depends on. One trigger, so the document is built in one
    /// place whatever changed — a new RFC, the font-size slider, or a window resize.
    private struct BuildInputs: Equatable {
        /// Distinguishes "not fetched yet" from "fetched", so finishing a fetch
        /// triggers the build. It also carries a change of document on its own:
        /// `load()` clears `document` before awaiting the next one, so every new RFC
        /// arrives as a false → true transition and needs no id of its own here.
        let hasDocument: Bool
        let fontSize: Double
        let column: CGFloat?

        var style: ReadingStyle? {
            column.map { ReadingStyle(bodySize: fontSize, measure: $0) }
        }
    }

    private var buildInputs: BuildInputs {
        BuildInputs(hasDocument: document != nil, fontSize: fontSize, column: column)
    }

    var body: some View {
        content
            .navigationTitle(id.displayName)
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { toolbar }
            // Two presentations of the same panel.
            //
            // On macOS it is an overlay, and it has to be an overlay rather than any
            // of the things that look like one. `.inspector` is a split-view column,
            // so it splits the toolbar too and puts the reader beside the panel. A
            // `.safeAreaBar` looks closer — the system draws it on glass — but a safe
            // area is *reserved layout space*: the container sizes for the bar even
            // when the content ignores it, so opening the panel widened the window,
            // the wider window widened the pane, the wider pane changed the column,
            // and the column change rebuilt the document and lost the reader's place.
            // One modifier, four visible symptoms.
            //
            // An overlay claims nothing. The pane's width does not move, so neither
            // does the text, and there is no rebuild to lose a scroll position to.
            //
            // iOS keeps the inspector. A 320 pt panel pinned to the trailing edge
            // swallows an iPhone, and in compact width the inspector already presents
            // itself as a sheet.
            #if os(macOS)
            .overlay(alignment: .trailing) {
                if showTableOfContents, document != nil {
                    inspector
                        .frame(width: Self.panelWidth)
                        .frame(maxHeight: .infinity)
                        // Without this the list draws its own opaque sidebar
                        // background over the glass, and the panel stops being
                        // translucent at all.
                        .scrollContentBackground(.hidden)
                        // The glass runs the full height of the window, up behind the
                        // toolbar and down past the bottom edge, so the panel is a
                        // side of the window rather than a card floating inside the
                        // reader. Only the surface ignores the safe area: letting the
                        // content ignore it too pushes the Contents/References picker
                        // up behind the toolbar, where it cannot be seen or clicked.
                        .background {
                            Color.clear
                                .glassEffect(.regular, in: .rect)
                                .ignoresSafeArea(.container, edges: .vertical)
                        }
                        .transition(.move(edge: .trailing))
                }
            }
            #else
            .inspector(isPresented: $showTableOfContents) {
                if document != nil {
                    inspector.inspectorColumnWidth(min: 260, ideal: 320)
                }
            }
            #endif
            .task(id: id) { await load() }
            .task(id: buildInputs) { await rebuild() }
            .onChange(of: navigation.scrollRequest) { _, request in
                jump(toSection: request?.section)
            }
            .onDisappear(perform: saveReadingPosition)
            .environment(\.openURL, OpenURLAction(handler: handleLink))
    }

    @State private var scrollTarget: String?

    /// The contents and references panel, however the platform presents it.
    private var inspector: some View {
        DocumentInspector(
            sections: bodySections,
            groups: referenceGroups,
            tab: $inspectorTab,
            current: visibleAnchor,
            selectSection: { anchor in navigation.jump(toSection: anchor) },
            openDocument: { library.open($0, activation: .current, in: navigation) }
        )
    }

    /// The width channel. It wraps everything, including the loading state, so the
    /// column is known before there is a document to build.
    ///
    /// The floor is here rather than on the split view's detail column, where it
    /// guarded the reader *and* the panel together and so let the panel take all but
    /// 190 pt of it. This is the reader alone.
    private var content: some View {
        states
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width in
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
        if showOriginal {
            OriginalTextView(text: originalText, fontSize: fontSize)
                .task { originalText = try? await library.originalText(for: id) }
        } else if let document, let built {
            let headerIdentity = DocumentHeaderView.Identity(header: document.header, metadata: metadata)
            RFCTextView(
                built: built,
                lastVisibleAnchor: lastVisibleAnchor,
                scrollTarget: scrollTarget,
                onScrollHandled: { scrollTarget = nil },
                onVisibleAnchorChange: {
                    visibleAnchor = $0
                    // Recorded on the history entry when navigating away, so coming
                    // back returns here rather than to the top of the document.
                    navigation.visiblePosition = $0
                },
                onLink: openInApp,
                headerIdentity: headerIdentity,
                // Hosted outside the storage, so it needs the environment handed to
                // it: the banner's links to newer RFCs go through `LibraryModel`.
                header: {
                    DocumentHeaderView(library: library, navigation: navigation, identity: headerIdentity)
                        .padding(.top, 16)
                        .padding(.bottom, 12)
                }
            )
            .onAppear {
                // Deep link or restored reading position.
                if let request = navigation.scrollRequest {
                    jump(toSection: request.section)
                } else if let saved = savedPosition(), document.section(anchor: saved) != nil {
                    scrollTarget = saved
                }
            }
        } else if let loadError {
            ContentUnavailableView {
                Label("Couldn't load \(id.displayName)", systemImage: "wifi.exclamationmark")
            } description: {
                Text(loadError)
            } actions: {
                Button("Try Again") { Task { await load() } }
                Link("Open on rfc-editor.org", destination: RFCEditorEndpoints.infoPage(id))
            }
        } else {
            ProgressView("Loading \(id.displayName)…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                toggleBookmark()
            } label: {
                Label("Bookmark", systemImage: isBookmarked ? "bookmark.fill" : "bookmark")
            }
            .keyboardShortcut("d", modifiers: .command)

            Menu {
                ForEach(CitationStyle.allCases) { style in
                    Button(style.displayName) { copyCitation(style) }
                }
                Divider()
                Button("Copy Link to Current Section") {
                    let section = visibleAnchor.flatMap { document?.section(anchor: $0)?.number }
                    Clipboard.copy(RFCLink(id: id, section: section).webURL.absoluteString)
                }
            } label: {
                Label("Cite", systemImage: "quote.opening")
            }

            if let metadata {
                ShareLink(item: RFCEditorEndpoints.infoPage(id), subject: Text("\(id.displayName): \(metadata.title)"))
            }

            Menu {
                Toggle("Original Text", isOn: $showOriginal)
                Button("Open on rfc-editor.org") { systemOpenURL(RFCEditorEndpoints.infoPage(id)) }
                if let url = metadata?.errataURL {
                    Button("Errata") { systemOpenURL(url) }
                }
                Button("Datatracker") { systemOpenURL(RFCEditorEndpoints.datatracker(id)) }
            } label: {
                Label("More", systemImage: "ellipsis.circle")
            }

        }

        // Its own group, so the glass separates the panel's toggle from the
        // document's actions instead of running them together — as Pages separates
        // its inspector toggles from the document's. The toggle is last, the
        // rightmost thing in the toolbar, over the panel it opens.
        ToolbarSpacer(.fixed, placement: .primaryAction)

        // While the panel is showing, everything to its left is pushed off it.
        //
        // A split-view inspector gets this for free: it owns a section of the
        // titlebar, and AppKit lays the document's toolbar out in what is left. An
        // overlay owns nothing, so the toolbar keeps spanning the window and the
        // document's actions end up sitting on the panel's glass. Reserving the
        // panel's width here does by hand what the split view would have done, and
        // leaves the toggle itself out on the glass where Pages puts it.
        #if os(macOS)
        if showTableOfContents, document != nil {
            ToolbarItem(placement: .primaryAction) {
                Color.clear.frame(width: Self.panelWidth - Self.toggleGroupWidth, height: 1)
            }
            // Otherwise the reserved width joins the toggle's glass group and the two
            // render as one long empty pill running back across the panel.
            .sharedBackgroundVisibility(.hidden)
        }
        #endif

        ToolbarItem(placement: .primaryAction) {
            Button {
                // An overlay is ordinary content and would otherwise appear and
                // vanish between frames; `.inspector` animated itself.
                withAnimation(.snappy) { showTableOfContents.toggle() }
            } label: {
                Label("Contents", systemImage: "list.bullet.indent")
            }
            .keyboardShortcut("t", modifiers: [.command, .shift])
        }
    }

    // MARK: - Actions

    /// Fetches. Building is `rebuild()`'s job, which this triggers by setting
    /// `document`.
    private func load() async {
        loadError = nil
        document = nil
        built = nil
        bodySections = []
        referenceGroups = []
        // A reused view must not carry the previous document's place into the new
        // one; `install()` reports the real anchor a moment later.
        visibleAnchor = nil
        lastVisibleAnchor.anchor = nil
        showOriginal = preferOriginalText
        do {
            let loaded = try await library.document(for: id)
            referenceGroups = ReferenceGroup.groups(in: loaded)
            document = loaded
        } catch {
            loadError = error.localizedDescription
        }
    }

    /// The one place the document is built.
    ///
    /// A rebuild costs the whole attributed string plus a full relayout — 650 ms on
    /// the largest documents in the library — so a change to an *existing* document's
    /// style waits that long to settle, and `.task(id:)` cancels the pending rebuild
    /// on every further tick of the font-size slider or the window's edge. The first
    /// build of a document does not wait: there is nothing on screen to disturb, and
    /// the column is already known, so it is built once and built right.
    private func rebuild() async {
        guard let document, let style = buildInputs.style else { return }
        if built != nil {
            try? await Task.sleep(for: .milliseconds(650))
            guard !Task.isCancelled else { return }
        }
        // Off the main actor: this is string assembly and text measurement, and
        // blocking the main thread for it is what made the font-size slider stutter.
        let place = built == nil ? nil : lastVisibleAnchor.anchor
        let rebuilt = await Task.detached { DocumentTextBuilder.build(document, style: style) }.value
        guard !Task.isCancelled else { return }
        built = rebuilt
        // The sections the storage actually holds, straight from the index the
        // builder just emitted — rather than re-deriving "is this a bibliography?"
        // from the model and hoping the two rules stay in step. A contents row that
        // has no anchor is a destination `scroll(to:)` cannot reach.
        // Taken once: `AnchorIndex.sections` filters, sorts and re-indexes every
        // anchor in the document, so asking inside the filter would rebuild the
        // whole index once per section.
        let sections = rebuilt.anchors.sections
        bodySections = document.allSections.filter { sections.offset(of: $0.anchor) != nil }
        // Only a restyle has a place to restore; a first build lets `onAppear` decide
        // between a deep link and the saved reading position.
        if let place { scrollTarget = place }
    }

    /// Resolves a section number or an anchor to the anchor the reader scrolls to.
    private func jump(toSection section: String?) {
        guard let section, let document else { return }
        scrollTarget = (document.section(number: section) ?? document.section(anchor: section))?.anchor ?? section
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
        case .document(let link):
            library.open(link, activation: activation, in: navigation)
        case .unhandled:
            return false
        }
        return true
    }

    private func toggleBookmark() {
        if let existing = bookmarks.first(where: { $0.number == id.number }) {
            modelContext.delete(existing)
        } else {
            modelContext.insert(Bookmark(number: id.number, title: metadata?.title ?? document?.header.title ?? id.displayName))
        }
    }

    private func copyCitation(_ style: CitationStyle) {
        guard let metadata else { return }
        let section = visibleAnchor.flatMap { document?.section(anchor: $0)?.number }
        Clipboard.copy(CitationFormatter().cite(metadata, section: style == .bibtex ? nil : section, style: style))
    }

    private func savedPosition() -> String? {
        let number = id.number
        let descriptor = FetchDescriptor<ReadingPosition>(predicate: #Predicate { $0.number == number })
        return try? modelContext.fetch(descriptor).first?.sectionAnchor
    }

    private func saveReadingPosition() {
        let anchor = lastVisibleAnchor.anchor
        let number = id.number
        let descriptor = FetchDescriptor<ReadingPosition>(predicate: #Predicate { $0.number == number })
        if let existing = try? modelContext.fetch(descriptor).first {
            existing.sectionAnchor = anchor
            existing.updatedAt = .now
        } else {
            modelContext.insert(ReadingPosition(number: number, sectionAnchor: anchor))
        }
    }
}

// MARK: - Pieces

/// Everything above the first line of prose: title, badges, authors, and the status
/// banner. Hosted in the text view's top content inset, so it scrolls with the body
/// without being part of it — the banner carries buttons, and nobody selects through
/// it. The abstract is no longer here; it is the first prose in the storage, which is
/// what puts the banner between the title and the abstract as `VISION.md` asks.
struct DocumentHeaderView: View {
    /// Passed down for the same reason `StatusBanner` takes them: this whole subtree
    /// is hosted outside the SwiftUI hierarchy.
    let library: LibraryModel
    let navigation: NavigationModel

    /// Exactly what the body below reads, and nothing else.
    ///
    /// The header is hosted in a `UIHostingController`/`NSHostingController` that
    /// sits outside SwiftUI's diffing, so assigning `rootView` re-renders the whole
    /// subtree — on every update pass, which includes every section crossing while
    /// scrolling. Comparing this decides whether that assignment is needed at all.
    /// It is also the view's input, so a field it does not carry is a field the
    /// header cannot display, and the two cannot fall out of step.
    struct Identity: Equatable {
        let title: String
        let date: String?
        let workingGroup: String?
        let authors: [String]
        /// Everything else the header shows comes straight off the metadata, which
        /// is `Hashable` — so it is compared whole rather than field by field.
        let metadata: RFCMetadata?

        init(header: DocumentHeader, metadata: RFCMetadata?) {
            title = header.title
            date = (header.date ?? metadata?.date)?.formatted
            workingGroup = header.workingGroup ?? metadata?.workingGroup
            let authors = header.authors.isEmpty ? (metadata?.authors ?? []) : header.authors
            self.authors = authors.map { $0.role == nil ? $0.name : "\($0.name), Ed." }
            self.metadata = metadata
        }
    }

    /// The view renders from the identity rather than beside it, so the two cannot
    /// describe different headers.
    let identity: Identity

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(identity.title)
                .font(.largeTitle.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                if let metadata = identity.metadata {
                    StatusBadge(status: metadata.currentStatus)
                    Text(metadata.stream.displayName)
                }
                if let date = identity.date {
                    Text(date)
                }
                if let group = identity.workingGroup {
                    Text(group)
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            if !identity.authors.isEmpty {
                Text(identity.authors.joined(separator: ", "))
                    .font(.subheadline)
            }
            if let metadata = identity.metadata {
                StatusBanner(library: library, navigation: navigation, metadata: metadata)
                    .padding(.top, 4)
            }
        }
        // The header is hosted, not placed by SwiftUI, and a hosting view lays its
        // root out at that root's own width rather than at the frame the coordinator
        // gave it — so a `VStack` that hugs its content ends up somewhere other than
        // the column's leading edge, and by a distance that changes with the title's
        // length. Filling the column is the same instruction the body text gets.
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The single most important piece of context: is this still the current document?
struct StatusBanner: View {
    /// Handed over rather than read from the environment.
    ///
    /// This view is hosted in an `NSHostingController`/`UIHostingController` in the
    /// text view's top inset — outside the SwiftUI tree that `ContentView` injects
    /// into — so an `@Environment` lookup here is a runtime trap waiting to fire
    /// rather than a compile-time requirement. The two models arrive as properties so
    /// the compiler is the thing that notices when a call site forgets one.
    let library: LibraryModel
    let navigation: NavigationModel
    let metadata: RFCMetadata

    var body: some View {
        if metadata.isObsolete || !metadata.updatedBy.isEmpty || metadata.hasErrata {
            VStack(alignment: .leading, spacing: 6) {
                if metadata.isObsolete {
                    row("Obsoleted by", metadata.obsoletedBy, symbol: "exclamationmark.triangle.fill", tint: .red)
                }
                if !metadata.updatedBy.isEmpty {
                    row("Updated by", metadata.updatedBy, symbol: "arrow.triangle.2.circlepath", tint: .orange)
                }
                if metadata.hasErrata, let url = metadata.errataURL {
                    Link(destination: url) {
                        Label("This RFC has errata", systemImage: "pencil.and.list.clipboard")
                    }
                    .font(.subheadline)
                }
            }
            .padding(12)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
        }
    }

    private func row(_ title: String, _ ids: [DocumentID], symbol: String, tint: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: symbol).foregroundStyle(tint)
            Text(title).fontWeight(.medium)
            ForEach(ids, id: \.self) { id in
                Button(id.displayName) { library.open(id, activation: .current, in: navigation) }
                    .buttonStyle(.plain)
                    .foregroundStyle(.tint)
            }
        }
        .font(.subheadline)
    }
}

struct OriginalTextView: View {
    let text: String?
    let fontSize: Double

    var body: some View {
        if let text {
            ScrollView([.vertical, .horizontal]) {
                Text(text)
                    .font(.system(size: fontSize * 0.85, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(24)
            }
        } else {
            ProgressView()
        }
    }
}

struct TableOfContentsView: View {
    /// Only the sections the storage holds; see `DocumentView.bodySections`.
    let sections: [RFCKit.Section]
    let current: String?
    let select: (String) -> Void

    var body: some View {
        List {
            ForEach(sections) { section in
                Button {
                    select(section.anchor)
                } label: {
                    Text(section.displayTitle)
                        .lineLimit(2)
                        .padding(.leading, CGFloat(max(0, section.depth - 1)) * 12)
                        .fontWeight(section.anchor == current ? .semibold : .regular)
                }
                .buttonStyle(.plain)
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Contents")
    }
}

enum Clipboard {
    static func copy(_ string: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
        #else
        UIPasteboard.general.string = string
        #endif
    }
}
