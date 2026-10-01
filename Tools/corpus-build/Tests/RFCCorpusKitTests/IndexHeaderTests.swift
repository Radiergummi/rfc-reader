import Foundation
import RFCCorpusKit
import RFCKit
import Testing

/// What a converted legacy document's header takes from the RFC index rather than from
/// its title page (#218, #203).
@Suite("Index header")
struct IndexHeaderTests {
  private static func entry(
    number: Int = 1234,
    authors: [Author] = [Author(name: "A. Author")],
    date: PublicationDate = PublicationDate(year: 1980, month: 3),
    obsoletes: [DocumentID] = [],
    updates: [DocumentID] = []
  ) -> RFCMetadata {
    RFCMetadata(
      id: .rfc(number), title: "A Title", authors: authors, date: date, obsoletes: obsoletes,
      updates: updates)
  }

  private static func applied(
    _ entry: RFCMetadata, to header: DocumentHeader
  ) -> (header: DocumentHeader, notes: [String]) {
    var header = header
    let notes = IndexHeader.apply(entry, to: &header)
    return (header, notes)
  }

  @Test func `the index's authors replace the page's, in its order and with its roles`() {
    let page = DocumentHeader(
      id: .rfc(1234), title: "A Title", authors: [Author(name: "garbage l969")])
    let index = Self.entry(authors: [
      Author(name: "B. Second", role: .editor), Author(name: "A. First"),
    ])
    let header = Self.applied(index, to: page).header
    #expect(
      header.authors == [Author(name: "B. Second", role: .editor), Author(name: "A. First")])
  }

  @Test func `a page with no date takes the index's`() {
    let page = DocumentHeader(id: .rfc(1234), title: "A Title")
    let index = Self.entry(date: PublicationDate(year: 1982, month: 8))
    #expect(Self.applied(index, to: page).header.date == PublicationDate(year: 1982, month: 8))
  }

  @Test func `the index's date replaces a page date that differs`() {
    let page = DocumentHeader(
      id: .rfc(1234), title: "A Title", date: PublicationDate(year: 1983, month: 1))
    let index = Self.entry(date: PublicationDate(year: 1982, month: 8))
    #expect(Self.applied(index, to: page).header.date == PublicationDate(year: 1982, month: 8))
  }

  @Test func `a page that states no number takes the index's, with a note`() {
    let page = DocumentHeader(title: "A Title")
    let (header, notes) = Self.applied(Self.entry(number: 1483), to: page)
    #expect(header.id == .rfc(1483))
    #expect(notes == ["RFC number from the index; the front matter states none"])
  }

  @Test func `a page that states another number takes the index's, with a note`() {
    let page = DocumentHeader(id: .rfc(1843), title: "A Title")
    let (header, notes) = Self.applied(Self.entry(number: 1483), to: page)
    #expect(header.id == .rfc(1483))
    #expect(notes == ["RFC number from the index; the front matter states 1843"])
  }

  @Test func `a page that states the index's number needs no note`() {
    let page = DocumentHeader(id: .rfc(1234), title: "A Title")
    #expect(Self.applied(Self.entry(number: 1234), to: page).notes.isEmpty)
  }

  @Test func `what the document obsoletes and updates comes from the index`() {
    let page = DocumentHeader(
      id: .rfc(1234), title: "A Title", obsoletes: [.rfc(1)], updates: [.rfc(2)])
    let index = Self.entry(obsoletes: [.rfc(900)], updates: [.rfc(901), .rfc(902)])
    let header = Self.applied(index, to: page).header
    #expect(header.obsoletes == [.rfc(900)])
    #expect(header.updates == [.rfc(901), .rfc(902)])
  }

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
