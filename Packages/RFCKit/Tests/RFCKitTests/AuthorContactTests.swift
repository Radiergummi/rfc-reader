import Foundation
import Testing

@testable import RFCKit

/// What a document publishes about its authors beyond their names (#19), read
/// from RFCXML's `<author>` into the model rather than left as body text, and the
/// Authors' Addresses section that prep builds from the same elements (#113).
@Suite("Author contact details")
struct AuthorContactTests {
  // MARK: The header

  /// RFC 9682's one author has everything but a fax: a structured postal
  /// address, a phone number and an email address.
  @Test func `a full address is structured`() throws {
    let author = try #require(try Fixtures.document("rfc9682.xml").header.authors.first)
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

  @Test func `a web address is kept as written`() throws {
    let authors = try Fixtures.document("rfc8771.xml").header.authors
    #expect(authors.map(\.contact?.uri) == ["https://i-dunno.at/", "https://www.sinodun.com/"])
  }

  /// RFC 9652's author wrote the address as lines, which have no fields to recover.
  @Test func `postal lines are kept as lines`() throws {
    let author = try #require(try Fixtures.document("rfc9652.xml").header.authors.first)
    #expect(author.contact?.organization == nil, "`<organization/>` is empty")
    #expect(author.contact?.postal == PostalAddress(postalLines: ["Prahran", "Australia"]))
    #expect(author.contact?.postal?.lines == ["Prahran", "Australia"])
  }

  /// A building is not a street: RFC 9283's `<extaddr>` stays one.
  @Test func `an extended address is not a street`() throws {
    let author = try #require(try Fixtures.document("rfc9283.xml").header.authors.first)
    let postal = try #require(author.contact?.postal)
    #expect(postal.extendedAddress == ["School of Computer Science"])
    #expect(postal.street == ["PB 92019"])
    #expect(
      postal.lines == ["School of Computer Science", "PB 92019", "Auckland 1142", "New Zealand"])
  }

  /// Nothing is looked up or inferred: a legacy header names its authors and no more.
  @Test func `a legacy header has no contact details`() throws {
    let document = try Fixtures.document("rfc2119.txt")
    #expect(!document.header.authors.isEmpty)
    #expect(document.header.authors.allSatisfy { $0.contact == nil })
  }

  @Test func `the address reads as the RFC editor sets it`() {
    let postal = PostalAddress(
      street: ["Postfach 330440"], city: "Bremen", code: "D-28359", country: "Germany")
    #expect(postal.lines == ["Postfach 330440", "Bremen D-28359", "Germany"])
  }

  // MARK: The Authors' Addresses section

  private static func lines(_ block: Block?) -> [String] {
    guard case .paragraph(let paragraph) = block else {
      Issue.record("expected a paragraph, got \(String(describing: block))")
      return []
    }
    return paragraph.inlines.split(separator: .lineBreak).map { Array($0).plainText }
  }

  /// One paragraph per author, a detail per line, where it used to be an aside
  /// per level of `<author><address><postal>`, nested three deep.
  @Test func `each author is one paragraph`() throws {
    let section = try #require(
      try Fixtures.document("rfc9682.xml").section(anchor: "authors-addresses"))
    #expect(section.blocks.count == 1)
    let paragraph = try #require(
      section.blocks.first?.paragraph,
      "expected a paragraph, got \(String(describing: section.blocks.first))")
    let lines = paragraph.inlines.split(separator: .lineBreak).map { Array($0).plainText }
    #expect(
      lines == [
        "Carsten Bormann", "Universität Bremen TZI", "Postfach 330440", "Bremen D-28359",
        "Germany", "Phone: +49-421-218-63921", "Email: cabo@tzi.org",
      ])
    let mailto = URL(string: "mailto:cabo@tzi.org")!
    #expect(paragraph.inlines.contains(.link(mailto, [.text("cabo@tzi.org")])))
  }

  /// RFC 9631's Contributors section lists three people as `<contact>`s, which the
  /// schema gives an author's content. Each is a paragraph of their own, a
  /// district kept beside its city, where the names used to run together as
  /// inline text and everything else about them was dropped.
  @Test func `each contributor is one paragraph`() throws {
    let section = try #require(
      try Fixtures.document("rfc9631.xml").allSections.first { $0.titleText == "Contributors" })
    #expect(section.blocks.count == 3)
    #expect(
      Self.lines(section.blocks.dropFirst().first) == [
        "Yifeng Zhou", "ByteDance", "Building 1, AVIC Plaza", "43 N 3rd Ring W Rd",
        "Haidian District", "Beijing 100000", "China", "Email: yifeng.zhou@bytedance.com",
      ])
  }

  /// A `<contact>` in prose is still the name, inline.
  @Test func `a contact in prose is inline`() throws {
    let document = try Fixtures.document("rfc9682.xml")
    let thanks = document.allSections.flatMap(\.blocks).compactMap { block -> String? in
      guard case .paragraph(let paragraph) = block else { return nil }
      return paragraph.inlines.plainText
    }
    #expect(thanks.contains { $0.contains("the reviewers Marco Tiloca, Christian Amsüss") })
  }

  /// An organization is its own entry's name when no person is named, as
  /// `parseAuthor` has it, and is not repeated beneath itself. No published v3 RFC
  /// has such an author of its own (none of RFC 8650 onwards does), so there is no
  /// document to read one from.
  @Test func `an organization is not repeated as its own affiliation`() {
    let author = Author(
      name: "IAB", contact: AuthorContact(organization: "IAB", emails: ["iab@iab.org"]))
    #expect(
      RFCXMLParser.addressInlines(author) == [
        .text("IAB"), .lineBreak, .text("Email: "),
        .link(URL(string: "mailto:iab@iab.org")!, [.text("iab@iab.org")]),
      ])
  }

  /// An address is the `mailto:` URL's path, so a `?`, `#` or `%` in it is
  /// escaped rather than starting a query, a fragment or an escape.
  @Test func `a mailto link escapes the address`() throws {
    let url = try #require(RFCXMLParser.mailto("a?b#c%d@example.com"))
    #expect(url.absoluteString == "mailto:a%3Fb%23c%25d@example.com")
    // `URL.path` is empty for a URL with no authority on Apple's Foundation, so the
    // address is read back through the components that built it.
    let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
    #expect(components.path == "a?b#c%d@example.com")
  }

  /// A web address `URL` cannot read is shown as text, not dropped.
  @Test func `a web address that is no URL is text`() {
    #expect(URL(string: "http://[::1") == nil, "the host's bracket is never closed")
    let author = Author(name: "A", contact: AuthorContact(uri: "http://[::1"))
    #expect(
      RFCXMLParser.addressInlines(author) == [
        .text("A"), .lineBreak, .text("URI: "), .text("http://[::1"),
      ])
  }

  /// The schema forbids an aside inside an aside, and a round trip is held to it.
  @Test(arguments: ["rfc8761.xml", "rfc8771.xml", "rfc8999.xml", "rfc9220.xml", "rfc9682.xml"])
  func `no aside holds another`(fixture: String) throws {
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
    let document = try Fixtures.document(fixture)
    #expect(!document.allSections.contains { nested($0.blocks, inAside: false) })
  }

  // MARK: A round trip

  private static func roundTrip(_ document: RFCDocument) throws -> (String, RFCDocument) {
    let xml = RFCXMLSerializer().serialize(document)
    return (xml, try RFCXMLParser.parse(Data(xml.utf8)))
  }

  @Test(arguments: ["rfc8771.xml", "rfc8999.xml", "rfc9283.xml", "rfc9652.xml", "rfc9682.xml"])
  func `contact details survive a round trip`(fixture: String) throws {
    let document = try Fixtures.document(fixture)
    #expect(try Self.roundTrip(document).1.header.authors == document.header.authors)
  }

  /// The form is the author's to choose, and written back as chosen.
  @Test func `postal lines are written back as lines`() throws {
    let (xml, _) = try Self.roundTrip(try Fixtures.document("rfc9652.xml"))
    #expect(xml.contains("<postalLine>Prahran</postalLine>"))
    #expect(!xml.contains("<street>"))
  }

  @Test func `an extended address is written back as one`() throws {
    let (xml, _) = try Self.roundTrip(try Fixtures.document("rfc9283.xml"))
    #expect(xml.contains("<extaddr>School of Computer Science</extaddr>"))
    #expect(xml.contains("<street>PB 92019</street>"))
  }

  @Test func `a web address that is no URL survives a round trip`() throws {
    var document = try Fixtures.document("rfc9682.xml")
    document.header.authors[0].contact?.uri = "http://[::1"
    let (_, reparsed) = try Self.roundTrip(document)
    #expect(reparsed.header.authors.first?.contact?.uri == "http://[::1")
  }
}
