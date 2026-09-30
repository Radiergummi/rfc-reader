/// The anchor a numbered section goes by where its source names none: `section-4.2`,
/// and `appendix-A.1` for a number that starts with a letter, as an appendix's does.
///
/// It is the RFC Editor's and Datatracker's fragment convention, which the app's own
/// scheme follows too, and the anchor the legacy parser gives its headings and its
/// `Section N` references. Written and read here only, so none of them can drift.
enum SectionAnchor {
  private static let sectionPrefix = "section-"
  static let appendixPrefix = "appendix-"

  /// `4.2` → `section-4.2`, `A.1` → `appendix-A.1`. An appendix numbered like a
  /// section is named by its anchor already, `appendix-1`, and stays as it is.
  static func anchor(forSectionNumber number: String) -> String {
    if number.hasPrefix(appendixPrefix) { return number }
    return number.first?.isLetter == true
      ? "\(appendixPrefix)\(number)" : "\(sectionPrefix)\(number)"
  }

  /// An appendix heading's anchor, whatever its number: `appendix-A.1`, and
  /// `appendix-2` for `APPENDIX 2`, which `anchor(forSectionNumber:)` would give a
  /// section's name.
  static func anchor(forAppendixNumber number: String) -> String {
    "\(appendixPrefix)\(number)"
  }

  /// `section-4.2` → `4.2`, `appendix-A.1` → `A.1`, `page-12` → nil. An appendix
  /// numbered like a section keeps its prefix, `appendix-1`, which is its anchor:
  /// read as `1`, it named section 1.
  static func sectionNumber(fromAnchor anchor: String) -> String? {
    for prefix in [sectionPrefix, appendixPrefix] where anchor.hasPrefix(prefix) {
      let number = String(anchor.dropFirst(prefix.count))
      guard !number.isEmpty else { return nil }
      return prefix == appendixPrefix && number.first?.isNumber == true ? anchor : number
    }
    return nil
  }
}
