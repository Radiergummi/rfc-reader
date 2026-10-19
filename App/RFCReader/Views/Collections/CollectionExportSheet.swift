import RFCKit
import RFCReaderKit
import SwiftUI
import UniformTypeIdentifiers

/// Which collection's export sheet is on show (#385).
struct CollectionExportRequest: Identifiable, Hashable {
  let collection: UUID
  var id: UUID { collection }
}

/// Every RFC of a collection exported into a folder named after it (#385): the
/// format chosen, the files made with one progress that can be cancelled, what
/// could not be exported named, then the folder saved where the reader picks.
struct CollectionExportSheet: View {
  let request: CollectionExportRequest

  @Environment(LibraryModel.self) private var library
  @Environment(\.dismiss) private var dismiss
  @State private var format = ExportFormat.pdf
  @State private var export = CollectionExportSession(
    workspace: FileManager.default.temporaryDirectory
      .appending(path: "Collection Export", directoryHint: .isDirectory)
      .appending(path: UUID().uuidString, directoryHint: .isDirectory))
  @State private var isSaving = false
  @State private var saveError: String?

  private var entry: CollectionSnapshot.Entry? { library.collections[request.collection] }

  var body: some View {
    content
      // A swipe would end an export under way without a word.
      .interactiveDismissDisabled(export.isExporting)
      .onDisappear { export.end() }
      .fileExporter(
        isPresented: $isSaving,
        document: export.folder.map { ExportedFolder(url: $0) },
        contentType: .folder,
        defaultFilename: export.folder?.lastPathComponent
      ) { result in
        switch result {
        case .success: dismiss()
        // Canceled or failed, the finished export stays, to be saved again.
        case .failure(let error as CocoaError) where error.code == .userCancelled: break
        case .failure(let error): saveError = error.localizedDescription
        }
      }
      .alert(
        "Couldn't save the folder",
        isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })
      ) {
        Button("OK") { saveError = nil }
      } message: {
        Text(verbatim: saveError ?? "")
      }
  }

  @ViewBuilder
  private var content: some View {
    #if os(macOS)
      VStack(alignment: .leading, spacing: 12) {
        Text(title).font(.headline)
        fields
        HStack {
          Spacer()
          cancelButton.keyboardShortcut(.cancelAction)
          confirmButton.keyboardShortcut(.defaultAction)
        }
      }
      .padding(20)
      .frame(width: 380)
    #else
      NavigationStack {
        Form { fields }
          .navigationTitle(title)
          .navigationBarTitleDisplayMode(.inline)
          .toolbar {
            ToolbarItem(placement: .cancellationAction) { cancelButton }
            ToolbarItem(placement: .confirmationAction) { confirmButton }
          }
      }
      .presentationDetents([.medium, .large])
    #endif
  }

  private var title: String {
    String(localized: "Export “\(entry?.name ?? "")”")
  }

  @ViewBuilder
  private var fields: some View {
    switch export.phase {
    case .choosing:
      Picker("Format:", selection: $format) {
        ForEach(CollectionExport.formats) { format in
          Text(verbatim: format.name()).tag(format)
        }
      }
    case .exporting(let progress):
      ProgressView(value: Double(progress.done), total: Double(max(progress.total, 1))) {
        Text("Exporting…")
      }
    case .finished(let report):
      if report.wasCanceled {
        Text("The export was canceled.")
      } else if report.skipped.isEmpty {
        Text("Every RFC was exported.")
      } else {
        Text("These RFCs were not exported:")
        skipped(report.skippedLines)
      }
    }
  }

  /// What could not be exported, which a collection exported offline can make
  /// long: scrolled, so the buttons stay in reach.
  @ViewBuilder
  private func skipped(_ lines: [String]) -> some View {
    #if os(macOS)
      ScrollView {
        VStack(alignment: .leading, spacing: 4) { skippedLines(lines) }
          .frame(maxWidth: .infinity, alignment: .leading)
      }
      .frame(maxHeight: 200)
    #else
      skippedLines(lines)
    #endif
  }

  private func skippedLines(_ lines: [String]) -> some View {
    ForEach(lines, id: \.self) { line in
      Text(verbatim: line).font(.callout).foregroundStyle(.secondary)
    }
  }

  private var cancelButton: some View {
    Button("Cancel", role: .cancel) {
      export.end()
      dismiss()
    }
  }

  @ViewBuilder
  private var confirmButton: some View {
    switch export.phase {
    case .choosing:
      Button("Export") { start() }
        .disabled(entry == nil)
    case .exporting:
      Button("Export") {}.disabled(true)
    case .finished(let report):
      if report.exported.isEmpty || report.wasCanceled {
        Button("Done") { dismiss() }
      } else {
        Button("Save…") { isSaving = true }
      }
    }
  }

  private func start() {
    guard let entry else { return }
    let plan = CollectionExport(entry, format: format)
    let paperSize = PrintLayout.paperSize(for: .current)
    let library = library
    export.start(plan) { id in
      try await DocumentExport.data(
        for: id, as: plan.format, paperSize: paperSize, library: library)
    }
  }
}

/// A folder of exported files, for SwiftUI's `fileExporter`, which saves it under
/// the name it is given. Written only, and read from the disk as it is saved.
nonisolated struct ExportedFolder: FileDocument {
  static var readableContentTypes: [UTType] { [] }
  static var writableContentTypes: [UTType] { [.folder] }

  let url: URL

  init(url: URL) {
    self.url = url
  }

  init(configuration: ReadConfiguration) throws {
    throw CocoaError(.fileReadUnsupportedScheme)
  }

  func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
    try FileWrapper(url: url)
  }
}
