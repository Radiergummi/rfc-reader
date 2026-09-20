import RFCKit
import SwiftData
import SwiftUI

struct ContentView: View {
    @Environment(LibraryModel.self) private var library
    @State private var columnVisibility = NavigationSplitViewVisibility.all

    var body: some View {
        @Bindable var library = library
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 200, ideal: 240)
        } content: {
            RFCListView()
                .navigationSplitViewColumnWidth(min: 280, ideal: 360)
        } detail: {
            if let selection = library.selection {
                DocumentView(id: selection)
                    .id(selection)
            } else {
                EmptyDetailView()
            }
        }
        .sheet(isPresented: $library.isShowingGoToSheet) {
            GoToDocumentSheet()
        }
        .focusedSceneValue(\.openDocumentAction) {
            library.isShowingGoToSheet = true
        }
    }
}

struct EmptyDetailView: View {
    @Environment(LibraryModel.self) private var library

    var body: some View {
        ContentUnavailableView {
            Label("Pick an RFC", systemImage: "doc.text.magnifyingglass")
        } description: {
            Text("Browse the sidebar, search, or jump straight to a number.")
        } actions: {
            Button("Go to RFC…") { library.isShowingGoToSheet = true }
                .keyboardShortcut("l", modifiers: .command)
        }
    }
}

/// Command-L style jump: accepts a number, `RFC 9110`, `BCP 14`, or any RFC Editor / Datatracker URL.
struct GoToDocumentSheet: View {
    @Environment(LibraryModel.self) private var library
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
        library.open(link)
        dismiss()
    }
}
