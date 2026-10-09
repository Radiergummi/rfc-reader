import Foundation
import Testing

@testable import RFCKit

/// A legacy document parsed with its RFC index entry takes its header from the entry,
/// as a converted one does (#767): the title page's guess is wrong in hundreds of
/// documents, and the app parses every legacy RFC from its text until a pack arrives.
@Suite("Legacy text parser: the index entry")
struct LegacyIndexEntryTests {
  /// RFC 1149's entry, with authors and a title its title page doesn't have, so what
  /// the header shows can only have come from the entry.
  static func entry() throws -> RFCMetadata {
    var entry = try #require(try Fixtures.sampleIndex()[1149])
    entry.authors = [Author(name: "B. Second", role: .editor), Author(name: "A. First")]
    return entry
  }

  @Test func `the header is the index entry's`() throws {
    let entry = try Self.entry()
    let header = LegacyTextParser.parse(try Fixtures.data("rfc1149.txt"), entry: entry).header
    #expect(header.id == .rfc(1149))
    #expect(header.authors == entry.authors)
    #expect(header.date == entry.date)
    #expect(header.obsoletes == entry.obsoletes)
    #expect(header.updates == entry.updates)
  }

  /// The title goes through the parse, which keeps the page's where it is the title
  /// and the index's where the page's guess is something else.
  @Test func `the title is chosen as the converter chooses it`() throws {
    let data = try Fixtures.data("rfc1149.txt")
    let entry = try Self.entry()
    let parsed = LegacyTextParser.parse(data, entry: entry).header.title
    let converted = LegacyTextParser.parse(
      LegacyTextParser.text(decoding: data), title: entry.title
    )
    .header.title
    #expect(parsed == converted)
  }

  /// A document parsed before the entry was at hand takes the entry's header when it
  /// is read, as one parsed with it has.
  @Test(arguments: try Fixtures.legacyTexts())
  func `the entry applied after the parse gives the header the parse would`(fixture: String)
    throws
  {
    let index = try Fixtures.sampleIndex()
    let data = try Fixtures.data(fixture)
    let page = LegacyTextParser.parse(data)
    guard let id = page.header.id, let entry = index[id] else { return }
    let applied = LegacyTextParser.applying(entry, to: page)
    let parsed = LegacyTextParser.parse(data, entry: entry)
    #expect(applied.header.authors == parsed.header.authors)
    #expect(applied.header.date == parsed.header.date)
    #expect(applied.header.id == parsed.header.id)
  }

  @Test func `a document read from XML is left as it is`() throws {
    let document = try Fixtures.document("rfc9283.xml")
    let entry = RFCMetadata(
      id: .rfc(9283), title: "Another", authors: [Author(name: "Z. Other")],
      date: PublicationDate(year: 2000))
    #expect(LegacyTextParser.applying(entry, to: document) == document)
  }

  /// Without an entry the page is all there is, as before.
  @Test func `without an entry the header is the page's`() throws {
    let data = try Fixtures.data("rfc1149.txt")
    #expect(LegacyTextParser.parse(data).header == LegacyTextParser.parse(data, entry: nil).header)
    #expect(LegacyTextParser.parse(data).header.authors != (try Self.entry()).authors)
  }
}
