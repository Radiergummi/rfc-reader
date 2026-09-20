import RFCKit
import SwiftUI

struct SidebarView: View {
    @Environment(LibraryModel.self) private var library

    var body: some View {
        @Bindable var library = library
        List(selection: $library.filter) {
            Section("Library") {
                row(.bookmarks)
                row(.recent)
                row(.downloaded)
            }
            Section("Browse") {
                row(.all)
                row(.standards)
                row(.bestCurrentPractice)
                ForEach([Stream.ietf, .irtf, .iab, .independent], id: \.self) { stream in
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
                            library.open(recent.id)
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
        .safeAreaInset(edge: .bottom) {
            IndexStatusView()
        }
    }

    private func row(_ filter: LibraryFilter) -> some View {
        Label(filter.title, systemImage: filter.systemImage).tag(filter)
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
