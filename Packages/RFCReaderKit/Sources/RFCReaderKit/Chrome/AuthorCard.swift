import Contacts
import Foundation
import RFCKit

/// The contact card an author chip opens (#19): an unsaved `CNMutableContact` of
/// exactly what the document publishes, for `CNContactViewController`. Nothing is
/// looked up or inferred.
public enum AuthorCard {
  /// Whether the document publishes anything beyond the name. A chip without it is
  /// not a button: a card holding only the name the chip already shows says nothing.
  ///
  /// An author that is an organization and publishes only that has nothing beyond
  /// the name either: its organization is the name.
  public static func hasCard(_ author: Author) -> Bool {
    guard var contact = author.contact else { return false }
    if isOrganization(author) {
      contact.organization = nil
    }
    return !contact.isEmpty
  }

  /// An author that is an organization: RFCXML names it by the organization alone,
  /// and the parser takes that for the name.
  private static func isOrganization(_ author: Author) -> Bool {
    author.contact?.organization == author.name
  }

  public static func contact(for author: Author) -> CNMutableContact {
    let card = CNMutableContact()
    if isOrganization(author) {
      card.contactType = .organization
    } else if let components = PersonNameComponentsFormatter().personNameComponents(
      from: author.name),
      components.familyName != nil
    {
      card.namePrefix = components.namePrefix ?? ""
      card.givenName = components.givenName ?? ""
      card.middleName = components.middleName ?? ""
      card.familyName = components.familyName ?? ""
      card.nameSuffix = components.nameSuffix ?? ""
    } else {
      card.familyName = author.name
    }
    // The one role the index and both parsers record.
    if author.isEditor {
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
    // Contacts has no field for a sorting code; after the city is where the
    // countries that use one write it ("75008 Paris CEDEX 08").
    address.city = [postal.city, postal.sortingCode].compactMap { $0 }.joined(separator: " ")
    address.state = postal.region ?? ""
    address.postalCode = postal.code ?? ""
    address.country = postal.country ?? ""
    return address
  }
}
