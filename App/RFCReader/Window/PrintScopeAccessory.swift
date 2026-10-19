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
  ///
  /// The section's PDF is made the first time the pop-up picks it, which most prints
  /// never do. Until it is here the pop-up waits, and the panel shows and prints the
  /// whole document, as its summary says; a section that cannot be made leaves the
  /// whole document chosen and the choice disabled.
  final class PrintScopeAccessory: NSViewController, NSPrintPanelAccessorizing {
    private let pages: PrintedPDFView
    private let whole: PDFDocument
    private var section: PDFDocument?
    private let makeSection: @MainActor () async -> PDFDocument?
    private let popUp = NSPopUpButton()

    /// What the preview depends on, for `keyPathsForValuesAffectingPreview`: the
    /// scope of the document the view prints.
    @objc dynamic private(set) var scopeIndex = 0

    init(
      pages: PrintedPDFView, whole: PDFDocument,
      makeSection: @escaping @MainActor () async -> PDFDocument?
    ) {
      self.pages = pages
      self.whole = whole
      self.makeSection = makeSection
      super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
      fatalError("init(coder:) is not used")
    }

    override func loadView() {
      popUp.addItems(withTitles: ExportScope.allCases.map { $0.name() })
      popUp.autoenablesItems = false
      popUp.target = self
      popUp.action = #selector(choose)
      let label = NSTextField(labelWithString: String(localized: "Contents:"))
      let row = NSStackView(views: [label, popUp])
      row.edgeInsets = NSEdgeInsets(top: 8, left: 20, bottom: 8, right: 20)
      row.frame.size = row.fittingSize
      view = row
    }

    @objc private func choose() {
      switch ExportScope.allCases[popUp.indexOfSelectedItem] {
      case .wholeDocument:
        show(whole, as: .wholeDocument)
      case .currentSection:
        if let section {
          show(section, as: .currentSection)
          return
        }
        popUp.isEnabled = false
        Task {
          let made = await makeSection()
          popUp.isEnabled = true
          guard let made else {
            popUp.selectItem(at: Self.index(of: .wholeDocument))
            popUp.item(at: Self.index(of: .currentSection))?.isEnabled = false
            show(whole, as: .wholeDocument)
            return
          }
          section = made
          show(made, as: .currentSection)
        }
      }
    }

    /// `document` printed, and the preview and summary told so.
    private func show(_ document: PDFDocument, as scope: ExportScope) {
      pages.document = document
      scopeIndex = Self.index(of: scope)
    }

    private static func index(of scope: ExportScope) -> Int {
      ExportScope.allCases.firstIndex(of: scope) ?? 0
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
