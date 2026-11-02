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
/// fetches them and points it there, on a Mac, where this package builds. It passes
/// the Makefile's `CORPUS_TEST_XML_DOCUMENTS` as `RFC_CORPUS_XML_DOCUMENTS`, and a
/// document not on it is refused, even where a local corpus holds it; where it is not
/// set, nothing is refused.
enum CorpusXML {
  static var directory: URL? {
    guard let path = ProcessInfo.processInfo.environment["RFC_CORPUS_XML"], !path.isEmpty
    else { return nil }
    return URL(fileURLWithPath: path, isDirectory: true)
  }

  static var isAvailable: Bool { directory != nil }

  /// The stems `RFC_CORPUS_XML_DOCUMENTS` lists, where it is set.
  static var listedDocuments: Set<String>? {
    CorpusList.stems(in: "RFC_CORPUS_XML_DOCUMENTS")
  }

  /// `listed` is the list `stem` is checked against, the environment's unless a test
  /// passes its own.
  static func document(_ stem: String, listed: Set<String>? = listedDocuments) throws
    -> RFCDocument
  {
    guard let directory else { throw CorpusXMLError.notConfigured }
    if let listed, !listed.contains(stem) {
      throw CorpusXMLError.notListed(stem)
    }
    let file = directory.appendingPathComponent("\(stem).xml")
    guard FileManager.default.fileExists(atPath: file.path) else {
      throw CorpusXMLError.notFetched(stem)
    }
    return try RFCXMLParser.parse(try Data(contentsOf: file))
  }
}

/// The Makefile's lists of the documents the corpus-backed suites read, as `make
/// test-corpus-app` passes them in the environment.
enum CorpusList {
  /// The stems the environment variable `name` lists, separated by whitespace, or nil
  /// where it is not set.
  static func stems(in name: String) -> Set<String>? {
    guard let list = ProcessInfo.processInfo.environment[name] else { return nil }
    return Set(list.split(whereSeparator: \.isWhitespace).map(String.init))
  }
}

enum CorpusXMLError: Error, Equatable {
  /// `RFC_CORPUS_XML` is not set; a suite that reads the corpus is enabled only where it is.
  case notConfigured
  /// The document is not in the directory: `make test-corpus` and `make test-corpus-app`
  /// fetch only the documents listed in the Makefile's `CORPUS_TEST_XML_DOCUMENTS`.
  case notFetched(String)
  /// The document is not in `RFC_CORPUS_XML_DOCUMENTS`, the Makefile's
  /// `CORPUS_TEST_XML_DOCUMENTS`.
  case notListed(String)
}

extension CorpusXMLError: CustomStringConvertible {
  var description: String {
    switch self {
    case .notConfigured:
      "RFC_CORPUS_XML is not set"
    case .notFetched(let stem):
      "\(stem) is read by a corpus-backed test but not fetched: add it to CORPUS_TEST_XML_DOCUMENTS"
    case .notListed(let stem):
      "\(stem) is read by a corpus-backed test but not listed: add it to CORPUS_TEST_XML_DOCUMENTS"
    }
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
      if let anchor = ReaderLinkScheme.anchor(from: url) {
        if built.anchors.offset(of: anchor) == nil { unresolved.append(anchor) }
      } else if RFCLink(url: url) != RFCLink(id: .rfc(5234), section: "B.1") {
        unresolved.append(url.absoluteString)
      }
    }
    #expect(links > 50, "\(stem) has \(links) rule links")
    #expect(unresolved.isEmpty, "\(unresolved.prefix(10))")
  }

  /// A document fetched locally, by `make corpus`, but not on the Makefile's list is
  /// refused before its file is looked for: CI fetches only the listed ones (#986).
  @Test(.enabled(if: CorpusXML.listedDocuments != nil))
  func `a document not on the list is refused as not listed`() {
    #expect(throws: CorpusXMLError.notListed("rfc0")) { try CorpusXML.document("rfc0") }
  }

  @Test func `a listed document that is not fetched is refused as not fetched`() {
    #expect(throws: CorpusXMLError.notFetched("rfc0")) {
      try CorpusXML.document("rfc0", listed: ["rfc0"])
    }
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
