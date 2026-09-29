import CoreGraphics
import Foundation
import RFCKit

/// What an exported PDF has that a printed one does not: links, an outline and the
/// document's own description (#376).
///
/// Pure: where a link goes, which sections the outline lists, and what the file's
/// info says are decided here, from the document and its build. The app's renderer
/// only measures where things landed on the page and hands that to PDFKit.
public enum PDFExport {
  /// Where a link in the PDF goes.
  public enum Target: Equatable, Sendable {
    /// A place in this document, by its anchor: a destination within the file.
    case anchor(String)
    /// Anywhere else: another RFC's page on rfc-editor.org, or an external URL.
    case web(URL)
  }

  /// Where a link the builder recorded goes in a file that stands on its own.
  ///
  /// The reader's own schemes mean nothing outside the app, so they are turned into
  /// what a PDF reader can follow: an anchor into a destination in this file, a
  /// reference to another RFC into its page on rfc-editor.org, and a citation of a
  /// bibliography entry — which the body leaves out — into what the entry links
  /// to: its URL, or the RFC it names. A link that goes nowhere a reader can follow
  /// has no annotation.
  ///
  /// - Parameter references: the document's bibliography entries, by anchor.
  public static func target(of url: URL, references: [String: Reference]) -> Target? {
    if let anchor = DocumentTextBuilder.anchor(from: url) {
      return .anchor(anchor)
    }
    if let entry = DocumentTextBuilder.reference(from: url) {
      guard let reference = references[entry] else { return nil }
      if let url = reference.url, let target = followable(url) { return target }
      return reference.documentID.map { .web(RFCLink(id: $0).webURL) }
    }
    if let link = RFCLink(url: url) {
      return .web(link.webURL)
    }
    return followable(url)
  }

  /// `url` as a link, when a PDF reader can follow it: the web, or mail.
  private static func followable(_ url: URL) -> Target? {
    guard let scheme = url.scheme?.lowercased(), ["http", "https", "mailto"].contains(scheme)
    else { return nil }
    return .web(url)
  }

  /// The document's bibliography entries by anchor, for `target(of:references:)`.
  public static func references(in document: RFCDocument) -> [String: Reference] {
    Dictionary(
      ReferenceGroup.groups(in: document).flatMap(\.entries).map { ($0.anchor, $0) },
      uniquingKeysWith: { first, _ in first })
  }

  /// One entry in the PDF's outline, the sidebar a PDF reader lists its bookmarks
  /// in.
  public struct OutlineEntry: Equatable, Sendable {
    public let title: String
    public let anchor: String
    public let children: [OutlineEntry]
  }

  /// The outline: the abstract, then every section the build holds, nested as the
  /// document nests them. A section the build left out — the bibliography, which
  /// the reader keeps in its panel — is left out here too, since there is nowhere
  /// in the file for it to go; its subsections with it.
  public static func outline(of document: RFCDocument, built: BuiltDocument) -> [OutlineEntry] {
    func entries(_ sections: [Section]) -> [OutlineEntry] {
      sections.compactMap { section in
        guard built.anchors.offset(of: section.anchor) != nil else { return nil }
        return OutlineEntry(
          title: section.displayTitle, anchor: section.anchor,
          children: entries(section.subsections))
      }
    }
    var outline: [OutlineEntry] = []
    if built.anchors.offset(of: DocumentTextBuilder.abstractAnchor) != nil {
      outline.append(
        OutlineEntry(title: "Abstract", anchor: DocumentTextBuilder.abstractAnchor, children: []))
    }
    return outline + entries(document.sections)
  }

  /// What the file's info dictionary says about it: what Finder's Get Info,
  /// Spotlight and a PDF reader's document properties show.
  public struct Info: Equatable, Sendable {
    /// `RFC 9110: HTTP Semantics`.
    public let title: String
    public let author: String
    /// `RFC 9110`.
    public let subject: String
    /// The document's own keywords, then its working group and status, as its
    /// Finder tags say them (`ExportFormat.tagNames(for:)`).
    public let keywords: [String]

    public init(header: DocumentHeader, metadata: RFCMetadata?) {
      let summary = HeaderSummary(header: header, metadata: metadata)
      let id = header.id ?? metadata?.id
      title = PrintFurniture.documentTitle(id: id, title: summary.title)
      author = summary.authors.map(\.displayName).joined(separator: ", ")
      subject = id?.displayName ?? ""
      let own = header.keywords.isEmpty ? (metadata?.keywords ?? []) : header.keywords
      let filing = ExportFormat.classification(metadata).filter { !own.contains($0) }
      keywords = own + filing
    }
  }

  /// A place on a page: where a destination scrolls to, in the page's PDF
  /// coordinates.
  public struct Place: Equatable, Sendable {
    public let page: Int
    public let point: CGPoint
  }

  /// Where a destination goes for a paragraph whose first line's top is at
  /// `lineTop`, in the laid-out document's coordinates: that line's page, at the
  /// column's left edge. The line's top, not its layout fragment's, because a
  /// fragment's frame includes the space before a heading while a page starts at a
  /// line's top: from the fragment, a heading that opens a page would be placed at
  /// the foot of the page before.
  public static func destination(
    lineTop: CGFloat, pages: [PrintPagination.Page], layout: PrintLayout
  ) -> Place? {
    guard let index = PrintPagination.page(containing: lineTop, in: pages) else { return nil }
    let onPaper = layout.onPaper(
      CGRect(x: 0, y: lineTop, width: 0, height: 0), page: pages[index])
    let pdf = pdfRect(onPaper, paperHeight: layout.paperSize.height)
    return Place(page: index, point: CGPoint(x: pdf.minX, y: pdf.maxY))
  }

  /// Where a link's words go, `rect` in the laid-out document's coordinates: on the
  /// page that holds their middle, in that page's PDF coordinates.
  public static func linkBounds(
    _ rect: CGRect, pages: [PrintPagination.Page], layout: PrintLayout
  ) -> (page: Int, rect: CGRect)? {
    guard let index = PrintPagination.page(containing: rect.midY, in: pages) else { return nil }
    let onPaper = layout.onPaper(rect, page: pages[index])
    return (index, pdfRect(onPaper, paperHeight: layout.paperSize.height))
  }

  /// `rect`, given top-down as a page draws it, in a PDF page's own coordinates,
  /// which run bottom-up from the page's bottom-left corner: what PDFKit's
  /// annotations and destinations are placed in.
  public static func pdfRect(_ rect: CGRect, paperHeight: CGFloat) -> CGRect {
    CGRect(x: rect.minX, y: paperHeight - rect.maxY, width: rect.width, height: rect.height)
  }
}
