import Foundation

/// The `(Normative)` or `(Informative)` an appendix heading opens its title with,
/// `Annex B (informative): Title` or `Appendix A. (Normative) Title` (#428). One reading
/// for both parsers: the legacy parser takes it out of a heading, the serializer writes
/// it back into `<name>` as `written(_:)` spells it, and the XML parser takes it out
/// again, so the model reads back as it was written.
enum HeadingQualifier {
  /// The qualifier `title` opens with, and the title without it and the separator
  /// after it. The whole title, and no qualifier, when it opens with neither: a title
  /// that only mentions "normative" further on is left alone.
  static func split(_ title: String) -> (qualifier: Section.Qualifier?, title: String) {
    guard let match = title.prefixMatch(of: pattern),
      let qualifier = Section.Qualifier(rawValue: match.word.lowercased())
    else { return (nil, title) }
    return (qualifier, String(title[match.range.upperBound...]))
  }

  /// `split(_:)` over a heading's inlines: the qualifier is in the first run of text.
  static func split(_ title: [Inline]) -> (qualifier: Section.Qualifier?, title: [Inline]) {
    guard case .text(let first)? = title.first else { return (nil, title) }
    let (qualifier, rest) = split(first)
    guard let qualifier else { return (nil, title) }
    return (qualifier, (rest.isEmpty ? [] : [.text(rest)]) + title.dropFirst())
  }

  /// `(Normative)` or `(Informative)`, as the serializer writes it ahead of a title.
  static func written(_ qualifier: Section.Qualifier) -> String {
    switch qualifier {
    case .normative: "(Normative)"
    case .informative: "(Informative)"
    }
  }

  /// The word in parentheses, then whatever sets the title off from it: a colon, a
  /// full stop, dashes, or spaces alone.
  private static let pattern = Pattern(
    #/\((?<word>(?i:normative|informative))\)\s*(?:[:.]|-+|–|—)?\s*/#)
}
