import Foundation
import RFCKit

/// What the Contents tab shows: a document's sections in its own order or A–Z,
/// narrowed by words in a title or the start of its heading.
///
/// What is listed is decided here, under test; `TableOfContentsView` only draws it.
public enum ContentsOutline {
  /// How the tab orders the sections. Remembered app-wide by its raw value.
  public enum Order: String, Sendable {
    case document
    case alphabetical
  }

  /// A section in the document's order.
  public struct Row: Identifiable, Sendable {
    public let anchor: String
    /// `4.2. Caching`.
    public let title: String
    /// How far the row is indented.
    public let depth: Int
    /// An ancestor shown only so a match keeps its place in the hierarchy.
    public let isContext: Bool

    public var id: String { anchor }
  }

  /// A section in A–Z.
  public struct Entry: Identifiable, Sendable {
    public let anchor: String
    /// The title alone, or the number it is shown by for a section without words.
    public let title: String
    /// `4.2` or `Appendix A`, set beside the title, with an appendix named by the
    /// labels the list was given: `Anhang A` in a German translation (#940).
    public let caption: String?

    public var id: String { anchor }
  }

  /// The entries under one letter.
  public struct Group: Identifiable, Sendable {
    /// `A` to `Z`, or `#` for every title that does not start with a Latin letter.
    public let label: String
    public let entries: [Entry]

    public var id: String { label }
  }

  /// `sections`, which are flat and in document order, narrowed by `filter`: each
  /// match after those of its ancestors not already listed, which are context.
  /// - Parameter appendixLabels: what an appendix is named by, as the body beside the
  ///   list names it: a translated document's labels (#940), or English.
  public static func rows(
    of sections: [Section], filter: String, appendixLabels: Section.AppendixLabels = .english
  ) -> [Row] {
    let text = trimmed(filter)
    var rows: [Row] = []
    // The open path to the current section.
    var path: [PathStep] = []
    for section in sections {
      let depth = section.depth
      while let last = path.last, last.section.depth >= depth { path.removeLast() }
      // The heading's words, an appendix's qualifier among them (#428).
      let isMatch = matches(
        section, title: section.headingWords.plainText, text, appendixLabels: appendixLabels)
      if isMatch {
        for index in path.indices where !path[index].isListed {
          let ancestor = path[index]
          rows.append(
            Row(
              anchor: ancestor.section.anchor,
              title: ancestor.section.displayTitle(appendixLabels: appendixLabels),
              depth: ancestor.section.depth, isContext: true))
          path[index].isListed = true
        }
        rows.append(
          Row(
            anchor: section.anchor, title: section.displayTitle(appendixLabels: appendixLabels),
            depth: depth, isContext: false))
      }
      path.append(PathStep(section: section, isListed: isMatch))
    }
    return rows
  }

  /// A section on the path to the one `rows` is at, and whether it is listed yet.
  private struct PathStep {
    let section: Section
    var isListed: Bool
  }

  /// The matches of `filter` among `sections` by title, under `A` to `Z` and then
  /// `#`. Equal titles keep the document's order. An appendix is named by
  /// `appendixLabels`, as in `rows`.
  public static func groups(
    of sections: [Section], filter: String, appendixLabels: Section.AppendixLabels = .english
  ) -> [Group] {
    let text = trimmed(filter)
    var byLabel: [String: [(key: String, entry: Entry)]] = [:]
    for section in sections {
      let title = section.titleText
      guard matches(section, title: title, text, appendixLabels: appendixLabels) else { continue }
      // A title sorts from its first letter or digit; one with no words in it sorts
      // by the number it is shown by, under `#`, whether a section's or an appendix's.
      let words = title.drop { !$0.isLetter && !$0.isNumber }
      let key =
        words.isEmpty ? section.displayTitle(appendixLabels: appendixLabels) : String(words)
      let label = words.isEmpty ? "#" : groupLabel(key)
      byLabel[label, default: []].append(
        (key, entry(section, title: title, appendixLabels: appendixLabels)))
    }
    let letters = byLabel.keys.filter { $0 != "#" }.sorted()
    return (letters + ["#"]).compactMap { label in
      byLabel[label].map { Group(label: label, entries: sortedByKey($0)) }
    }
  }

  /// Whether `section`, whose title is `title`, matches `text`: words anywhere in
  /// its title, or the start of its heading as the list shows it (`4.2.`,
  /// `Appendix A`, or with `appendixLabels` from a translation `Anhang A`), as the
  /// English names it (`Appendix A`, which the RFC's own prose cites), or by its
  /// number alone (`A.`), ignoring case and diacritics, so `4.2` does not find 14.2.
  private static func matches(
    _ section: Section, title: String, _ text: String, appendixLabels: Section.AppendixLabels
  ) -> Bool {
    if text.isEmpty { return true }
    let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
    let anchored = options.union(.anchored)
    return title.range(of: text, options: options) != nil
      || section.displayTitle(appendixLabels: appendixLabels).range(of: text, options: anchored)
        != nil
      || section.displayTitle.range(of: text, options: anchored) != nil
      || section.number.map { "\($0)." }?.range(of: text, options: anchored) != nil
  }

  private static func trimmed(_ filter: String) -> String {
    filter.trimmingCharacters(in: .whitespaces)
  }

  private static func entry(
    _ section: Section, title: String, appendixLabels: Section.AppendixLabels
  ) -> Entry {
    if title.isEmpty {
      return Entry(
        anchor: section.anchor, title: section.displayTitle(appendixLabels: appendixLabels),
        caption: nil)
    }
    return Entry(
      anchor: section.anchor, title: title,
      caption: section.numberLabel(appendixLabels: appendixLabels))
  }

  /// `A` to `Z` for a key that starts with a Latin letter, diacritics folded, and `#`
  /// for anything else.
  private static func groupLabel(_ key: String) -> String {
    let first = key.prefix(1)
      .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
      .uppercased()
    return first.count == 1 && ("A"..."Z").contains(first) ? first : "#"
  }

  /// The entries in the order of their keys. Equal keys keep the order they were
  /// collected in, which is the document's.
  private static func sortedByKey(_ keyed: [(key: String, entry: Entry)]) -> [Entry] {
    keyed.enumerated().sorted { first, second in
      let order = first.element.key.compare(
        second.element.key, options: [.caseInsensitive, .diacriticInsensitive, .numeric])
      return order == .orderedSame ? first.offset < second.offset : order == .orderedAscending
    }.map(\.element.entry)
  }
}
