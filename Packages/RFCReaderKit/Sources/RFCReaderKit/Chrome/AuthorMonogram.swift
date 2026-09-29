import Foundation

/// The circle an author chip wears in the header (#19): a Contacts-style monogram,
/// white initials on a tint picked from the name.
public enum AuthorMonogram {
  /// The contrast the initials need against their tint. They are small bold text,
  /// and Apple's Human Interface Guidelines (Accessibility › Color and effects) ask
  /// for at least 4.5:1 for text at standard sizes, 3:1 only for large text — the
  /// same two thresholds as WCAG 2.x success criterion 1.4.3, whose relative
  /// luminance and contrast ratio `SRGBColor` computes.
  public static let minimumContrast = 4.5

  /// White, as Contacts draws them, on every tint: the palette is made to clear
  /// ``minimumContrast`` with white rather than the initials switching to black on
  /// the lighter tints, so every chip looks like every other.
  public static let initialsColor = SRGBColor.white

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
  public static let palette: [SRGBColor] = [
    SRGBColor(hex: 0xDD_3228),  // red, 4.60:1 (the system colour's 3.55:1)
    SRGBColor(hex: 0xAD_6300),  // orange, 4.60:1 (2.20:1)
    SRGBColor(hex: 0x8F_7200),  // yellow, 4.59:1 (1.51:1)
    SRGBColor(hex: 0x20_873A),  // green, 4.58:1 (2.22:1)
    SRGBColor(hex: 0x00_837D),  // mint, 4.62:1 (2.12:1)
    SRGBColor(hex: 0x20_8091),  // teal, 4.61:1 (2.57:1)
    SRGBColor(hex: 0x00_71ED),  // blue, 4.58:1 (4.02:1)
    SRGBColor(hex: 0x58_56D6),  // indigo, 5.65:1, unchanged
  ]

  /// The tint a name wears: ``palette`` indexed by ``tint(for:among:)``.
  public static func tintColor(for name: String) -> SRGBColor {
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
