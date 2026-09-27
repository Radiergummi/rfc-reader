/// What the offer to return from a jump within a document says (#254).
public enum ReturnOffer {
  /// "Back to §4.2" for a numbered section, "Back to Top" before the reader had
  /// scrolled anywhere, and plain "Back" for a place without a number, such as the
  /// abstract.
  ///
  /// A place's section is whatever the history recorded: usually the anchor the
  /// reader had scrolled to, which `sectionNumbers` maps to its number, but a deep
  /// link or a section link can record the number itself. Read as a number first,
  /// in the same order `DocumentView.jump(toSection:)` resolves it, so the label
  /// names the section a tap on it goes to.
  public static func title(for place: Place, sectionNumbers: [String: String]) -> String {
    guard let section = place.section else { return "Back to Top" }
    if sectionNumbers.values.contains(section) {
      return "Back to §\(section)"
    }
    if let number = sectionNumbers[section] {
      return "Back to §\(number)"
    }
    return "Back"
  }
}
