/// An RFCXML part number, the `pn` attribute prep gives every numbered part of a
/// document: `section-4.2`, `section-appendix.a.1`, `figure-3`, `table-2`.
///
/// Read by the XML parser and written by the serializer, which is why both directions
/// live here: the two used to spell the vocabulary out separately.
enum PartNumber: Hashable, Sendable {
  /// A numbered section, `4.2`.
  case section(String)
  /// An appendix, `A.1`, which the attribute spells in lower case.
  case appendix(String)
  /// An appendix that calls itself an annex, `section-annex.a` (#428). RFCXML has no
  /// annex; the word is ours, kept where only this parser reads it, and the section's
  /// anchor stays an appendix's.
  case annex(String)
  case figure(Int)
  case table(Int)

  private static let sectionPrefix = "section-"
  private static let appendixPrefix = "section-appendix."
  private static let annexPrefix = "section-annex."
  private static let figurePrefix = "figure-"
  private static let tablePrefix = "table-"

  /// Nil for anything that is not one of the four: prep also numbers the boilerplate
  /// and the contents (`section-boilerplate.1`, `section-toc.1`), and those are no
  /// section the document numbers.
  init?(_ attribute: String) {
    if let number = Self.appendixNumber(attribute, prefix: Self.appendixPrefix) {
      self = .appendix(number)
    } else if let number = Self.appendixNumber(attribute, prefix: Self.annexPrefix) {
      self = .annex(number)
    } else if attribute.hasPrefix(Self.sectionPrefix) {
      let number = String(attribute.dropFirst(Self.sectionPrefix.count))
      guard number.first?.isNumber == true else { return nil }
      self = .section(number)
    } else if attribute.hasPrefix(Self.figurePrefix),
      let number = Int(attribute.dropFirst(Self.figurePrefix.count))
    {
      self = .figure(number)
    } else if attribute.hasPrefix(Self.tablePrefix),
      let number = Int(attribute.dropFirst(Self.tablePrefix.count))
    {
      self = .table(number)
    } else {
      return nil
    }
  }

  /// The part number of a numbered section, or of an appendix by the word it names
  /// itself by.
  init(
    sectionNumber number: String, isAppendix: Bool, word: Section.AppendixWord = .appendix
  ) {
    switch (isAppendix, word) {
    case (false, _): self = .section(number)
    case (true, .appendix): self = .appendix(number)
    case (true, .annex): self = .annex(number)
    }
  }

  /// What a document claims this part number by, so that no two sections hold it:
  /// an annex's is its appendix's, since an annex `A` and an appendix `A` share their
  /// anchor (#428). The serializer and the paragraphs' numbering claim by it alike.
  var claim: PartNumber {
    if case .annex(let number) = self { return .appendix(number) }
    return self
  }

  /// `a.1` after `prefix` → `A.1`: only the letter is raised.
  private static func appendixNumber(_ attribute: String, prefix: String) -> String? {
    guard attribute.hasPrefix(prefix) else { return nil }
    var parts = attribute.dropFirst(prefix.count).split(separator: ".").map(String.init)
    guard let first = parts.first else { return nil }
    parts[0] = first.uppercased()
    return parts.joined(separator: ".")
  }

  /// The value of the `pn` attribute.
  var attribute: String {
    switch self {
    case .section(let number):
      "\(Self.sectionPrefix)\(number)"
    case .appendix(let number):
      "\(Self.appendixPrefix)\(Self.lowercasingLetter(of: number))"
    case .annex(let number):
      "\(Self.annexPrefix)\(Self.lowercasingLetter(of: number))"
    case .figure(let number):
      "\(Self.figurePrefix)\(number)"
    case .table(let number):
      "\(Self.tablePrefix)\(number)"
    }
  }

  /// `A.1` → `a.1`: only the appendix's letter is lowered.
  private static func lowercasingLetter(of number: String) -> String {
    var parts = number.split(separator: ".").map(String.init)
    if let first = parts.first { parts[0] = first.lowercased() }
    return parts.joined(separator: ".")
  }
}
