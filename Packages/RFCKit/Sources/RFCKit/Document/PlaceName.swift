/// How a place in a document reads in words: what a citation, a cross reference's
/// label and the reader's chrome call a section or an appendix.
///
/// A place is what `RFCLink.section` holds: a section number, `4.2`, an appendix's
/// letter, `A.1`, or, for an appendix a legacy RFC numbers like a section, its
/// anchor, `appendix-1`, since the number alone names section 1 (#429).
public enum PlaceName {
  /// `Section 4.2`, `Appendix A.1`, `Appendix 1`.
  public static func spelledOut(_ place: String) -> String {
    if place.hasPrefix(SectionAnchor.appendixPrefix) {
      return "Appendix \(place.dropFirst(SectionAnchor.appendixPrefix.count))"
    }
    return place.first?.isLetter == true ? "Appendix \(place)" : "Section \(place)"
  }

  /// `§ 4.2`, `§ A.1`, and `Appendix 1`, which a section sign would call section 1.
  /// Unbreakable, as a chip's is.
  public static func abbreviated(_ place: String) -> String {
    let name =
      place.hasPrefix(SectionAnchor.appendixPrefix) ? spelledOut(place) : "§ \(place)"
    return name.replacing(" ", with: "\u{00A0}")
  }
}
