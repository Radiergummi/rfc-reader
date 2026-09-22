import RFCKit
import SwiftUI

struct SidebarView: View {
    @Environment(LibraryModel.self) private var library
    @Environment(NavigationModel.self) private var navigation

    var body: some View {
        @Bindable var navigation = navigation
        List(selection: selection) {
            Section("Library") {
                row(.bookmarks)
                row(.recent)
                row(.downloaded)
            }
            Section("Browse") {
                row(.all)
                row(.standards)
                row(.bestCurrentPractice)
                ForEach([RFCKit.Stream.ietf, .irtf, .iab, .independent], id: \.self) { stream in
                    row(.stream(stream))
                }
            }
            if !library.topWorkingGroups.isEmpty {
                Section("Working Groups") {
                    ForEach(library.topWorkingGroups, id: \.self) { group in
                        row(.workingGroup(group))
                    }
                }
            }
            if !library.recent.isEmpty {
                Section("Just Published") {
                    ForEach(library.recent.prefix(5)) { recent in
                        Button {
                            library.open(recent.id, activation: .current, in: navigation)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(recent.id.displayName).font(.caption).foregroundStyle(.secondary)
                                Text(recent.title).lineLimit(2)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .navigationTitle("RFCs")
        // Search lives on the sidebar, not on the list it filters.
        //
        // `.searchable` on the list column puts the field at the trailing end of the
        // window's toolbar, outboard of everything the document declares — so the
        // contents toggle could not be the rightmost item, and the field ran on past
        // the panel's leading edge and under its glass. Declared here with
        // `.sidebar`, it sits in the sidebar itself, which leaves the toolbar's
        // trailing end to the panel's toggle. The text it binds to lives on
        // `NavigationModel`, so `RFCListView` filters on it exactly as before.
        .searchable(text: $navigation.searchText, placement: .sidebar, prompt: "Search")
        .labelStyle(SidebarLabelStyle())
        .safeAreaInset(edge: .bottom) {
            IndexStatusView()
        }
    }

    /// iOS only offers `List(selection:)` with an optional binding, and deselecting
    /// should leave the current filter in place rather than clear it.
    private var selection: Binding<LibraryFilter?> {
        Binding(
            get: { navigation.filter },
            set: { if let new = $0 { navigation.filter = new } }
        )
    }

    private func row(_ filter: LibraryFilter) -> some View {
        Label(filter.title, systemImage: filter.systemImage).tag(filter)
    }
}

/// Gives every sidebar row's icon a column of its own, so the titles line up however
/// wide the glyph is.
///
/// `Label` sizes the icon to the symbol and leaves it at that. Most of the sidebar's
/// symbols carry enough of their own whitespace to look spaced anyway; the wide ones
/// do not, and `person.3` — 28 pt against `bookmark`'s 14 — ran straight into its
/// title. Spacing alone would fix that row and leave the titles on a ragged edge, so
/// the icon gets a fixed column instead and the two problems go away together.
private struct SidebarLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        Row(icon: configuration.icon, title: configuration.title)
    }

    private struct Row: View {
        let icon: LabelStyleConfiguration.Icon
        let title: LabelStyleConfiguration.Title
        /// Wide enough for the widest symbol the sidebar uses, and scaled with the
        /// text so the column still holds at larger accessibility sizes.
        @ScaledMetric(relativeTo: .body) private var column: CGFloat = 22

        var body: some View {
            HStack(spacing: 6) {
                icon.frame(width: column)
                title
            }
        }
    }
}

struct IndexStatusView: View {
    @Environment(LibraryModel.self) private var library

    var body: some View {
        HStack(spacing: 6) {
            switch library.indexState {
            case .idle, .loading:
                ProgressView().controlSize(.mini)
                Text("Loading index…")
            case .ready(let count, let updatedAt):
                Text("\(count) RFCs · updated \(updatedAt, format: .relative(presentation: .named))")
            case .failed(let message):
                Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)
                Text(message).lineLimit(2)
                Button("Retry") { Task { await library.refreshIndex() } }.buttonStyle(.borderless)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(8)
        .frame(maxWidth: .infinity)
        .background(.bar)
    }
}
