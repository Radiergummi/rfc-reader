#if os(macOS)
  import AppKit
  import PDFKit
  import RFCReaderKit

  /// The print panel's Whole Document / Current Section pop-up (#386), and the view
  /// that prints whichever of the two PDFs it chooses.
  ///
  /// PDFKit's own print operation prints the one document it was made from, so a
  /// choice made in the panel needs a view of the app's: it lays the chosen PDF's
  /// pages out one paper each, fitted to the paper the panel has (`PrintedPages`),
  /// and the panel's preview follows the pop-up.
  final class PrintScopeAccessory: NSViewController, NSPrintPanelAccessorizing {
    private let pages: PrintedPDFView
    private let documents: [ExportScope: PDFDocument]
    private let popUp = NSPopUpButton()

    /// What the preview depends on, for `keyPathsForValuesAffectingPreview`.
    @objc dynamic private(set) var scopeIndex = 0

    init(pages: PrintedPDFView, documents: [ExportScope: PDFDocument]) {
      self.pages = pages
      self.documents = documents
      super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
      fatalError("init(coder:) is not used")
    }

    override func loadView() {
      popUp.addItems(withTitles: ExportScope.allCases.map { $0.name() })
      popUp.target = self
      popUp.action = #selector(choose)
      let label = NSTextField(labelWithString: String(localized: "Contents:"))
      let row = NSStackView(views: [label, popUp])
      row.edgeInsets = NSEdgeInsets(top: 8, left: 20, bottom: 8, right: 20)
      row.frame.size = row.fittingSize
      view = row
    }

    @objc private func choose() {
      let scope = ExportScope.allCases[popUp.indexOfSelectedItem]
      if let document = documents[scope] { pages.document = document }
      scopeIndex = popUp.indexOfSelectedItem
    }

    func localizedSummaryItems() -> [[NSPrintPanel.AccessorySummaryKey: String]] {
      [
        [
          .itemName: String(localized: "Contents"),
          .itemDescription: ExportScope.allCases[scopeIndex].name(),
        ]
      ]
    }

    func keyPathsForValuesAffectingPreview() -> Set<String> {
      ["scopeIndex"]
    }
  }

  /// A PDF's pages as a view to print: one page per paper, the first at the top.
  final class PrintedPDFView: NSView {
    var document: PDFDocument

    init(document: PDFDocument) {
      self.document = document
      super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
      fatalError("init(coder:) is not used")
    }

    /// The paper being printed on, which the panel can change.
    private var paper: CGSize {
      NSPrintOperation.current?.printInfo.paperSize ?? NSPrintInfo.shared.paperSize
    }

    override func knowsPageRange(_ range: NSRangePointer) -> Bool {
      setFrameSize(PrintedPages.size(count: document.pageCount, paper: paper))
      range.pointee = NSRange(location: 1, length: document.pageCount)
      return true
    }

    override func rectForPage(_ page: Int) -> NSRect {
      PrintedPages.rect(forPage: page, count: document.pageCount, paper: paper)
    }

    override func draw(_ dirtyRect: NSRect) {
      guard let context = NSGraphicsContext.current?.cgContext else { return }
      for index in 0..<document.pageCount {
        let rect = rectForPage(index + 1)
        guard rect.intersects(dirtyRect), let page = document.page(at: index) else { continue }
        let bounds = page.bounds(for: .mediaBox)
        let fitted = PrintedPages.fitted(bounds.size, in: rect)
        context.saveGState()
        context.translateBy(x: fitted.minX, y: fitted.minY)
        context.scaleBy(x: fitted.width / bounds.width, y: fitted.height / bounds.height)
        context.translateBy(x: -bounds.minX, y: -bounds.minY)
        page.draw(with: .mediaBox, to: context)
        context.restoreGState()
      }
    }
  }
#endif
