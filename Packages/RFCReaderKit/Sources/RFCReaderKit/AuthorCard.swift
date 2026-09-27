import Contacts
import Foundation
import RFCKit

/// The circle an author chip wears in the header (#19): a Contacts-style monogram,
/// white initials on a tint picked from the name.
public enum AuthorMonogram {
  /// The contrast the initials need against their tint. They are small bold text,
  /// and Apple's Human Interface Guidelines (Accessibility › Color and effects) ask
  /// for at least 4.5:1 for text at standard sizes, 3:1 only for large text — the
  /// same two thresholds as WCAG 2.x success criterion 1.4.3, whose relative
  /// luminance and contrast ratio `SRGBColour` computes.
  public static let minimumContrast = 4.5

  /// White, as Contacts draws them, on every tint: the palette is made to clear
  /// ``minimumContrast`` with white rather than the initials switching to black on
  /// the lighter tints, so every chip looks like every other.
  public static let initialsColour = SRGBColour.white

  /// The system colours' hues — red, orange, yellow, green, mint, teal, blue and
  /// indigo, as iOS draws them in light appearance — each darkened until white
  /// initials clear ``minimumContrast``, by scaling its linear-light channels
  /// equally, which keeps the hue. The system colours themselves cannot be used:
  /// white on them measures 1.5:1 (yellow) to 4.0:1 (blue), only indigo passing,
  /// and they resolve to different values by appearance and platform, so no one
  /// measurement would hold. These are fixed, and the circle is opaque, so the
  /// contrast is the same in light and dark appearance. Indigo passed as it was.
  ///
  /// The order is the one ``tint(for:among:)`` indexes into: reordering it, or
  /// changing its length, recolours every author.
  public static let palette: [SRGBColour] = [
    SRGBColour(hex: 0xDD_3228),  // red, 4.60:1 (the system colour's 3.55:1)
    SRGBColour(hex: 0xAD_6300),  // orange, 4.60:1 (2.20:1)
    SRGBColour(hex: 0x8F_7200),  // yellow, 4.59:1 (1.51:1)
    SRGBColour(hex: 0x20_873A),  // green, 4.58:1 (2.22:1)
    SRGBColour(hex: 0x00_837D),  // mint, 4.62:1 (2.12:1)
    SRGBColour(hex: 0x20_8091),  // teal, 4.61:1 (2.57:1)
    SRGBColour(hex: 0x00_71ED),  // blue, 4.58:1 (4.02:1)
    SRGBColour(hex: 0x58_56D6),  // indigo, 5.65:1, unchanged
  ]

  /// The tint a name wears: ``palette`` indexed by ``tint(for:among:)``.
  public static func tintColour(for name: String) -> SRGBColour {
    palette[tint(for: name, among: palette.count)]
  }

  /// The first letter of the first and the last word of the name, whatever its
  /// script: "Mark Nottingham" is "MN", "R. Fielding" "RF". A single word gives
  /// one letter. A generational suffix is not the last word: "D. Eastlake 3rd" is
  /// "DE", not "D3".
  public static func initials(for name: String) -> String {
    var words = name.split(whereSeparator: \.isWhitespace)
    while words.count > 1, let last = words.last, isGenerationalSuffix(last) {
      words.removeLast()
    }
    guard let first = words.first?.first else { return "" }
    guard words.count > 1, let last = words.last?.first else { return String(first).uppercased() }
    return (String(first) + String(last)).uppercased()
  }

  /// "Jr.", "Sr", "III", or a word that starts with a digit, like "3rd".
  private static func isGenerationalSuffix(_ word: Substring) -> Bool {
    guard let first = word.first, !first.isNumber else { return true }
    let bare = word.trimmingCharacters(in: CharacterSet(charactersIn: ".,")).lowercased()
    return ["jr", "sr", "ii", "iii", "iv"].contains(bare)
  }

  /// Which of `count` colours the name gets. FNV-1a over the name's UTF-8, not
  /// `hashValue`, which Swift seeds afresh every launch: the same name has to be
  /// the same colour in every document and every session. It is the name as
  /// written, so a person spelled differently ("R. Fielding", "Roy T. Fielding")
  /// can wear two colours.
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
    // Contacts has no field for a sorting code; after the city is where the
    // countries that use one write it ("75008 Paris CEDEX 08").
    address.city = [postal.city, postal.sortingCode].compactMap { $0 }.joined(separator: " ")
    address.state = postal.region ?? ""
    address.postalCode = postal.code ?? ""
    address.country = postal.country ?? ""
    return address
  }
}
