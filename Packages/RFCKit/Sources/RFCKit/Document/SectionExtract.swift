import Foundation

extension RFCDocument {
  /// The document narrowed to one section and its subsections, for an export or a
  /// print of the section a reader is in (#386); nil when no section has `anchor`.
  ///
  /// The abstract is left out, and the title names the section after the
  /// document's, `HTTP Semantics, § 4`, so every surface that says what a file is —
  /// a PDF's title block and its info, a page's heading — says it is a part. A
  /// reference to anything left out is a writer's to send to the document on
  /// rfc-editor.org.
  public func narrowed(toSection anchor: String) -> RFCDocument? {
    guard let section = section(anchor: anchor) else { return nil }
    let part = section.place.map(PlaceName.abbreviated) ?? section.titleText
    var header = self.header
    header.abstract = []
    header.title = header.title.isEmpty ? part : "\(header.title), \(part)"
    header.abbreviatedTitle = header.abbreviatedTitle.map { "\($0), \(part)" }
    var narrowed = RFCDocument(header: header, sections: [section], source: source)
    narrowed.abbreviations = abbreviations
    narrowed.definedTerms = definedTerms
    return narrowed
  }

  /// Every anchor a link into this document can land on: its sections', its
  /// blocks', and the abstract's where it has one.
  public var anchors: Set<String> {
    var anchors = Set(allSections.map(\.anchor))
    anchors.formUnion(blocks.flatMap(\.anchors))
    if !header.abstract.isEmpty { anchors.insert(FullTextIndex.abstractAnchor) }
    return anchors
  }
}
