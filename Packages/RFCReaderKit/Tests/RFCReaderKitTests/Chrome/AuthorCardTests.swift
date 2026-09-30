import Contacts
import Foundation
import RFCKit
import Testing

@testable import RFCReaderKit

/// The header's author chips (#19): the monogram each one wears, and the contact
/// card a chip opens, built from exactly what the document publishes.
@Suite("Author card")
struct AuthorCardTests {
  // MARK: - Monogram

  @Test func `initials are the first and last names' first letters`() {
    #expect(AuthorMonogram.initials(for: "Mark Nottingham") == "MN")
    #expect(AuthorMonogram.initials(for: "R. Fielding") == "RF")
    #expect(AuthorMonogram.initials(for: "J. Reschke") == "JR")
    #expect(AuthorMonogram.initials(for: "Jan Van den Berg") == "JB")
  }

  /// A generational suffix is not a name: "D. Eastlake 3rd" is "DE", not "D3".
  @Test func `a generational suffix is not an initial`() {
    #expect(AuthorMonogram.initials(for: "D. Eastlake 3rd") == "DE")
    #expect(AuthorMonogram.initials(for: "Donald E. Eastlake 3rd") == "DE")
    #expect(AuthorMonogram.initials(for: "John Smith Jr.") == "JS")
    #expect(AuthorMonogram.initials(for: "John Smith, Jr.") == "JS")
    #expect(AuthorMonogram.initials(for: "Henry Ford III") == "HF")
  }

  @Test func `a single name gives one initial`() {
    #expect(AuthorMonogram.initials(for: "Postel") == "P")
  }

  @Test func `initials are taken from any script`() {
    #expect(AuthorMonogram.initials(for: "Émile Zola") == "ÉZ")
    #expect(AuthorMonogram.initials(for: "李 明") == "李明")
  }

  @Test func `an empty name has no initials`() {
    #expect(AuthorMonogram.initials(for: "  ") == "")
  }

  /// Stable across launches, unlike `hashValue`, so the same name is the same
  /// color in every document and every session.
  @Test func `the tint is fixed for a name and within the palette`() {
    let count = AuthorMonogram.palette.count
    let tint = AuthorMonogram.tint(for: "Mark Nottingham", among: count)
    #expect(tint == AuthorMonogram.tint(for: "Mark Nottingham", among: count))
    #expect(AuthorMonogram.palette.indices.contains(tint))
    // Pinned, so a change to the hash or the palette's length — either of which
    // would recolor everyone — is a deliberate one. FNV-1a 64 of the name, modulo 8.
    #expect(count == 8)
    #expect(tint == 1)
    #expect(AuthorMonogram.tintColor(for: "Mark Nottingham") == AuthorMonogram.palette[1])
  }

  /// The initials are small bold text, so they are held to the HIG's 4.5:1 for text
  /// at standard sizes rather than the 3:1 it allows large text. The circle is
  /// opaque and its tints are fixed sRGB values rather than system colors, so this
  /// is the contrast in light and dark appearance alike.
  @Test func `every tint's initials clear 4.5 to 1`() {
    for tint in AuthorMonogram.palette {
      #expect(
        AuthorMonogram.initialsColor.contrast(with: tint) >= AuthorMonogram.minimumContrast,
        "\(tint)")
    }
    #expect(AuthorMonogram.minimumContrast == 4.5)
  }

  @Test func `different names spread across the palette`() {
    let names = [
      "A. Barth", "R. Fielding", "M. Nottingham", "J. Reschke", "J. Postel", "S. Bradner",
    ]
    let tints = Set(names.map { AuthorMonogram.tint(for: $0, among: 8) })
    #expect(tints.count > 1)
  }

  // MARK: - Contact card

  private func author(_ contact: AuthorContact?, role: Author.Role? = nil) -> Author {
    Author(name: "Mark Nottingham", role: role, contact: contact)
  }

  @Test func `the name is split the way Contacts expects`() {
    let contact = AuthorCard.contact(for: author(nil))
    #expect(contact.givenName == "Mark")
    #expect(contact.familyName == "Nottingham")
  }

  /// The formatter finds a title and a suffix as well as the names, and the card
  /// shows the whole name the document gives.
  @Test func `a title and a suffix stay on the card`() {
    let suffixed = AuthorCard.contact(for: Author(name: "John Smith Jr."))
    #expect(suffixed.givenName == "John")
    #expect(suffixed.familyName == "Smith")
    #expect(suffixed.nameSuffix == "Jr.")
    let titled = AuthorCard.contact(for: Author(name: "Dr. Jane Smith"))
    #expect(titled.namePrefix == "Dr.")
    #expect(titled.givenName == "Jane")
  }

  @Test func `an editor is marked as one`() {
    #expect(AuthorCard.contact(for: author(nil, role: .editor)).jobTitle == "Editor")
    #expect(AuthorCard.contact(for: author(nil)).jobTitle == "")
  }

  @Test func `every published field reaches the card`() {
    let card = AuthorCard.contact(
      for: author(
        AuthorContact(
          organization: "Cloudflare", phone: "+1 555 0100", facsimile: "+1 555 0101",
          emails: ["mnot@mnot.net", "mark@example.com"], uri: "https://www.mnot.net/")))
    #expect(card.organizationName == "Cloudflare")
    #expect(
      card.emailAddresses.map { $0.value as String } == ["mnot@mnot.net", "mark@example.com"])
    #expect(card.phoneNumbers.map(\.value.stringValue) == ["+1 555 0100", "+1 555 0101"])
    #expect(card.phoneNumbers.map(\.label) == [CNLabelWork, CNLabelPhoneNumberWorkFax])
    #expect(card.urlAddresses.map { $0.value as String } == ["https://www.mnot.net/"])
  }

  @Test func `a structured address is kept field by field`() throws {
    let card = AuthorCard.contact(
      for: author(
        AuthorContact(
          postal: PostalAddress(
            street: ["1 Example Street"], extendedAddress: ["Building 2"], cityArea: "Mitte",
            city: "Berlin", region: "BE", code: "10115", country: "Germany"))))
    let address = try #require(card.postalAddresses.first?.value)
    #expect(address.street == "Building 2\n1 Example Street")
    #expect(address.subLocality == "Mitte")
    #expect(address.city == "Berlin")
    #expect(address.state == "BE")
    #expect(address.postalCode == "10115")
    #expect(address.country == "Germany")
  }

  /// The author's own lines are the one form that works for many countries'
  /// addresses, so they are kept as written, in their order, and never parsed.
  @Test func `postal lines are kept in their own order`() throws {
    let lines = ["〒100-0001", "東京都千代田区", "千代田1-1"]
    let card = AuthorCard.contact(
      for: author(AuthorContact(postal: PostalAddress(postalLines: lines))))
    let address = try #require(card.postalAddresses.first?.value)
    #expect(address.street == lines.joined(separator: "\n"))
    #expect(address.city.isEmpty)
  }

  /// RFCXML names an author that is an organization by the organization alone, and
  /// the parser uses it as the name. That is a company card, not a person called
  /// "Internet Architecture Board".
  @Test func `an organization that is the author is a company card`() {
    let card = AuthorCard.contact(
      for: Author(
        name: "Internet Architecture Board",
        contact: AuthorContact(organization: "Internet Architecture Board", emails: ["iab@iab.org"])
      ))
    #expect(card.contactType == .organization)
    #expect(card.organizationName == "Internet Architecture Board")
    #expect(card.givenName.isEmpty)
    #expect(card.familyName.isEmpty)
  }

  /// Its organization is the name the chip already shows, so an organization that
  /// publishes nothing else has no card to open.
  @Test func `an organization that publishes only itself has no card`() {
    let name = "Internet Architecture Board"
    let itself = AuthorContact(organization: name)
    let withEmail = AuthorContact(organization: name, emails: ["iab@iab.org"])
    #expect(!AuthorCard.hasCard(Author(name: name, contact: itself)))
    #expect(AuthorCard.hasCard(Author(name: name, contact: withEmail)))
    // A person's organization is not their name, and is worth a card.
    #expect(AuthorCard.hasCard(author(AuthorContact(organization: "Fastly"))))
  }

  /// Contacts has no field for a sorting code, so it goes after the city, where
  /// France writes a CEDEX: "75008 Paris CEDEX 08", not "75008 CEDEX 08 Paris".
  @Test func `a sorting code is kept after the city`() throws {
    let card = AuthorCard.contact(
      for: author(
        AuthorContact(postal: PostalAddress(city: "Paris", code: "75008", sortingCode: "CEDEX 08")))
    )
    let address = try #require(card.postalAddresses.first?.value)
    #expect(address.postalCode == "75008")
    #expect(address.city == "Paris CEDEX 08")
  }

  @Test func `an author who publishes nothing has only a name`() {
    let card = AuthorCard.contact(for: author(nil))
    #expect(card.emailAddresses.isEmpty)
    #expect(card.postalAddresses.isEmpty)
    #expect(card.organizationName.isEmpty)
    #expect(!AuthorCard.hasCard(author(nil)))
    #expect(!AuthorCard.hasCard(author(AuthorContact())))
    #expect(AuthorCard.hasCard(author(AuthorContact(emails: ["a@example.com"]))))
  }
}
