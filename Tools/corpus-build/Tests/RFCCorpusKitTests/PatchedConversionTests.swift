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

  /// The patched output is the canonical one: written again from what the app reads,
  /// so a patched document differs from an unpatched one only where the patch does,
  /// artwork's spaces included. And unpatched, parsing and writing a converted document
  /// again gives the same bytes (#683), which a corpus run warns about where it does not.
  @Test(arguments: Fixtures.legacyTexts)
  func `a patch that changes nothing changes no byte`(fixture: String) throws {
    let stem = String(fixture.dropLast(4))
    let text = try Fixtures.text(fixture)
    let patch = try XMLPatch(
      parsing: Data("<diff><replace sel=\"/rfc/@version\">3</replace></diff>".utf8),
      name: "\(stem).xml")
    let unpatched = DocumentConverter().convert(text: text, stem: stem, metadata: nil)
    let roundTrip = unpatched.report.warnings.filter { $0.contains("round trip") }
    #expect(roundTrip.isEmpty, "\(roundTrip)")
    let patched = DocumentConverter().convert(
      text: text, stem: stem, metadata: nil, patch: patch)
    let xml = try #require(patched.xml, "\(patched.report.failure ?? "")")
    let restored = String(decoding: xml, as: UTF8.self).replacingOccurrences(
      of: "from \(stem).txt and patched by corpus/overrides/\(stem).xml.",
      with: "from \(stem).txt.")
    #expect(restored == unpatched.xml.map { String(decoding: $0, as: UTF8.self) })
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
