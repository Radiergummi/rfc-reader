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
/// format chosen, then where, then the files written straight there with one
/// progress that can be canceled, and what could not be exported named. Where is
/// asked first, so that once the sheet says the RFCs are exported they are where
/// the reader asked for them.
struct CollectionExportSheet: View {
  let request: CollectionExportRequest

  @Environment(LibraryModel.self) private var library
  @Environment(\.dismiss) private var dismiss
  @State private var format = ExportFormat.pdf
  @State private var export = CollectionExportSession()
  @State private var isChoosingFolder = false
  @State private var folderError: String?

  private var entry: CollectionSnapshot.Entry? { library.collections[request.collection] }

  var body: some View {
    content
      // A swipe would end an export under way without a word.
      .interactiveDismissDisabled(export.isExporting)
      .onDisappear { export.cancel() }
      .fileImporter(isPresented: $isChoosingFolder, allowedContentTypes: [.folder]) { result in
        switch result {
        case .success(let parent): start(in: parent)
        case .failure(let error as CocoaError) where error.code == .userCancelled: break
        case .failure(let error): folderError = error.localizedDescription
        }
      }
      .fileDialogConfirmationLabel(Text("Export"))
      .alert(
        "Couldn't open the folder",
        isPresented: Binding(get: { folderError != nil }, set: { if !$0 { folderError = nil } })
      ) {
        Button("OK") { folderError = nil }
      } message: {
        Text(verbatim: folderError ?? "")
      }
  }

  @ViewBuilder
  private var content: some View {
    #if os(macOS)
      VStack(alignment: .leading, spacing: 12) {
        Text(title).font(.headline)
        fields
        HStack {
          showInFinderButton
          Spacer()
          if !isFinished { cancelButton.keyboardShortcut(.cancelAction) }
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
            if !isFinished {
              ToolbarItem(placement: .cancellationAction) { cancelButton }
            }
            ToolbarItem(placement: .confirmationAction) { confirmButton }
          }
      }
      .presentationDetents([.medium, .large])
    #endif
  }

  private var isFinished: Bool {
    if case .finished = export.phase { true } else { false }
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
      }
      if let folder = export.folder {
        Text("Exported to “\(folder.lastPathComponent)”.")
      }
      if !report.skipped.isEmpty {
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

  /// While the files are written, Cancel stops the export, which then says how far
  /// it came; before, it closes the sheet.
  private var cancelButton: some View {
    Button("Cancel", role: .cancel) {
      if export.isExporting {
        export.cancel()
      } else {
        dismiss()
      }
    }
  }

  #if os(macOS)
    /// The folder the export made, selected in a Finder window.
    @ViewBuilder
    private var showInFinderButton: some View {
      if let folder = export.folder, isFinished {
        Button("Show in Finder") {
          NSWorkspace.shared.activateFileViewerSelecting([folder])
        }
      }
    }
  #endif

  @ViewBuilder
  private var confirmButton: some View {
    switch export.phase {
    case .choosing:
      Button("Export…") { isChoosingFolder = true }
        .disabled(entry?.rfcNumbers.isEmpty ?? true)
    case .exporting:
      Button("Export…") {}.disabled(true)
    case .finished:
      Button("Done") { dismiss() }
    }
  }

  private func start(in parent: URL) {
    guard let entry else { return }
    let plan = CollectionExport(entry, format: format)
    // The paper a single export is laid out for: Page Setup's on the Mac
    // (`DocumentOutputController`), the region's on iOS (`DocumentOutput`).
    #if os(macOS)
      let paperSize = NSPrintInfo.shared.paperSize
    #else
      let paperSize = PrintLayout.paperSize(for: .current)
    #endif
    let library = library
    export.start(plan, in: parent) { id in
      try await DocumentExport.data(
        for: id, as: plan.format, paperSize: paperSize, library: library)
    }
  }
}
