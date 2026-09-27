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

  /// Stable across launches, unlike `hashValue`, so the same person is the same
  /// colour in every document and every session.
  @Test func `the tint is fixed for a name and within the palette`() {
    let tint = AuthorMonogram.tint(for: "Mark Nottingham", among: 8)
    #expect(tint == AuthorMonogram.tint(for: "Mark Nottingham", among: 8))
    #expect((0..<8).contains(tint))
    // Pinned, so a change to the hash — which would recolour everyone — is a
    // deliberate one. FNV-1a 64 of the name, modulo 8.
    #expect(AuthorMonogram.tint(for: "Mark Nottingham", among: 8) == 1)
  }

  @Test func `different names spread across the palette`() {
    let names = [
      "A. Barth", "R. Fielding", "M. Nottingham", "J. Reschke", "J. Postel", "S. Bradner",
    ]
    let tints = Set(names.map { AuthorMonogram.tint(for: $0, among: 8) })
    #expect(tints.count > 1)
  }

  // MARK: - Contact card

  private func author(_ contact: AuthorContact?, role: String? = nil) -> Author {
    Author(name: "Mark Nottingham", role: role, contact: contact)
  }

  @Test func `the name is split the way Contacts expects`() {
    let contact = AuthorCard.contact(for: author(nil))
    #expect(contact.givenName == "Mark")
    #expect(contact.familyName == "Nottingham")
  }

  @Test func `an editor is marked as one`() {
    #expect(AuthorCard.contact(for: author(nil, role: "editor")).jobTitle == "Editor")
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
