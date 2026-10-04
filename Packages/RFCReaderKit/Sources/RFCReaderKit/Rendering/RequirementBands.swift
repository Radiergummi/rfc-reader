import Foundation
import RFCKit

/// Where Implementer draws its requirement bands (#700): each BCP 14 sentence the
/// requirements index found (`Requirements`), as a range of the built text. The
/// band is drawn by the fragments that lay the sentence out, so a switch into or
/// out of Implementer changes no font and needs no rebuild.
///
/// A requirement says its sentence and the anchor it lands on, not where in the
/// build it is, so each is found there: from its anchor, or from the end of the
/// sentence before it where that is further on, to the end of its section's own
/// text, by its words alone. The build sets the same inlines the index read, but
/// spaces them, wraps them and draws citations as chips its own way, so only the
/// letters and digits are compared. A sentence not found there gets no band.
public struct RequirementBands: Sendable, Equatable {
  /// The band's tint, a highlighter's yellow over the page or a card, kept apart
  /// from a chip's accent and an aside's gray, and faint enough that a link on it
  /// clears the minimum contrast in either appearance (`AccentContrastTests`).
  public static let tint = (
    light: (color: SRGBColor(hex: 0xFF_CC00), opacity: 0.14),
    dark: (color: SRGBColor(hex: 0xFF_D600), opacity: 0.06)
  )

  /// The bands, in order, none overlapping another.
  public let ranges: [NSRange]

  public init() {
    ranges = []
  }

  public init(_ requirements: [Requirement], in built: BuiltDocument) {
    let units = Array(built.text.string.utf16)
    let words = Self.words(in: units)
    let sections = built.anchors.sections.entries.map(\.offset)
    var ranges: [NSRange] = []
    // In document order, as the index lists them: one sentence never starts
    // before the end of the one found before it.
    var cursor = 0
    for requirement in requirements {
      guard let anchor = built.anchors.offset(of: requirement.anchor),
        let section = built.anchors.offset(of: requirement.sectionAnchor)
      else { continue }
      // The section's own text ends at the next heading, of any depth.
      let next = sections.partitioningIndex { $0 > section }
      let end = next < sections.count ? sections[next] : units.count
      let sentenceUnits = Array(requirement.sentence.utf16)
      let sentence = Self.words(in: sentenceUnits).map { sentenceUnits[range: $0] }
      guard
        let found = Self.find(
          sentence, in: units, words: words, from: max(anchor, cursor), to: end)
          ?? Self.find(
            Self.droppingAsideLabel(sentence), in: units, words: words,
            from: max(anchor, cursor), to: end)
      else { continue }
      let band = Self.widened(found, to: requirement.sentence, in: units)
      ranges.append(band)
      cursor = NSMaxRange(band)
    }
    self.ranges = ranges
  }

  /// The bands that meet `range`, whole: where a band starts and ends decides
  /// which of its corners round, so a fragment needs more of it than it lays out.
  public func ranges(meeting range: NSRange) -> [NSRange] {
    let first = ranges.partitioningIndex { NSMaxRange($0) > range.location }
    return Array(ranges[first...].prefix { $0.location < NSMaxRange(range) })
  }

  // MARK: - Words

  /// Every run of letters and digits in `units`, in order.
  private static func words(in units: [UInt16]) -> [NSRange] {
    var words: [NSRange] = []
    var start: Int?
    for (index, unit) in units.enumerated() {
      if isWordCharacter(unit) {
        if start == nil { start = index }
      } else if let wordStart = start {
        words.append(NSRange(location: wordStart, length: index - wordStart))
        start = nil
      }
    }
    if let start { words.append(NSRange(location: start, length: units.count - start)) }
    return words
  }

  /// A letter or a digit. A surrogate half is neither: the key words, and every
  /// sentence stating one, are found by their other words just as well.
  private static func isWordCharacter(_ unit: UInt16) -> Bool {
    guard let scalar = Unicode.Scalar(unit) else { return false }
    return scalar.properties.isAlphabetic || scalar.properties.numericType != nil
  }

  /// The range from the first to the last of the words of `sentence`, where they
  /// come one after another in `units` between `start` and `end`.
  private static func find(
    _ sentence: [ArraySlice<UInt16>], in units: [UInt16], words: [NSRange], from start: Int,
    to end: Int
  ) -> NSRange? {
    guard !sentence.isEmpty else { return nil }
    var index = words.partitioningIndex { $0.location >= start }
    while index + sentence.count <= words.count,
      NSMaxRange(words[index + sentence.count - 1]) <= end
    {
      if zip(sentence, words[index..<(index + sentence.count)]).allSatisfy({
        units[range: $1] == $0
      }) {
        let last = words[index + sentence.count - 1]
        return NSRange(
          location: words[index].location, length: NSMaxRange(last) - words[index].location)
      }
      index += 1
    }
    return nil
  }

  /// `sentence` without the "Note" or "Notes" it opens with, which an aside's caption
  /// takes the place of in the build (#700); empty where it opens with neither, which
  /// finds nothing.
  private static func droppingAsideLabel(_ sentence: [ArraySlice<UInt16>])
    -> [ArraySlice<UInt16>]
  {
    guard let first = sentence.first,
      ["Note", "NOTE", "Notes", "NOTES"].contains(String(decoding: first, as: UTF16.self))
    else { return [] }
    return Array(sentence.dropFirst())
  }

  /// `found` taken out to what `sentence` has before its first word and after its
  /// last, an opening quote or a full stop, where the build has the same there.
  private static func widened(_ found: NSRange, to sentence: String, in units: [UInt16])
    -> NSRange
  {
    let sentenceUnits = Array(sentence.utf16)
    let leading = sentenceUnits.prefix { !isWordCharacter($0) }
    let trailing = sentenceUnits.reversed().prefix { !isWordCharacter($0) }.reversed()
    var start = found.location
    for unit in leading.reversed() {
      guard start > 0, units[start - 1] == unit else { break }
      start -= 1
    }
    var end = NSMaxRange(found)
    for unit in trailing {
      guard end < units.count, units[end] == unit else { break }
      end += 1
    }
    return NSRange(location: start, length: end - start)
  }
}

extension Array where Element == UInt16 {
  fileprivate subscript(range range: NSRange) -> ArraySlice<UInt16> {
    self[range.location..<NSMaxRange(range)]
  }
}
