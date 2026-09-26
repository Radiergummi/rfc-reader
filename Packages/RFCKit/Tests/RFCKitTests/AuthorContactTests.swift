import Foundation
import Testing

@testable import RFCKit

/// What a document publishes about its authors beyond their names (#19), read
/// from RFCXML's `<author>` into the model rather than left as body text, and the
/// Authors' Addresses section that prep builds from the same elements (#113).
@Suite("Author contact details")
struct AuthorContactTests {
  private static func xml(_ name: String) throws -> RFCDocument {
    try RFCXMLParser.parse(try Fixtures.data(name))
  }

  // MARK: The header

  /// RFC 9682's one author has everything but a fax: a structured postal
  /// address, a phone number and an email address.
  @Test func aFullAddressIsStructured() throws {
    let author = try #require(try Self.xml("rfc9682.xml").header.authors.first)
    #expect(author.name == "Carsten Bormann")
    let contact = try #require(author.contact)
    #expect(contact.organization == "Universität Bremen TZI")
    #expect(
      contact.postal
        == PostalAddress(
          street: ["Postfach 330440"], city: "Bremen", code: "D-28359", country: "Germany"))
    #expect(contact.phone == "+49-421-218-63921")
    #expect(contact.emails == ["cabo@tzi.org"])
    #expect(contact.uri == nil)
  }

  @Test func aWebAddressIsAURL() throws {
    let authors = try Self.xml("rfc8771.xml").header.authors
    #expect(
      authors.map(\.contact?.uri) == [
        URL(string: "https://i-dunno.at/"), URL(string: "https://www.sinodun.com/"),
      ])
  }

  /// Nothing is looked up or inferred: a legacy header names its authors and no more.
  @Test func aLegacyHeaderHasNoContactDetails() throws {
    let document = LegacyTextParser.parse(try Fixtures.data("rfc2119.txt"))
    #expect(!document.header.authors.isEmpty)
    #expect(document.header.authors.allSatisfy { $0.contact == nil })
  }

  @Test func theAddressReadsAsTheRFCEditorSetsIt() {
    let postal = PostalAddress(
      street: ["Postfach 330440"], city: "Bremen", code: "D-28359", country: "Germany")
    #expect(postal.lines == ["Postfach 330440", "Bremen D-28359", "Germany"])
  }

  // MARK: The Authors' Addresses section

  /// One paragraph per author, a detail per line, where it used to be an aside
  /// per level of `<author><address><postal>`, nested three deep.
  @Test func eachAuthorIsOneParagraph() throws {
    let section = try #require(
      try Self.xml("rfc9682.xml").section(anchor: "authors-addresses"))
    #expect(section.blocks.count == 1)
    guard case .paragraph(let paragraph) = section.blocks.first else {
      Issue.record("expected a paragraph, got \(String(describing: section.blocks.first))")
      return
    }
    let lines = paragraph.inlines.split(separator: .lineBreak).map { Array($0).plainText }
    #expect(
      lines == [
        "Carsten Bormann", "Universität Bremen TZI", "Postfach 330440", "Bremen D-28359",
        "Germany", "Phone: +49-421-218-63921", "Email: cabo@tzi.org",
      ])
    let mailto = URL(string: "mailto:cabo@tzi.org")!
    #expect(paragraph.inlines.contains(.link(mailto, [.text("cabo@tzi.org")])))
  }

  /// The schema forbids an aside inside an aside, and a round trip is held to it.
  @Test(arguments: ["rfc8761.xml", "rfc8771.xml", "rfc8999.xml", "rfc9220.xml", "rfc9682.xml"])
  func noAsideHoldsAnother(fixture: String) throws {
    func nested(_ blocks: [Block], inAside: Bool) -> Bool {
      blocks.contains { block in
        switch block {
        case .aside(let inner): inAside || nested(inner, inAside: true)
        case .blockQuote(let inner): nested(inner, inAside: false)
        case .list(let list): list.items.contains { nested($0.blocks, inAside: false) }
        case .figure(let figure): nested(figure.blocks, inAside: false)
        default: false
        }
      }
    }
    let document = try Self.xml(fixture)
    #expect(!document.allSections.contains { nested($0.blocks, inAside: false) })
  }

  // MARK: A round trip

  @Test(arguments: ["rfc8771.xml", "rfc8999.xml", "rfc9682.xml"])
  func contactDetailsSurviveARoundTrip(fixture: String) throws {
    let document = try Self.xml(fixture)
    let reparsed = try RFCXMLParser.parse(Data(RFCXMLSerializer().serialize(document).utf8))
    #expect(reparsed.header.authors == document.header.authors)
  }
}
