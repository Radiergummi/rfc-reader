/// How a place in a document reads in words: what a citation, a cross reference's
/// label and the reader's chrome call a section or an appendix.
///
/// A place is what `RFCLink.section` holds: a section number, `4.2`, an appendix's
/// letter, `A.1`, or, for an appendix a legacy RFC numbers like a section, its
/// anchor, `appendix-1`, since the number alone names section 1 (#429).
public enum PlaceName {
  /// `Section 4.2`, `Appendix A.1`, `Appendix 1`. A `separator` of a no-break space
  /// keeps the word with the place.
  public static func spelledOut(_ place: String, separator: String = " ") -> String {
    if isAppendixAnchor(place) {
      return "Appendix\(separator)\(place.dropFirst(SectionAnchor.appendixPrefix.count))"
    }
    let isLettered = place.first?.isLetter == true && SectionAnchor.isSectionNumber(place)
    return "\(isLettered ? "Appendix" : "Section")\(separator)\(place)"
  }

  /// `§ 4.2`, `§ A.1`, and `Appendix 1`, which a section sign would call section 1.
  /// Unbreakable, as a chip's is.
  public static func abbreviated(_ place: String) -> String {
    isAppendixAnchor(place)
      ? spelledOut(place, separator: "\u{00A0}") : "§\u{00A0}\(place)"
  }

  /// Whether `place` is an appendix's anchor, `appendix-1`, rather than a number.
  static func isAppendixAnchor(_ place: String) -> Bool {
    place.hasPrefix(SectionAnchor.appendixPrefix)
  }
}
