import RFCKit
import RFCReaderKit
import SwiftData
import SwiftUI

/// The reader. Renders an `RFCDocument` natively and handles every in-document link.
struct DocumentView: View {
    @Environment(LibraryModel.self) private var library
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
    @State private var copiedStyle: CitationStyle?
    /// The text column this view's width implies, and nil until a width is known.
    ///
    /// Artwork scaling and table shape are measured against the column, so the column
    /// has to be settled *before* the first build or the document is built against a
    /// guess and immediately thrown away. It is a pure function of the width
    /// (`ReaderLayout`), so this view can work it out for itself rather than waiting
    /// to be told by the text view it has not created yet — which is why nothing is
    /// built until the geometry reader has run once.
    @State private var column: CGFloat?

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
            .inspector(isPresented: $showTableOfContents) {
                if let document {
                    DocumentInspector(
                        document: document,
                        sections: bodySections,
                        groups: referenceGroups,
                        tab: $inspectorTab,
                        current: visibleAnchor,
                        selectSection: { anchor in
                            library.pendingSection = nil
                            scrollTarget = anchor
                        },
                        openDocument: { library.open($0) }
                    )
                    .inspectorColumnWidth(min: 260, ideal: 320)
                }
            }
            .task(id: id) { await load() }
            .task(id: buildInputs) { await rebuild() }
            .onChange(of: library.pendingSection) { _, section in
                jump(toSection: section)
            }
            .onDisappear(perform: saveReadingPosition)
            .environment(\.openURL, OpenURLAction(handler: handleLink))
    }

    @State private var scrollTarget: String?

    /// The width channel. It wraps everything, including the loading state, so the
    /// column is known before there is a document to build.
    private var content: some View {
        states
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width in
                guard width > 0 else { return }
                column = ReaderLayout.column(forWidth: width)
            }
    }

    @ViewBuilder
    private var states: some View {
        if showOriginal {
            OriginalTextView(text: originalText, fontSize: fontSize)
                .task { originalText = try? await library.originalText(for: id) }
        } else if let document, let built {
            RFCTextView(
                built: built,
                lastVisibleAnchor: lastVisibleAnchor,
                scrollTarget: scrollTarget,
                onScrollHandled: { scrollTarget = nil },
                onVisibleAnchorChange: { visibleAnchor = $0 },
                onLink: { openInApp($0) },
                headerIdentity: DocumentHeaderView.Identity(header: document.header, metadata: metadata),
                // Hosted outside the storage, so it needs the environment handed to
                // it: the banner's links to newer RFCs go through `LibraryModel`.
                header: {
                    DocumentHeaderView(header: document.header, metadata: metadata)
                        .environment(library)
                        .padding(.top, 16)
                        .padding(.bottom, 12)
                }
            )
            .onAppear {
                // Deep link or restored reading position.
                if library.pendingSection != nil {
                    jump(toSection: library.pendingSection)
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

            Button {
                showTableOfContents.toggle()
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
        bodySections = document.allSections.filter { rebuilt.anchors.sections.offset(of: $0.anchor) != nil }
        // Only a restyle has a place to restore; a first build lets `onAppear` decide
        // between a deep link and the saved reading position.
        if let place { scrollTarget = place }
    }

    private func jump(toSection section: String?) {
        guard let section, let document else { return }
        if let target = document.section(number: section) ?? document.section(anchor: section) {
            scrollTarget = target.anchor
        }
        library.pendingSection = nil
    }

    /// Cross references arrive as URLs from the attributed text; anything else goes to the system.
    private func handleLink(_ url: URL) -> OpenURLAction.Result {
        openInApp(url) ? .handled : .systemAction
    }

    /// The same decision as `handleLink`, as a `Bool`: the text view's delegate wants
    /// to know whether to fall back to its own action, and `OpenURLAction.Result` is
    /// not `Equatable`.
    private func openInApp(_ url: URL) -> Bool {
        if let anchor = DocumentTextBuilder.anchor(from: url) {
            scrollTarget = anchor
            return true
        }
        if let link = RFCLink(url: url) {
            if link.id == id, let section = link.section {
                jump(toSection: section)
            } else {
                library.open(link)
            }
            return true
        }
        return false
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
        copiedStyle = style
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
    /// Exactly what the body below reads, and nothing else.
    ///
    /// The header is hosted in a `UIHostingController`/`NSHostingController` that
    /// sits outside SwiftUI's diffing, so assigning `rootView` re-renders the whole
    /// subtree — on every update pass, which includes every section crossing while
    /// scrolling. Comparing this decides whether that assignment is needed at all.
    /// It has to list every field the view displays, or a header goes stale; the
    /// compiler cannot check that, so the two are kept adjacent.
    struct Identity: Equatable {
        let title: String
        let date: String?
        let workingGroup: String?
        let authors: [String]
        let status: String?
        let stream: String?
        let obsoletedBy: [DocumentID]
        let updatedBy: [DocumentID]
        let hasErrata: Bool

        init(header: DocumentHeader, metadata: RFCMetadata?) {
            title = header.title
            date = (header.date ?? metadata?.date)?.formatted
            workingGroup = header.workingGroup ?? metadata?.workingGroup
            let authors = header.authors.isEmpty ? (metadata?.authors ?? []) : header.authors
            self.authors = authors.map { $0.role == nil ? $0.name : "\($0.name), Ed." }
            status = metadata.map { String(describing: $0.currentStatus) }
            stream = metadata?.stream.displayName
            obsoletedBy = metadata?.obsoletedBy ?? []
            updatedBy = metadata?.updatedBy ?? []
            hasErrata = metadata?.hasErrata ?? false
        }
    }

    let header: DocumentHeader
    let metadata: RFCMetadata?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(header.title)
                .font(.largeTitle.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                if let metadata {
                    StatusBadge(status: metadata.currentStatus)
                    Text(metadata.stream.displayName)
                }
                if let date = header.date ?? metadata?.date {
                    Text(date.formatted)
                }
                if let group = header.workingGroup ?? metadata?.workingGroup {
                    Text(group)
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            let authors = header.authors.isEmpty ? (metadata?.authors ?? []) : header.authors
            if !authors.isEmpty {
                Text(authors.map { $0.role == nil ? $0.name : "\($0.name), Ed." }.joined(separator: ", "))
                    .font(.subheadline)
            }
            if let metadata {
                StatusBanner(metadata: metadata)
                    .padding(.top, 4)
            }
        }
    }
}

/// The single most important piece of context: is this still the current document?
struct StatusBanner: View {
    @Environment(LibraryModel.self) private var library
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
                Button(id.displayName) { library.open(id) }
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
