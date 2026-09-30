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
    return await renderExport(
      document, metadata: library.metadata(id), choices: library.presentationChoices(for: id),
      paperSize: paperSize)
  }

  @concurrent
  static func renderExport(
    _ document: RFCDocument, metadata: RFCMetadata?, choices: PresentationChoices,
    paperSize: CGSize
  ) async -> Data {
    let layout = PrintLayout(paperSize: paperSize)
    let furniture = PrintFurniture(header: document.header, metadata: metadata)
    return buildAndLayOut(
      Printed(document: document, choices: choices), style: layout.exportStyle,
      furniture: furniture, layout: layout
    ) { built, laidOut in
      let pages = pdf(laidOut, layout: layout, furniture: furniture)
      let outline = PDFExport.outline(of: document, built: built)
      let marks = PDFMarks(
        laidOut, text: built.text, anchors: built.anchors, outline: outline,
        references: PDFExport.references(in: document), layout: layout)
      return annotate(
        pages, marks: marks, outline: outline,
        info: PDFExport.Info(header: document.header, metadata: metadata))
    }
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

    // Added to what the drawing wrote, its creation date and creator among them,
    // and only what the document has: no empty author on an RFC that names none.
    var attributes = document.documentAttributes ?? [:]
    attributes[PDFDocumentAttribute.titleAttribute] = info.title
    if !info.author.isEmpty {
      attributes[PDFDocumentAttribute.authorAttribute] = info.author
    }
    if !info.subject.isEmpty {
      attributes[PDFDocumentAttribute.subjectAttribute] = info.subject
    }
    if !info.keywords.isEmpty {
      attributes[PDFDocumentAttribute.keywordsAttribute] = info.keywords
    }
    document.documentAttributes = attributes
    return document.dataRepresentation() ?? data
  }
}

/// Where the laid-out text put what an export points at, in PDF page
/// coordinates.
nonisolated struct PDFMarks {
  /// A link's words on one page, and where they go. A link that wraps onto the
  /// next line, or the next page, is one of these per line.
  struct Link {
    let page: Int
    let rect: CGRect
    let target: PDFExport.Target
  }

  /// The anchors the outline and the links go to, each at the top of its
  /// paragraph's first line.
  let destinations: [String: PDFExport.Place]
  let links: [Link]

  init(
    _ laidOut: DocumentPDF.LaidOut, text: NSAttributedString, anchors: AnchorIndex,
    outline: [PDFExport.OutlineEntry], references: [String: Reference], layout: PrintLayout
  ) {
    let manager = laidOut.manager
    let pages = laidOut.pages

    var targets: [(range: NSRange, target: PDFExport.Target)] = []
    text.enumerateAttribute(.rfcLinkTarget, in: NSRange(location: 0, length: text.length)) {
      value, range, _ in
      guard let url = value as? URL,
        let target = PDFExport.target(of: url, references: references)
      else { return }
      targets.append((range, target))
    }

    // Only the anchors something goes to: every paragraph has one, and placing each
    // is a walk through the text.
    var wanted: Set<String> = []
    func want(_ entries: [PDFExport.OutlineEntry]) {
      for entry in entries {
        wanted.insert(entry.anchor)
        want(entry.children)
      }
    }
    want(outline)
    for case .anchor(let anchor) in targets.map(\.target) {
      wanted.insert(anchor)
    }

    var destinations: [String: PDFExport.Place] = [:]
    for anchor in wanted {
      guard let offset = anchors.offset(of: anchor),
        let location = manager.location(atOffset: offset),
        let fragment = manager.textLayoutFragment(for: location),
        let line = fragment.textLineFragments.first
      else { continue }
      let lineTop = fragment.layoutFragmentFrame.minY + line.typographicBounds.minY
      destinations[anchor] = PDFExport.destination(lineTop: lineTop, pages: pages, layout: layout)
    }

    var links: [Link] = []
    for (range, target) in targets {
      if case .anchor(let anchor) = target, destinations[anchor] == nil { continue }
      guard let textRange = manager.textRange(for: range) else { continue }
      manager.enumerateTextSegments(in: textRange, type: .standard, options: []) {
        _, frame, _, _ in
        if let placed = PDFExport.linkBounds(frame, pages: pages, layout: layout) {
          links.append(Link(page: placed.page, rect: placed.rect, target: target))
        }
        return true
      }
    }
    self.destinations = destinations
    self.links = links
  }
}
