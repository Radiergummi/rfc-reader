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
  case figure(Int)
  case table(Int)

  private static let sectionPrefix = "section-"
  private static let appendixPrefix = "section-appendix."
  private static let figurePrefix = "figure-"
  private static let tablePrefix = "table-"

  /// Nil for anything that is not one of the four: prep also numbers the boilerplate
  /// and the contents (`section-boilerplate.1`, `section-toc.1`), and those are no
  /// section the document numbers.
  init?(_ attribute: String) {
    if attribute.hasPrefix(Self.appendixPrefix) {
      var parts = attribute.dropFirst(Self.appendixPrefix.count).split(separator: ".").map(
        String.init)
      guard let first = parts.first else { return nil }
      parts[0] = first.uppercased()
      self = .appendix(parts.joined(separator: "."))
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

  /// The part number of a numbered section, or of an appendix.
  init(sectionNumber number: String, isAppendix: Bool) {
    self = isAppendix ? .appendix(number) : .section(number)
  }

  /// The value of the `pn` attribute.
  var attribute: String {
    switch self {
    case .section(let number):
      "\(Self.sectionPrefix)\(number)"
    case .appendix(let number):
      "\(Self.appendixPrefix)\(Self.lowercasingLetter(of: number))"
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
