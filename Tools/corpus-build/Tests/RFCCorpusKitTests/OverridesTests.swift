import Foundation
import RFCCorpusKit
import RFCKit
import Testing

#if canImport(FoundationXML)
  import FoundationXML
#endif

/// The committed overrides in `corpus/overrides/`: RFC 5261 patches, and the one
/// snapshot, `rfc1142.xml`. `convert` reads them only during a corpus run, so this is
/// what notices a broken one before then. Whether a patch still applies to the
/// converter's output needs the source text: `make corpus-overrides-check`, and the
/// corpus-backed suite below.
@Suite("Corpus overrides")
struct OverridesTests {
  static let directory = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().appending(path: "../../../../corpus/overrides")

  private static let overrides: [String] = {
    let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
    return names.filter { $0.hasSuffix(".xml") }.sorted()
  }()

  private static func data(_ name: String) throws -> Data {
    try Data(contentsOf: directory.appending(path: name))
  }

  /// As `convert` tells them apart: by the root element.
  private static func isPatch(_ name: String) throws -> Bool {
    try XMLDocument(data: try data(name)).rootElement()?.name == "diff"
  }

  @Test func `there are overrides`() {
    #expect(!Self.overrides.isEmpty)
  }

  @Test(arguments: overrides)
  func `each is a patch that reads, or a snapshot that parses with no known schema cause`(
    name: String
  ) throws {
    let data = try Self.data(name)
    if try Self.isPatch(name) {
      _ = try XMLPatch(parsing: data, name: name)
    } else {
      #expect(try !RFCXMLParser.parse(data).allSections.isEmpty)
      #expect(SchemaCheck.causes(in: data) == [])
    }
  }

  /// RFC 1142 is the one snapshot (#197): its correction rejoins words in the plain
  /// text, which a patch on the output cannot do.
  @Test func `only rfc1142 is a snapshot`() throws {
    #expect(try Self.overrides.filter { try !Self.isPatch($0) } == ["rfc1142.xml"])
  }

  /// RFC 1142's headings are recovered by `rfc1142.py`: every numbered heading of the
  /// standard, and none of the fragments a form feed used to cut a title into.
  @Test func `rfc1142 has every numbered heading`() throws {
    let sections = try RFCXMLParser.parse(try Self.data("rfc1142.xml")).allSections
    #expect(sections.count { $0.number != nil } == 255)
    let short = sections.map(\.titleText).filter { $0.count < 4 }
    #expect(short.isEmpty, "\(short)")
  }
}

/// The committed patches, applied to the documents they correct, as a corpus run
/// applies them: with the index's metadata (#197, #218).
@Suite("Corpus-backed: overrides", .enabled(if: CorpusText.isAvailable && CorpusText.hasIndex))
struct CorpusBackedOverridesTests {
  private static func patched(_ stem: String) throws -> RFCDocument {
    let patch = try XMLPatch(
      parsing: try Data(contentsOf: OverridesTests.directory.appending(path: "\(stem).xml")),
      name: "\(stem).xml")
    let metadata = try ConversionPlan.rfcNumber(of: stem).flatMap { try CorpusText.index()[$0] }
    let conversion = DocumentConverter().convert(
      text: try CorpusText.text(stem), stem: stem, metadata: metadata, patch: patch)
    let xml = try #require(conversion.xml, "\(conversion.report.failure ?? "")")
    return try RFCXMLParser.parse(xml)
  }

  private static func preamble(_ document: RFCDocument) throws -> [Block] {
    try #require(document.section(anchor: "preamble")).blocks
  }

  /// RFC 5's title page states the day, and its NLS file header goes (#172).
  @Test func `rfc5 has its day and no file header`() throws {
    let document = try Self.patched("rfc5")
    #expect(document.header.date?.day == 2)
    let blocks = try Self.preamble(document)
    #expect(blocks.count == 1)
    guard case .paragraph = blocks.first else {
      Issue.record("the preamble is \(blocks)")
      return
    }
  }

  /// RFC 822's title page states the day, and its blocks no longer stand ahead of the
  /// preface (#171).
  @Test func `rfc822 opens with its preface`() throws {
    let document = try Self.patched("rfc822")
    #expect(document.header.date?.day == 13)
    let first = try #require(try Self.preamble(document).first)
    guard case .preformatted(let artwork) = first else {
      Issue.record("the preamble opens with \(first)")
      return
    }
    #expect(artwork.text.trimmingCharacters(in: .whitespacesAndNewlines) == "PREFACE")
  }

  /// A patch on a document the run does not convert would do nothing without a word
  /// said, so it fails: RFC 570's text only points to its PostScript original (#316).
  @Test func `a patch on a skipped document fails`() throws {
    let patch = try XMLPatch(
      parsing: Data("<diff><remove sel=\"/rfc/@category\"/></diff>".utf8), name: "rfc570.xml")
    let conversion = DocumentConverter().convert(
      text: try CorpusText.text("rfc570"), stem: "rfc570", metadata: try CorpusText.index()[570],
      patch: patch)
    #expect(conversion.report.skipped == .publishedOnlyAsPDF)
    #expect(conversion.xml == nil)
    #expect(conversion.report.override == .patch)
    let failure = try #require(conversion.report.failure)
    #expect(failure.hasPrefix("rfc570.xml: "), "\(failure)")
  }
}
