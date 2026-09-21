import RFCKit
import RFCReaderKit
import SwiftData
import SwiftUI

struct ContentView: View {
    @Environment(LibraryModel.self) private var library
    @State private var columnVisibility = NavigationSplitViewVisibility.all
    /// This scene's own navigation state. `@State` here is what makes a tab a tab:
    /// every window and tab instantiates `ContentView` afresh, so each gets its own
    /// selection, filter, search text and back/forward stack. Shared library state —
    /// the index, the cache — stays on the environment's `LibraryModel`.
    @State private var navigation = NavigationModel()

    /// Short enough to survive a tab: the document's designation, not its title.
    private var windowTitle: String {
        navigation.selection?.displayName ?? navigation.filter.title
    }

    /// The prose title goes here, where macOS has room for it — truncated, because a
    /// tab is far narrower than the window and clips rather than eliding.
    private var windowSubtitle: String {
        navigation.selection
            .flatMap { library.metadata($0)?.title }?
            .truncated(to: Self.subtitleLimit) ?? ""
    }

    /// Long enough that most RFC titles survive whole, short enough that the series'
    /// genuinely long ones stop before the tab's edge.
    private static let subtitleLimit = 64

    var body: some View {
        @Bindable var navigation = navigation
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 200, ideal: 240)
        } content: {
            RFCListView()
                .navigationSplitViewColumnWidth(min: 280, ideal: 360)
        } detail: {
            if let selection = navigation.selection {
                DocumentView(id: selection)
                    .id(selection)
            } else {
                EmptyDetailView()
            }
        }
        .environment(navigation)
        // The window's title, and therefore the tab's.
        //
        // Only one `navigationTitle` in a `NavigationSplitView` reaches the window,
        // and the list column's was winning it — so every tab read "All RFCs"
        // whatever it was showing, while the subtitle set here came through
        // untouched because nothing competed for it. The list column no longer sets
        // one: the sidebar already shows which filter is active, so that title was
        // spending the window's only title slot on something said elsewhere.
        .navigationTitle(windowTitle)
        #if os(macOS)
        .navigationSubtitle(windowSubtitle)
        #endif
        // On the split view rather than on `DocumentView`: macOS gives the detail
        // column no leading toolbar slot — a `.navigation` item declared down there is
        // silently dropped — and scene-level navigation belongs beside the sidebar
        // toggle anyway, not with the document's own actions.
        //
        // Always present, dimmed when there is nowhere to go, as Safari does. A pair
        // that appears and vanishes with the history shifts everything beside it.
        .toolbar {
            ToolbarItem(placement: .navigation) {
                ControlGroup {
                    Button {
                        navigation.goBack()
                    } label: {
                        Label("Back", systemImage: "chevron.backward")
                    }
                    .disabled(!navigation.canGoBack)

                    Button {
                        navigation.goForward()
                    } label: {
                        Label("Forward", systemImage: "chevron.forward")
                    }
                    .disabled(!navigation.canGoForward)
                }
                .controlGroupStyle(.navigation)
            }
        }
        .onAppear {
            library.register(navigation)
            // Set by whoever asked for this window; nil when it was opened from the
            // menu or at launch, which lands on the library as before.
            if let link = library.takePendingSceneLink() {
                navigation.open(link, in: library.index)
            }
        }
        .onDisappear { library.unregister(navigation) }
        // Any navigation in this tab makes it the one an untargeted deep link lands in.
        .onChange(of: navigation.selection) { library.activate(navigation) }
        .sheet(isPresented: $navigation.isShowingGoToSheet) {
            GoToDocumentSheet()
        }
        .focusedSceneValue(\.openDocumentAction) {
            navigation.isShowingGoToSheet = true
        }
        .focusedSceneValue(\.navigationModel, navigation)
    }
}

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

/// Command-L style jump: accepts a number, `RFC 9110`, `BCP 14`, or any RFC Editor / Datatracker URL.
struct GoToDocumentSheet: View {
    @Environment(LibraryModel.self) private var library
    @Environment(NavigationModel.self) private var navigation
    @Environment(\.dismiss) private var dismiss
    @State private var input = ""
    @FocusState private var focused: Bool

    private var resolved: RFCLink? {
        if let url = URL(string: input.trimmingCharacters(in: .whitespaces)), url.scheme != nil, let link = RFCLink(url: url) {
            return link
        }
        return DocumentID(parsing: input).map { RFCLink(id: $0) }
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("RFC number or link", text: $input)
                    .focused($focused)
                    .onSubmit(open)
                    #if !os(macOS)
                    .keyboardType(.numbersAndPunctuation)
                    .textInputAutocapitalization(.never)
                    #endif
                if let link = resolved, let metadata = library.metadata(link.id) {
                    LabeledContent(link.id.displayName, value: metadata.title)
                } else if !input.isEmpty, resolved == nil {
                    Text("Not something I recognise as an RFC.").foregroundStyle(.secondary)
                }
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
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 160)
        #endif
    }

    private func open() {
        guard let link = resolved else { return }
        navigation.open(link, in: library.index)
        dismiss()
    }
}
