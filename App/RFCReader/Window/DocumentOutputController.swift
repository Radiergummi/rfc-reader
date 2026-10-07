#if os(macOS)
  import AppKit
  import PDFKit
  import RFCKit
  import RFCReaderKit
  import os

  /// A window's document as it leaves the screen: File > Print…, Export… and Page
  /// Setup…, each a sheet on the window (#772). Apart from `ReaderWindowController`,
  /// which builds the window, so that a new output format (#733) edits this rather
  /// than the window's construction.
  final class DocumentOutputController: NSObject {
    private weak var window: NSWindow?
    private let navigation: NavigationModel
    private let reader: ReaderState
    private let library: LibraryModel

    /// Whether a print is being prepared or its panel is up, so a second ⌘P
    /// neither builds the PDF again nor asks for a second sheet.
    private var isPrinting = false
    /// The PDF being made for a print, canceled when the window closes, so a closed
    /// window neither goes on building it nor asks for a sheet on itself.
    private var printing: Task<Void, Never>?
    /// Whether an export's save panel is up or its file is being made, so a second
    /// ⌘⇧E neither asks for a second panel nor makes the file again.
    private var isExporting = false

    init(window: NSWindow, navigation: NavigationModel, reader: ReaderState, library: LibraryModel)
    {
      self.window = window
      self.navigation = navigation
      self.reader = reader
      self.library = library
    }

    /// The window is closing: a PDF still being made for a print is not finished.
    func cancel() {
      printing?.cancel()
    }

    // MARK: - Print

    /// File > Print…: the document laid out for paper, handed to the system's print
    /// panel as a sheet on this window (#375). Laid out for the paper Page Setup has
    /// chosen; a different paper picked in the panel itself is scaled to fit.
    func printDocument() {
      guard !isPrinting, let id = navigation.selection, reader.offersPrintAndExport, let window
      else {
        return
      }
      // The PDF's pages carry their own margins; AppKit's, left in, would shrink
      // every page to fit inside a second set.
      guard let printInfo = NSPrintInfo.shared.copy() as? NSPrintInfo else { return }
      printInfo.leftMargin = 0
      printInfo.rightMargin = 0
      printInfo.topMargin = 0
      printInfo.bottomMargin = 0
      let original = reader.showOriginal
      isPrinting = true
      printing = Task {
        do {
          let data = try await DocumentPDF.make(
            for: id, original: original, paperSize: printInfo.paperSize, library: library)
          guard !Task.isCancelled else { return }
          guard let pdf = PDFDocument(data: data),
            let operation = pdf.printOperation(
              for: printInfo, scalingMode: .pageScaleToFit, autoRotate: false)
          else {
            isPrinting = false
            readerLog.error(
              "\(id.displayName, privacy: .public): print failed: PDFKit made no print operation of the PDF"
            )
            let alert = NSAlert()
            alert.messageText = String(localized: "Couldn't print \(id.displayName)")
            alert.beginSheetModal(for: window, completionHandler: nil)
            return
          }
          // The one field of the Save as PDF sheet a print can fill: its Author,
          // Subject and Keywords have no public setting (#375).
          operation.jobTitle = PrintFurniture.documentTitle(
            id: id, title: reader.documentTitle ?? library.metadata(id)?.title)
          operation.runModal(
            for: window, delegate: self,
            didRun: #selector(printOperationDidRun(_:success:contextInfo:)), contextInfo: nil)
        } catch {
          isPrinting = false
          guard !Task.isCancelled else { return }
          readerLog.failure(of: id, "print failed", error)
          _ = window.presentError(error)
        }
      }
    }

    @objc private func printOperationDidRun(
      _ operation: NSPrintOperation, success: Bool, contextInfo: UnsafeMutableRawPointer?
    ) {
      isPrinting = false
    }

    // MARK: - Export

    /// File > Export…: the document saved in the format the save panel's pop-up
    /// picks (#376), as a sheet on this window. A paged format is laid out for the
    /// paper Page Setup has chosen, as a print is.
    func exportDocument() {
      guard !isExporting, let id = navigation.selection, reader.offersPrintAndExport, let window
      else {
        return
      }
      let panel = NSSavePanel()
      let chooser = ExportFormatChooser(panel: panel, document: id, offered: reader.exportFormats)
      panel.accessoryView = chooser.view
      panel.isExtensionHidden = false
      panel.canCreateDirectories = true
      panel.tagNames = ExportFormat.tagNames(for: library.metadata(id))
      isExporting = true
      panel.beginSheetModal(for: window) { [library] response in
        guard response == .OK, let url = panel.url else {
          self.isExporting = false
          return
        }
        // Read here, not captured earlier: the chooser is what the panel's pop-up
        // changed, and holding it in this closure is what keeps it alive.
        let format = chooser.format
        let tags = panel.tagNames ?? []
        Task {
          do {
            let data = try await DocumentExport.data(
              for: id, as: format, paperSize: NSPrintInfo.shared.paperSize, library: library)
            try data.write(to: url, options: .atomic)
            // The panel only collects the tags; the file is written after it, and
            // an atomic write replaces it, so they are set on what was written.
            if !tags.isEmpty {
              try (url as NSURL).setResourceValue(tags, forKey: .tagNamesKey)
            }
            self.isExporting = false
          } catch {
            self.isExporting = false
            _ = window.presentError(error)
          }
        }
      }
    }

    // MARK: - Page Setup

    /// File > Page Setup…, which sets the paper `printDocument()` lays out for.
    func runPageSetup() {
      guard let window else { return }
      NSPageLayout().beginSheet(
        with: NSPrintInfo.shared, modalFor: window, delegate: nil, didEnd: nil, contextInfo: nil)
    }
  }
#endif
