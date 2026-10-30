import Foundation

/// What an index's locator reads as: prep's label for the place, `Section 3.7,
/// Paragraph 6`, shortened to `§3.7 ¶6`, the way an index cites places. An item
/// level (`, Item 2`) is dropped from the label; the link still leads to the item.
/// A label of any other shape (`Table 2`) is prep's, unchanged.
public enum IndexLocatorLabel {
  private static let places = ["Section ", "Appendix "]
  private static let paragraph = "Paragraph "
  private static let item = "Item "

  public static func short(_ label: String) -> String {
    let parts = label.replacingOccurrences(of: "\u{00A0}", with: " ")
      .components(separatedBy: ", ")
    guard let place = places.first(where: { parts[0].hasPrefix($0) }),
      parts[0].count > place.count, parts.count <= 3
    else { return label }
    var result = "§" + parts[0].dropFirst(place.count)
    if parts.count >= 2 {
      guard parts[1].hasPrefix(paragraph), parts[1].count > paragraph.count else { return label }
      // NO-BREAK SPACE: the paragraph never wraps away from its section.
      result += "\u{00A0}¶" + parts[1].dropFirst(paragraph.count)
    }
    if parts.count == 3, !parts[2].hasPrefix(item) { return label }
    return result
  }
}
