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
    /// The document as one attributed string plus its anchor index. Built in
    /// `load()` and on a settled font-size change — never in `body`, which would
    /// rebuild the whole document on every redraw.
    @State private var built: BuiltDocument?
    /// Every `Section.anchor` in the document. The anchor index the builder emits is
    /// wider than this on purpose — figures, tables and reference rows are in it too,
    /// so `rfc-anchor:` links reach them — but `visibleAnchor`'s four consumers all
    /// resolve it with `document.section(anchor:)`, so only these may be reported.
    @State private var sectionAnchors: Set<String> = []
    @State private var originalText: String?
    @State private var loadError: String?
    @State private var showOriginal = false
    @State private var showTableOfContents = false
    @State private var visibleAnchor: String?
    @State private var copiedStyle: CitationStyle?

    private var metadata: RFCMetadata? { library.metadata(id) }
    private var isBookmarked: Bool { bookmarks.contains { $0.number == id.number } }
    private var readingStyle: ReadingStyle { ReadingStyle(bodySize: fontSize) }

    var body: some View {
        content
            .navigationTitle(id.displayName)
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { toolbar }
            .inspector(isPresented: $showTableOfContents) {
                if let document {
                    TableOfContentsView(document: document, current: visibleAnchor) { anchor in
                        library.pendingSection = nil
                        scrollTarget = anchor
                    }
                    .inspectorColumnWidth(min: 220, ideal: 280)
                }
            }
            .task(id: id) { await load() }
            .task(id: fontSize) { await restyle() }
            .onChange(of: library.pendingSection) { _, section in
                jump(toSection: section)
            }
            .onDisappear(perform: saveReadingPosition)
            .environment(\.openURL, OpenURLAction(handler: handleLink))
    }

    @State private var scrollTarget: String?

    @ViewBuilder
    private var content: some View {
        if showOriginal {
            OriginalTextView(text: originalText, fontSize: fontSize)
                .task { originalText = try? await library.originalText(for: id) }
        } else if let document, let built {
            RFCTextView(
                built: built,
                trackedAnchors: sectionAnchors,
                scrollTarget: scrollTarget,
                onScrollHandled: { scrollTarget = nil },
                onVisibleAnchorChange: { visibleAnchor = $0 },
                onLink: { openInApp($0) },
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

    private func load() async {
        loadError = nil
        built = nil
        showOriginal = preferOriginalText
        do {
            let loaded = try await library.document(for: id)
            document = loaded
            sectionAnchors = Set(loaded.allSections.map(\.anchor))
            built = DocumentTextBuilder.build(loaded, style: readingStyle)
        } catch {
            loadError = error.localizedDescription
        }
    }

    /// A font-size change costs a rebuild of the whole attributed string plus a full
    /// relayout — 650 ms on the largest documents in the library — so the slider is
    /// debounced by that much. `.task(id:)` cancels the pending rebuild on every
    /// further tick, and the anchor index puts the reader back where they were.
    private func restyle() async {
        guard let document, built != nil else { return }
        try? await Task.sleep(for: .milliseconds(650))
        guard !Task.isCancelled else { return }
        let place = visibleAnchor
        built = DocumentTextBuilder.build(document, style: readingStyle)
        scrollTarget = place
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
        if url.scheme == DocumentTextBuilder.anchorScheme {
            let anchor = url.absoluteString.dropFirst(DocumentTextBuilder.anchorScheme.count + 1)
                .removingPercentEncoding ?? ""
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
        let number = id.number
        let descriptor = FetchDescriptor<ReadingPosition>(predicate: #Predicate { $0.number == number })
        if let existing = try? modelContext.fetch(descriptor).first {
            existing.sectionAnchor = visibleAnchor
            existing.updatedAt = .now
        } else {
            modelContext.insert(ReadingPosition(number: number, sectionAnchor: visibleAnchor))
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
    let document: RFCDocument
    let current: String?
    let select: (String) -> Void

    var body: some View {
        List {
            ForEach(document.allSections) { section in
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
