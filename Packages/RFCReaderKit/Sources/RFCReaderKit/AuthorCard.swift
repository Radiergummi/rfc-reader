import Contacts
import Foundation
import RFCKit

/// The circle an author chip wears in the header (#19): a Contacts-style monogram,
/// tinted from the name.
public enum AuthorMonogram {
  /// The first letter of the first and the last word of the name, whatever its
  /// script: "Mark Nottingham" is "MN", "R. Fielding" "RF". A single word gives
  /// one letter.
  public static func initials(for name: String) -> String {
    let words = name.split(whereSeparator: \.isWhitespace)
    guard let first = words.first?.first else { return "" }
    guard words.count > 1, let last = words.last?.first else { return String(first).uppercased() }
    return (String(first) + String(last)).uppercased()
  }

  /// Which of `count` colours the name gets. FNV-1a over the name's UTF-8, not
  /// `hashValue`, which Swift seeds afresh every launch: the same person has to be
  /// the same colour in every document and every session.
  public static func tint(for name: String, among count: Int) -> Int {
    var hash: UInt64 = 0xcbf2_9ce4_8422_2325
    for byte in name.utf8 {
      hash ^= UInt64(byte)
      hash &*= 0x0000_0100_0000_01b3
    }
    return Int(hash % UInt64(count))
  }
}

/// The contact card an author chip opens (#19): an unsaved `CNMutableContact` of
/// exactly what the document publishes, for `CNContactViewController`. Nothing is
/// looked up or inferred.
public enum AuthorCard {
  /// Whether the document publishes anything beyond the name. A chip without it is
  /// not a button: a card holding only the name the chip already shows says nothing.
  public static func hasCard(_ author: Author) -> Bool {
    guard let contact = author.contact else { return false }
    return !contact.isEmpty
  }

  public static func contact(for author: Author) -> CNMutableContact {
    let card = CNMutableContact()
    // An author that is an organization: RFCXML names it by the organization alone,
    // and the parser takes that for the name.
    if let organization = author.contact?.organization, organization == author.name {
      card.contactType = .organization
    } else if let components = PersonNameComponentsFormatter().personNameComponents(
      from: author.name),
      components.familyName != nil
    {
      card.givenName = components.givenName ?? ""
      card.middleName = components.middleName ?? ""
      card.familyName = components.familyName ?? ""
    } else {
      card.familyName = author.name
    }
    // The one role RFCXML gives an author.
    if author.role != nil {
      card.jobTitle = "Editor"
    }
    guard let contact = author.contact else { return card }

    card.organizationName = contact.organization ?? ""
    card.emailAddresses = contact.emails.map {
      CNLabeledValue(label: CNLabelWork, value: $0 as NSString)
    }
    card.phoneNumbers =
      [(CNLabelWork, contact.phone), (CNLabelPhoneNumberWorkFax, contact.facsimile)]
      .compactMap { label, number in
        number.map { CNLabeledValue(label: label, value: CNPhoneNumber(stringValue: $0)) }
      }
    // As written: `AuthorContact.uri` is kept as text for the same reason.
    card.urlAddresses =
      contact.uri.map { [CNLabeledValue(label: CNLabelURLAddressHomePage, value: $0 as NSString)] }
      ?? []
    if let postal = contact.postal {
      card.postalAddresses = [CNLabeledValue(label: CNLabelWork, value: address(postal))]
    }
    return card
  }

  /// The author's own lines go into `street` as written, in their order: that form
  /// exists because many countries' addresses have no fields to put them in, and
  /// reassembling them in another country's order would be wrong.
  static func address(_ postal: PostalAddress) -> CNPostalAddress {
    let address = CNMutablePostalAddress()
    guard postal.postalLines.isEmpty else {
      address.street = postal.postalLines.joined(separator: "\n")
      return address
    }
    let pobox = postal.postOfficeBox.map { [$0] } ?? []
    address.street = (postal.extendedAddress + postal.street + pobox).joined(separator: "\n")
    address.subLocality = postal.cityArea ?? ""
    address.city = postal.city ?? ""
    address.state = postal.region ?? ""
    // Contacts has no field for a sorting code; beside the postal code is where
    // the countries that use one write it.
    address.postalCode = [postal.code, postal.sortingCode].compactMap { $0 }.joined(separator: " ")
    address.country = postal.country ?? ""
    return address
  }
}
