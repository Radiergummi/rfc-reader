import Foundation
import RFCCorpusKit
import RFCKit
import Testing

/// `DocumentConverter` with a patch: the same call a corpus run, `--only` and these
/// tests make (#197). Over committed fixtures, so no RFC text is added.
@Suite("Converting with a patch")
struct PatchedConversionTests {
  private static func convert(_ operations: String) throws -> DocumentConverter.Conversion {
    let patch = try XMLPatch(parsing: Data("<diff>\(operations)</diff>".utf8), name: "rfc2119.xml")
    return DocumentConverter().convert(
      text: try Fixtures.text("rfc2119.txt"), stem: "rfc2119", metadata: nil, patch: patch)
  }

  @Test func `the patch applies to the converted document`() throws {
    let conversion = try Self.convert("<remove sel=\"//section[@pn='section-9']\"/>")
    let xml = try #require(conversion.xml)
    let document = try RFCXMLParser.parse(xml)
    #expect(document.section(anchor: "section-9") == nil)
    #expect(conversion.report.override == .patch)
    #expect(conversion.report.failure == nil)
    // Counted from the patched document, not the converter's.
    #expect(conversion.report.sections == document.allSections.count)
  }

  @Test func `the generator comment names the patch`() throws {
    let xml = try #require(try Self.convert("<remove sel=\"/rfc/@category\"/>").xml)
    let text = String(decoding: xml, as: UTF8.self)
    #expect(text.contains("from rfc2119.txt and patched by corpus/overrides/rfc2119.xml."))
  }

  /// A patch whose effect writing the document again undoes does less than it says,
  /// so it fails: the writer puts `version="3"` back. Its failure is also the proof
  /// that the patched path changes no byte of its own, artwork's spaces included,
  /// since only output equal to the converter's to the byte is refused. And unpatched,
  /// parsing and writing a converted document again gives the same bytes (#683),
  /// which a corpus run warns about where it does not.
  @Test(arguments: Fixtures.legacyTexts)
  func `a patch that changes nothing the model holds fails`(fixture: String) throws {
    let stem = String(fixture.dropLast(4))
    let text = try Fixtures.text(fixture)
    let patch = try XMLPatch(
      parsing: Data("<diff><remove sel=\"/rfc/@version\"/></diff>".utf8), name: "\(stem).xml")
    let unpatched = DocumentConverter().convert(text: text, stem: stem, metadata: nil)
    let roundTrip = unpatched.report.warnings.filter { $0.contains("round trip") }
    #expect(roundTrip.isEmpty, "\(roundTrip)")
    let patched = DocumentConverter().convert(
      text: text, stem: stem, metadata: nil, patch: patch)
    #expect(patched.xml == nil)
    #expect(
      patched.report.failure
        == "\(stem).xml, operation 1 (remove /rfc/@version): it changes nothing the model holds",
      "\(patched.report.failure ?? "")")
  }

  /// Each operation must take effect, or one that writing undoes would pass behind
  /// another that does not.
  @Test func `an operation that writing undoes fails beside one that takes effect`() throws {
    let conversion = try Self.convert(
      """
      <add sel="/rfc/front/date" type="@day">7</add>
      <remove sel="/rfc/@version"/>
      """)
    #expect(conversion.xml == nil)
    #expect(
      conversion.report.failure
        == "rfc2119.xml, operation 2 (remove /rfc/@version): it changes nothing the model holds",
      "\(conversion.report.failure ?? "")")
  }

  @Test func `a failing patch writes nothing and says why`() throws {
    let conversion = try Self.convert("<remove sel=\"//section[@pn='section-99']\"/>")
    #expect(conversion.xml == nil)
    #expect(
      conversion.report.failure
        == "rfc2119.xml, operation 1 (remove //section[@pn='section-99']): matched 0 nodes")
  }

  /// A comment in a paragraph is nothing the model holds, so writing the document
  /// again would drop its words without a word said.
  @Test func `a patch adding what the model cannot hold fails`() throws {
    let conversion = try Self.convert(
      "<add sel=\"//section[@pn='section-6']\"><t>Kept <cref>vanishing words</cref></t></add>")
    #expect(conversion.xml == nil)
    let failure = try #require(conversion.report.failure)
    #expect(failure.contains("vanishing"), "\(failure)")
  }

  @Test func `an unpatched document reports no override`() throws {
    let conversion = DocumentConverter().convert(
      text: try Fixtures.text("rfc2119.txt"), stem: "rfc2119", metadata: nil)
    #expect(conversion.report.override == nil)
  }
}

/// A patch on a document whose output is not a fixed point of parsing and writing,
/// which no committed fixture is: each of them round-trips, as the suite above pins.
@Suite("Corpus-backed: converting with a patch", .enabled(if: CorpusText.isAvailable))
struct CorpusBackedPatchedConversionTests {
  /// RFC 7322 is one of the documents of #686, whose XML written again is not the
  /// converter's. An operation writing undoes must be measured against the document
  /// written again, not against the converter's bytes, which writing again changes
  /// with or without the patch. Once #686 is fixed RFC 7322 round-trips, and this
  /// test says no more than the fixtures' do.
  @Test func `an operation that writing undoes fails on a document that does not round-trip`()
    throws
  {
    let text = try CorpusText.text("rfc7322")
    let unpatched = DocumentConverter().convert(text: text, stem: "rfc7322", metadata: nil)
    #expect(
      unpatched.report.warnings.contains { $0.contains("round trip") },
      "RFC 7322 round-trips (#686), so this shows nothing the fixtures do not")
    let patch = try XMLPatch(
      parsing: Data("<diff><remove sel=\"/rfc/@version\"/></diff>".utf8), name: "rfc7322.xml")
    let patched = DocumentConverter().convert(
      text: text, stem: "rfc7322", metadata: nil, patch: patch)
    #expect(patched.xml == nil)
    #expect(
      patched.report.failure
        == "rfc7322.xml, operation 1 (remove /rfc/@version): it changes nothing the model holds",
      "\(patched.report.failure ?? "")")
  }
}
