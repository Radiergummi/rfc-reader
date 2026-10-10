import Foundation
import RFCCorpusKit
import RFCKit
import Testing

/// A converted legacy document's header comes from the RFC index rather than from its
/// title page (#218, #203). `IndexHeader` itself is RFCKit's, and tested there.
@Suite("Index header in conversion")
struct IndexHeaderConversionTests {
  /// Through the converter, on RFC 1149, whose index entry carries an April 1 day. Its
  /// title page already names the index's author, so the entry's authors are replaced
  /// with ones the page doesn't have, to show they come from the entry.
  @Test func `a conversion takes the header from the index entry`() throws {
    let text = LegacyTextParser.text(decoding: try Data(contentsOf: Fixtures.url("rfc1149.txt")))
    let index = try RFCIndexParser.parse(contentsOf: Fixtures.url("rfc-index-sample.xml"))
    var entry = try #require(index[1149])
    entry.authors = [Author(name: "B. Second", role: .editor), Author(name: "A. First")]
    let conversion = DocumentConverter().convert(text: text, stem: "rfc1149", metadata: entry)
    let header = try RFCXMLParser.parse(try #require(conversion.xml)).header
    #expect(header.id == .rfc(1149))
    #expect(header.authors.map(\.name) == ["B. Second", "A. First"])
    #expect(header.authors.map(\.role) == [.editor, nil])
    #expect(header.date == PublicationDate(year: 1990, month: 4, day: 1))
    #expect(!conversion.report.warnings.contains { $0.contains("RFC number") })
  }
}
