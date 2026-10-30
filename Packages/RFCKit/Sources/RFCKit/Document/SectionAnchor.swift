import Foundation

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
  /// section is named by its anchor already, `appendix-1`, and stays as it is; so
  /// does a section's anchor given as its place, `section-8.3`, which was written
  /// out as `appendix-section-8.3`.
  static func anchor(forSectionNumber number: String) -> String {
    if number.hasPrefix(appendixPrefix) || number.hasPrefix(sectionPrefix) { return number }
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
  ///
  /// An appendix letter is read in either case, `section-a.1` → `A.1`, as the prepped
  /// XML's `pn` attributes spell it (#276), and so is a top-level appendix's part
  /// number, `section-appendix.a` → `A`. What follows the prefix has to be a number:
  /// `section-foo` is nil, an anchor of its own, and so is a paragraph's part number,
  /// `section-4.2-3`, which the paragraph goes by.
  static func sectionNumber(fromAnchor anchor: String) -> String? {
    if case .appendix(let number) = PartNumber(anchor), number.first?.isLetter == true,
      isSectionNumber(number)
    {
      return number
    }
    for prefix in [sectionPrefix, appendixPrefix] where anchor.hasPrefix(prefix) {
      var number = String(anchor.dropFirst(prefix.count))
      guard isSectionNumber(number) else { return nil }
      if let letter = number.first, letter.isLetter {
        number = letter.uppercased() + number.dropFirst()
      }
      return prefix == appendixPrefix && number.first?.isNumber == true ? anchor : number
    }
    return nil
  }

  /// Whether `place` is shaped like a section number rather than an anchor: it
  /// starts with a digit, or is an appendix's single letter, alone or before a dot
  /// (`A`, `A.1`), and no dash follows the number, as a paragraph's does (`4.2-3`), nor
  /// an underscore, as a repeated legacy section's does (`1_2`, #491).
  static func isSectionNumber(_ place: String) -> Bool {
    guard let first = place.first, !place.contains(where: { $0 == "-" || $0 == "_" }) else {
      return false
    }
    let rest = place.dropFirst()
    return first.isNumber || (first.isLetter && (rest.isEmpty || rest.first == "."))
  }
}

/// What someone types to go to a section (#711): Go to Section… on the Mac and the
/// iPad, and the iOS # jump (#579), which share it. A section number as a heading
/// shows it, `4.2` or `A.1`, with or without a `§` before it or a dot after it, or
/// an anchor as a link spells it, `section-4.2`.
public enum SectionInput {
  /// The section number or anchor `typed` names, or nil where it names neither:
  /// `§ 4.2.` → `4.2`, `a.1` → `A.1`, `section-4.2` as it is.
  public static func place(_ typed: String) -> String? {
    var place = Substring(typed.trimmingCharacters(in: .whitespacesAndNewlines))
    if place.first == "§" {
      place = Substring(place.dropFirst().trimmingCharacters(in: .whitespaces))
    }
    if place.last == "." { place = place.dropLast() }
    let text = String(place)
    if SectionAnchor.sectionNumber(fromAnchor: text) != nil { return text }
    guard SectionAnchor.isSectionNumber(text) else { return nil }
    return text.prefix(1).uppercased() + text.dropFirst()
  }

  /// The anchor of the section among `sections`, or their subsections, that `typed`
  /// names: by its number, which a section whose source gave it an anchor of its own
  /// goes by too, or by its anchor. Nil where it names none of them.
  public static func anchor(_ typed: String, in sections: [Section]) -> String? {
    guard let place = place(typed) else { return nil }
    let number = SectionAnchor.sectionNumber(fromAnchor: place) ?? place
    return sections.lazy.flatMap(\.withSubsections)
      .first { $0.anchor == place || $0.number == number }?.anchor
  }
}
