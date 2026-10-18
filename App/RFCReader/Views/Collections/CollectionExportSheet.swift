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
  @State private var export = CollectionExportModel()
  @State private var isSaving = false

  private var entry: CollectionSnapshot.Entry? { library.collections[request.collection] }

  var body: some View {
    content
      .onDisappear { export.cancel() }
      .fileExporter(
        isPresented: $isSaving, document: export.folder, contentType: .folder,
        defaultFilename: export.folder?.name
      ) { _ in
        dismiss()
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
          buttons
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
      .presentationDetents([.medium])
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
      if report.wasCancelled {
        Text("The export was cancelled.")
      } else if report.skipped.isEmpty {
        Text("Every RFC was exported.")
      } else {
        Text("These RFCs were not exported:")
        ForEach(report.skippedLines, id: \.self) { line in
          Text(verbatim: line).font(.callout).foregroundStyle(.secondary)
        }
      }
    }
  }

  #if os(macOS)
    @ViewBuilder
    private var buttons: some View {
      cancelButton.keyboardShortcut(.cancelAction)
      confirmButton.keyboardShortcut(.defaultAction)
    }
  #endif

  private var cancelButton: some View {
    Button("Cancel", role: .cancel) {
      export.cancel()
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
      if report.exported.isEmpty {
        Button("Done") { dismiss() }
      } else {
        Button("Save…") { isSaving = true }
      }
    }
  }

  private func start() {
    guard let entry else { return }
    let plan = CollectionExport(collection: entry.name, members: entry.members, format: format)
    let paperSize = PrintLayout.paperSize(for: .current)
    let library = library
    export.start(plan) { id in
      try await DocumentExport.data(
        for: id, as: plan.format, paperSize: paperSize, library: library)
    }
  }
}

/// A collection export under way: its phase, and the task making its files, in a
/// folder of the temporary directory until it is saved.
@Observable
final class CollectionExportModel {
  enum Phase {
    case choosing
    case exporting(CollectionExport.Progress)
    case finished(CollectionExport.Report)
  }

  private(set) var phase = Phase.choosing
  /// The finished folder, for Save to Files and the Mac's save panel.
  private(set) var folder: ExportedFolder?
  private var task: Task<Void, Never>?
  private var workspace: URL?

  func start(
    _ plan: CollectionExport, make: @escaping @Sendable (DocumentID) async throws -> Data
  ) {
    let workspace = FileManager.default.temporaryDirectory
      .appending(path: "Collection Export", directoryHint: .isDirectory)
      .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    self.workspace = workspace
    let folderURL = workspace.appending(path: plan.folderName, directoryHint: .isDirectory)
    phase = .exporting(CollectionExport.Progress(done: 0, total: plan.files.count))
    task = Task {
      let report: CollectionExport.Report
      do {
        report = try await plan.run(into: folderURL) { progress in
          await MainActor.run { self.phase = .exporting(progress) }
        } make: { id in
          try await make(id)
        }
      } catch {
        var failed = CollectionExport.Report()
        failed.skipped = plan.files.map { ($0.document, error.localizedDescription) }
        report = failed
      }
      if Task.isCancelled {
        try? FileManager.default.removeItem(at: workspace)
        return
      }
      if !report.exported.isEmpty {
        folder = ExportedFolder(url: folderURL, name: plan.folderName)
      }
      phase = .finished(report)
    }
  }

  /// Stops an export under way, which then removes what it made, or removes what
  /// a finished one made, which has been saved or is no longer wanted.
  func cancel() {
    task?.cancel()
    if case .exporting = phase { return }
    if let workspace { try? FileManager.default.removeItem(at: workspace) }
  }
}

/// A folder of exported files, for SwiftUI's `fileExporter`, which saves it under
/// the name it is given. Written only, and read from the disk as it is saved.
nonisolated struct ExportedFolder: FileDocument {
  static var readableContentTypes: [UTType] { [] }
  static var writableContentTypes: [UTType] { [.folder] }

  let url: URL
  let name: String

  init(url: URL, name: String) {
    self.url = url
    self.name = name
  }

  init(configuration: ReadConfiguration) throws {
    throw CocoaError(.fileReadUnsupportedScheme)
  }

  func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
    try FileWrapper(url: url)
  }
}
