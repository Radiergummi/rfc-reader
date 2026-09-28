import CoreGraphics
import Foundation
import PDFKit
import RFCKit
import RFCReaderKit

#if canImport(UIKit)
  import UIKit
#else
  import AppKit
#endif

/// Export as PDF: the print's pages, with what a file read on screen has that
/// paper does not — links, an outline and the document's own description (#376).
///
/// What each of those says is `PDFExport`, in RFCReaderKit. What is here is only
/// measurement and PDFKit: where the laid-out text put a link's words and a
/// section's heading, and the annotations, destinations and outline that point
/// at them.
nonisolated extension DocumentPDF {
  /// The open document as a PDF to save. Always the rendered document, whatever the
  /// reader is showing: the published text is a format of its own (#377).
  @MainActor
  static func export(_ id: DocumentID, paperSize: CGSize, library: LibraryModel) async throws
    -> Data
  {
    let document = try await library.document(for: id)
    return await renderExport(document, metadata: library.metadata(id), paperSize: paperSize)
  }

  @concurrent
  static func renderExport(_ document: RFCDocument, metadata: RFCMetadata?, paperSize: CGSize)
    async -> Data
  {
    let layout = PrintLayout(paperSize: paperSize)
    let furniture = PrintFurniture(header: document.header, metadata: metadata)
    let built = DocumentTextBuilder.build(
      document, style: layout.style, title: furniture.titleBlock)
    let laidOut = LaidOut(built.text, keepingWithNext: built.keepsWithNext, layout: layout)
    let pages = pdf(laidOut, layout: layout, furniture: furniture)
    let marks = PDFMarks(
      laidOut, text: built.text, anchors: built.anchors,
      references: PDFExport.references(in: document), layout: layout)
    return annotate(
      pages, marks: marks, outline: PDFExport.outline(of: document, built: built),
      info: PDFExport.Info(header: document.header, metadata: metadata))
  }

  /// The rendered pages with their links, outline and info added, through PDFKit.
  /// The pages as drawn if PDFKit cannot read them back, which it wrote itself a
  /// moment ago: a file without links is still the document.
  static func annotate(
    _ data: Data, marks: PDFMarks, outline: [PDFExport.OutlineEntry], info: PDFExport.Info
  ) -> Data {
    guard let document = PDFDocument(data: data) else { return data }

    func destination(_ anchor: String) -> PDFDestination? {
      guard let place = marks.destinations[anchor], let page = document.page(at: place.page)
      else { return nil }
      return PDFDestination(page: page, at: place.point)
    }

    for link in marks.links {
      guard let page = document.page(at: link.page) else { continue }
      let annotation = PDFAnnotation(bounds: link.rect, forType: .link, withProperties: nil)
      switch link.target {
      case .web(let url):
        annotation.url = url
      case .anchor(let anchor):
        guard let destination = destination(anchor) else { continue }
        annotation.destination = destination
      }
      // No box around a link: on paper-shaped pages it should read as the text it is.
      let border = PDFBorder()
      border.lineWidth = 0
      annotation.border = border
      page.addAnnotation(annotation)
    }

    func add(_ entries: [PDFExport.OutlineEntry], to parent: PDFOutline) {
      for entry in entries {
        guard let destination = destination(entry.anchor) else { continue }
        let item = PDFOutline()
        item.label = entry.title
        item.destination = destination
        parent.insertChild(item, at: parent.numberOfChildren)
        add(entry.children, to: item)
      }
    }
    let root = PDFOutline()
    add(outline, to: root)
    document.outlineRoot = root

    document.documentAttributes = [
      PDFDocumentAttribute.titleAttribute: info.title,
      PDFDocumentAttribute.authorAttribute: info.author,
      PDFDocumentAttribute.subjectAttribute: info.subject,
      PDFDocumentAttribute.keywordsAttribute: info.keywords,
    ]
    return document.dataRepresentation() ?? data
  }
}

/// Where the laid-out text put what an export points at, in PDF page
/// coordinates.
nonisolated struct PDFMarks {
  /// A place on a page: where a destination scrolls to.
  struct Place {
    let page: Int
    let point: CGPoint
  }

  /// A link's words on one page, and where they go. A link that wraps onto the
  /// next line, or the next page, is one of these per line.
  struct Link {
    let page: Int
    let rect: CGRect
    let target: PDFExport.Target
  }

  /// Every anchor in the document, at the top of the paragraph it names.
  let destinations: [String: Place]
  let links: [Link]

  init(
    _ laidOut: DocumentPDF.LaidOut, text: NSAttributedString, anchors: AnchorIndex,
    references: [String: Reference], layout: PrintLayout
  ) {
    let manager = laidOut.manager
    let pages = laidOut.pages
    let paperHeight = layout.paperSize.height

    /// `rect`, in document coordinates, on the page that holds its middle.
    func placed(_ rect: CGRect) -> (page: Int, rect: CGRect)? {
      guard let index = PrintPagination.page(containing: rect.midY, in: pages) else {
        return nil
      }
      let onPaper = layout.onPaper(rect, page: pages[index])
      return (index, PDFExport.pdfRect(onPaper, paperHeight: paperHeight))
    }

    var destinations: [String: Place] = [:]
    for entry in anchors.entries {
      guard let location = manager.location(atOffset: entry.offset),
        let fragment = manager.textLayoutFragment(for: location)
      else { continue }
      let frame = fragment.layoutFragmentFrame
      let top = CGRect(x: 0, y: frame.minY, width: 0, height: 0)
      guard let index = PrintPagination.page(containing: frame.minY, in: pages) else {
        continue
      }
      let onPaper = layout.onPaper(top, page: pages[index])
      destinations[entry.anchor] = Place(
        page: index, point: CGPoint(x: onPaper.minX, y: paperHeight - onPaper.minY))
    }

    var links: [Link] = []
    text.enumerateAttribute(.rfcLinkTarget, in: NSRange(location: 0, length: text.length)) {
      value, range, _ in
      guard let url = value as? URL,
        let target = PDFExport.target(of: url, references: references),
        let textRange = manager.textRange(for: range)
      else { return }
      if case .anchor(let anchor) = target, destinations[anchor] == nil { return }
      manager.enumerateTextSegments(in: textRange, type: .standard, options: []) {
        _, frame, _, _ in
        if let placement = placed(frame) {
          links.append(Link(page: placement.page, rect: placement.rect, target: target))
        }
        return true
      }
    }
    self.destinations = destinations
    self.links = links
  }
}
