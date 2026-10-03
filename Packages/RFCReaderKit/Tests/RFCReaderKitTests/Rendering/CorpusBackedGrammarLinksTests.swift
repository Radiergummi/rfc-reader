import Foundation
import RFCKit
import Testing

@testable import RFCReaderKit

#if canImport(UIKit)
  import UIKit
#else
  import AppKit
#endif

/// The RFCs authored in RFCXML that a corpus-backed suite reads, from the directory
/// `RFC_CORPUS_XML` names, as RFCKit's `CorpusText` reads them: `make test-corpus`
/// fetches them and points it there, on a Mac, where this package builds.
private enum CorpusXML {
  static var directory: URL? {
    guard let path = ProcessInfo.processInfo.environment["RFC_CORPUS_XML"], !path.isEmpty
    else { return nil }
    return URL(fileURLWithPath: path, isDirectory: true)
  }

  static var isAvailable: Bool { directory != nil }

  static func document(_ stem: String) throws -> RFCDocument {
    let file = try #require(directory).appendingPathComponent("\(stem).xml")
    return try RFCXMLParser.parse(try Data(contentsOf: file))
  }
}

/// ABNF rule names as links (#185) over the grammars of RFC 9110, which spreads its
/// rules over every section that defines a field, and RFC 9112, which uses RFC 9110's
/// beside its own: those stay plain until rules are resolved across documents.
@Suite("Corpus-backed: ABNF links", .enabled(if: CorpusXML.isAvailable))
struct CorpusBackedGrammarLinksTests {
  @Test(arguments: ["rfc9110", "rfc9112"])
  func `every rule link goes to an anchor the document holds, or to RFC 5234`(stem: String) throws {
    let document = try CorpusXML.document(stem)
    let built = DocumentTextBuilder.build(document, style: ReadingStyle())
    var links = 0
    var unresolved: [String] = []
    let whole = NSRange(location: 0, length: built.text.length)
    built.text.enumerateAttribute(.link, in: whole) { value, range, _ in
      guard let url = value as? URL,
        built.text.attribute(.rfcVerbatim, at: range.location, effectiveRange: nil) != nil
      else { return }
      links += 1
      if let anchor = DocumentTextBuilder.anchor(from: url) {
        if built.anchors.offset(of: anchor) == nil { unresolved.append(anchor) }
      } else if RFCLink(url: url) != RFCLink(id: .rfc(5234), section: "B.1") {
        unresolved.append(url.absoluteString)
      }
    }
    #expect(links > 50, "\(stem) has \(links) rule links")
    #expect(unresolved.isEmpty, "\(unresolved.prefix(10))")
  }

  @Test(arguments: ["rfc9110", "rfc9112"])
  func `a linked grammar's text is unchanged`(stem: String) throws {
    let document = try CorpusXML.document(stem)
    let linked = DocumentTextBuilder.build(document, style: ReadingStyle())
    let plain = DocumentTextBuilder.build(
      document, style: ReadingStyle(), choices: PresentationChoices(preferred: .text))
    #expect(linked.text.string == plain.text.string)
  }

  /// RFC 9110 collects its grammar by hand in an appendix; the export collects the
  /// same rules from the sections that define them.
  @Test func `RFC 9110's grammar exports`() throws {
    let text = try #require(GrammarExport.text(for: try CorpusXML.document("rfc9110")))
    let rules = try #require(ABNF.parse(text))
    #expect(rules.count > 100)
  }
}
