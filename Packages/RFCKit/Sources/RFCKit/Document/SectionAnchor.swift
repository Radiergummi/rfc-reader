/// The anchor a numbered section goes by where its source names none: `section-4.2`,
/// and `appendix-A.1` for a number that starts with a letter, as an appendix's does.
///
/// It is the RFC Editor's and Datatracker's fragment convention, which the app's own
/// scheme follows too, and the anchor the legacy parser gives its headings and its
/// `Section N` references. Written and read here only, so none of them can drift.
enum SectionAnchor {
  private static let sectionPrefix = "section-"
  private static let appendixPrefix = "appendix-"

  /// `4.2` → `section-4.2`, `A.1` → `appendix-A.1`.
  static func anchor(forSectionNumber number: String) -> String {
    number.first?.isLetter == true ? "\(appendixPrefix)\(number)" : "\(sectionPrefix)\(number)"
  }

  /// `section-4.2` → `4.2`, `appendix-A.1` → `A.1`, `page-12` → nil.
  static func sectionNumber(fromAnchor anchor: String) -> String? {
    for prefix in [sectionPrefix, appendixPrefix] where anchor.hasPrefix(prefix) {
      let number = String(anchor.dropFirst(prefix.count))
      return number.isEmpty ? nil : number
    }
    return nil
  }
}
