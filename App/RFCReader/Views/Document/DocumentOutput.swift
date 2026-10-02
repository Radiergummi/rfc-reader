#if !os(macOS)
  import RFCKit
  import RFCReaderKit
  import SwiftUI
  import UIKit

  /// Export and Print on iOS (#599): the file or PDF made, then Save to Files or the
  /// print sheet presented. The Mac's are the window's (`ReaderWindowController`):
  /// a save panel and the print panel as sheets. Both make what they hand over the
  /// same way, through `DocumentExport` and `DocumentPDF`.
  @Observable
  final class DocumentOutput {
    /// Whether a print is being prepared or its sheet is up; see `printDocument`.
    private(set) var isPrinting = false
    /// A finished export, while Save to Files is showing it (#376).
    private(set) var exported: ExportedFile?
    /// Whether an export is being made or Save to Files is up; see `exportDocument`.
    private(set) var isExporting = false

    /// Save to Files, with the document in `format` (#376). Laid out for the
    /// region's paper, as a print is.
    func exportDocument(_ id: DocumentID, as format: ExportFormat, library: LibraryModel) {
      // A second tap while the file is made would make it again, and present Save to
      // Files over the first.
      guard !isExporting else { return }
      isExporting = true
      Task {
        guard
          let data = try? await DocumentExport.data(
            for: id, as: format, paperSize: PrintLayout.paperSize(for: .current),
            library: library)
        else {
          isExporting = false
          return
        }
        exported = ExportedFile(data: data, format: format)
      }
    }

    /// Save to Files went, saved or not.
    func finishExport() {
      exported = nil
      isExporting = false
    }

    /// The system's print sheet, with the document laid out for paper (#375). Laid
    /// out for the region's paper; the sheet scales it to whatever paper is chosen.
    func printDocument(
      _ id: DocumentID, original: Bool, title: String?, library: LibraryModel
    ) {
      // A second tap while the PDF is built would build it again and present the
      // shared controller twice.
      guard !isPrinting else { return }
      isPrinting = true
      Task {
        guard
          let data = try? await DocumentPDF.make(
            for: id, original: original, paperSize: PrintLayout.paperSize(for: .current),
            library: library)
        else {
          isPrinting = false
          return
        }
        let info = UIPrintInfo.printInfo()
        info.jobName = PrintFurniture.documentTitle(id: id, title: title)
        info.outputType = .general
        let controller = UIPrintInteractionController.shared
        controller.printInfo = info
        controller.printingItem = data
        // False when it cannot present, and then its handler never runs.
        let presented = controller.present(animated: true) { _, _, _ in
          self.isPrinting = false
        }
        if !presented { isPrinting = false }
      }
    }
  }
#endif
