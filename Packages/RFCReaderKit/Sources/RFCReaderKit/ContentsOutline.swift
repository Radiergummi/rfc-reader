import Foundation
import RFCKit

/// What the Contents tab shows: a document's sections in its own order or A–Z,
/// narrowed by words in a title or the start of a number.
///
/// What is listed is decided here, under test; `TableOfContentsView` only draws it.
public enum ContentsOutline {
  /// How the tab orders the sections. Remembered app-wide by its raw value.
  public enum Order: String, CaseIterable, Sendable {
    case document
    case alphabetical
  }

  /// One section, as the tab lists it.
  public struct Row: Identifiable, Equatable, Sendable {
    public let anchor: String
    /// `4.2. Caching` in document order; the title alone in A–Z, where the number
    /// is the caption.
    public let title: String
    /// The number, or `Appendix A`, set beside an A–Z title; nil in document order.
    public let caption: String?
    /// How far the row is indented: the section's depth in document order, 1 in A–Z.
    public let depth: Int
    /// An ancestor shown only so a match keeps its place in the hierarchy.
    public let isContext: Bool

    public var id: String { anchor }
  }

  /// Rows under a letter in A–Z; the single, unlabeled group of document order.
  public struct Group: Identifiable, Equatable, Sendable {
    /// `A` to `Z`, or `#` for every title that does not start with a Latin letter;
    /// nil in document order.
    public let label: String?
    public let rows: [Row]

    public var id: String { label ?? "" }
  }

  /// What the tab lists of `sections`, which are flat and in document order, for
  /// `filter` and `order`. No group at all when nothing matches.
  public static func groups(of sections: [Section], filter: String, order: Order) -> [Group] {
    let text = filter.trimmingCharacters(in: .whitespaces)
    switch order {
    case .document:
      let rows = inDocumentOrder(sections, matching: text)
      return rows.isEmpty ? [] : [Group(label: nil, rows: rows)]
    case .alphabetical:
      return alphabetically(sections, matching: text)
    }
  }

  /// Whether `section` matches `text`: words anywhere in its title, ignoring case
  /// and diacritics, or the start of its number, so `4.2` does not find 14.2.
  static func matches(_ section: Section, _ text: String) -> Bool {
    if text.isEmpty { return true }
    let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
    if section.titleText.range(of: text, options: options) != nil { return true }
    guard let number = section.number else { return false }
    return number.range(of: text, options: options.union(.anchored)) != nil
  }

  /// Each match, after those of its ancestors not already listed, which are context.
  private static func inDocumentOrder(_ sections: [Section], matching text: String) -> [Row] {
    var rows: [Row] = []
    // The open path to the current section: each ancestor, and whether it is listed.
    var path: [(section: Section, isListed: Bool)] = []
    for section in sections {
      while let last = path.last, last.section.depth >= section.depth { path.removeLast() }
      let isMatch = matches(section, text)
      if isMatch {
        for index in path.indices where !path[index].isListed {
          rows.append(documentRow(path[index].section, isContext: true))
          path[index].isListed = true
        }
        rows.append(documentRow(section, isContext: false))
      }
      path.append((section, isMatch))
    }
    return rows
  }

  private static func documentRow(_ section: Section, isContext: Bool) -> Row {
    Row(
      anchor: section.anchor, title: section.displayTitle, caption: nil,
      depth: section.depth, isContext: isContext)
  }

  /// Filled in by Task 3.
  private static func alphabetically(_ sections: [Section], matching text: String) -> [Group] {
    []
  }
}
