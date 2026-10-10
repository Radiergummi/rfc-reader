import Foundation
import Testing

@testable import RFCKit

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

extension HTTPURLResponse {
  /// A response as the server a stub stands in for sends it: with the
  /// `Content-Type` the RFC Editor and IANA serve a body of `url`'s extension as,
  /// which the client checks (#757), beside `headerFields`.
  static func served(
    from url: URL, statusCode: Int, headerFields: [String: String] = [:]
  ) -> HTTPURLResponse {
    var headers = headerFields
    switch url.pathExtension {
    case "xml": headers["Content-Type"] = "application/xml;charset=utf-8"
    case "txt": headers["Content-Type"] = "text/plain;charset=utf-8"
    default: break
    }
    return HTTPURLResponse(
      url: url, statusCode: statusCode, httpVersion: nil, headerFields: headers)!
  }
}

/// Answers every request with a scripted status and headers, and `body` for a `200`,
/// and keeps the last request it was sent.
final class ScriptedTransport: HTTPTransport, @unchecked Sendable {
  private let status: Int
  private let body: Data
  private let headers: [String: String]
  private let lock = NSLock()
  private var sent: URLRequest?

  init(status: Int, body: Data, headers: [String: String] = [:]) {
    self.status = status
    self.body = body
    self.headers = headers
  }

  var request: URLRequest? {
    lock.withLock { sent }
  }

  func response(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
    lock.withLock { sent = request }
    let response = HTTPURLResponse.served(
      from: request.url!, statusCode: status, headerFields: headers)
    return (status == 200 ? body : Data(), response)
  }
}

extension Block {
  /// The paragraph this block is, if it is one: what a test filters a block list by,
  /// written once instead of as an `if case` at every call site.
  var paragraph: Paragraph? {
    if case .paragraph(let paragraph) = self { paragraph } else { nil }
  }

  var list: ListBlock? {
    if case .list(let list) = self { list } else { nil }
  }

  var preformatted: Preformatted? {
    if case .preformatted(let preformatted) = self { preformatted } else { nil }
  }

  var references: ReferenceList? {
    if case .references(let list) = self { list } else { nil }
  }

  var table: Table? {
    if case .table(let table) = self { table } else { nil }
  }

  var figure: Figure? {
    if case .figure(let figure) = self { figure } else { nil }
  }

  var definitionList: DefinitionList? {
    if case .definitionList(let list) = self { list } else { nil }
  }

  var definitionItems: [DefinitionItem]? { definitionList?.items }

  var index: IndexBlock? {
    if case .index(let index) = self { index } else { nil }
  }
}

extension Inline {
  var crossReference: CrossReference? {
    if case .crossReference(let reference) = self { reference } else { nil }
  }
}

extension RFCDocument {
  /// The extractions the assertions open with. Every one of them is a filter of the
  /// same block list, and written out at each call site the filter -- which is the
  /// part that differs -- is the line you have to read four lines to find.
  ///
  /// The blocks directly in a section, not the nested ones and not the abstract:
  /// what these tests count. `RFCDocument.blocks` is every block (#131).
  var everyBlock: [Block] { allSections.flatMap(\.blocks) }

  /// The unnumbered text before the first heading, which the parser keeps as `preamble`.
  var leadIn: [Block] { sections.first { $0.anchor == "preamble" }?.blocks ?? [] }

  var referenceLists: [ReferenceList] { everyBlock.compactMap(\.references) }

  var paragraphs: [Paragraph] { everyBlock.compactMap(\.paragraph) }

  /// The items of each definition list: a catalog, or hanging-indent definitions.
  var definitionLists: [[DefinitionItem]] { everyBlock.compactMap(\.definitionItems) }

  /// Every paragraph at any depth: inside list items, definitions, figures, block
  /// quotes and asides as well as directly in a section.
  var nestedParagraphs: [Paragraph] { everyBlock.flattened.compactMap(\.paragraph) }

  /// Every verbatim block's text, a figure's included (#361).
  var artworkText: [String] { everyBlock.flattened.compactMap(\.preformatted).map(\.text) }

  var lists: [ListBlock] { everyBlock.compactMap(\.list) }

  /// What the XML declares as an ID: every section's anchor and every bibliography entry's.
  var declaredAnchors: [String] {
    allSections.map(\.anchor) + referenceLists.flatMap(\.entries).map(\.anchor)
  }

  var crossReferences: [CrossReference] {
    paragraphs.flatMap { $0.inlines.compactMap(\.crossReference) }
  }

  /// Every citation anywhere the linker runs: headings, the abstract, and prose at any
  /// depth -- lists, definitions, tables, quotes, a reference's annotation -- not only
  /// top-level paragraphs.
  var everyCrossReference: [CrossReference] { proseInlines.compactMap(\.crossReference) }
}

extension LegacyTextParser.Prelude {
  /// A prelude over hand-written lines, its body starting at `bodyStart`, set at column
  /// 0 or indented as `bodyIsIndented` says, and numbering its headings only with a full
  /// stop: what the segmentation guards are asked against.
  init(lines: [LegacyTextParser.Line], bodyStart: Int = 0, bodyIsIndented: Bool) {
    self.init(
      lines: lines, separators: [], proseIndent: LegacyTextParser.classicProseIndent, front: [],
      bodyStart: bodyStart, bodyIsIndented: bodyIsIndented)
  }
}
