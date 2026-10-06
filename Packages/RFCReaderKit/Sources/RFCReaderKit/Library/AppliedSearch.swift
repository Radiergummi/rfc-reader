import Foundation

/// When the list follows what is typed into search (#124).
///
/// Every change of result set costs SwiftUI's `List` 40–50 ms of diffing on the main
/// thread in Release, however many rows it is handed, so a list that followed every
/// keystroke froze the window once a letter. The list follows the query applied
/// instead, which catches up with the field after a pause in typing: a word typed at
/// speed changes the list once. Clearing the search applies at once, because there
/// is nothing to wait for and the full list is what the reader asked to go back to.
public enum AppliedSearch {
  /// Long enough that a word typed at speed makes one update, short enough that the
  /// list follows while the reader looks at it.
  public static let pause = Duration.milliseconds(150)

  /// How the query applied catches up with what is typed.
  public enum Step: Equatable, Sendable {
    /// Apply `query` before returning: the search is cleared, so there is nothing to
    /// search for.
    case apply(query: String)
    /// Search for `query` after `delay`: the list follows once its rows are made.
    case search(query: String, after: Duration)
  }

  /// How long to wait before searching for `query`, a normalized one: a pause in
  /// typing, or nothing when the search is cleared.
  public static func pause(before query: String) -> Duration {
    query.isEmpty ? .zero : pause
  }

  /// The query `text` asks for, normalized as every list reads one (`normalizedQuery`).
  public static func query(for text: String) -> String {
    text.normalizedQuery
  }

  /// How to apply `text` over the query `applied`: nil when it asks for the query
  /// already applied. A new query waits for a pause in typing unless `pausing` is
  /// false, as for Return in the field.
  public static func step(applying text: String, over applied: String, pausing: Bool) -> Step? {
    let query = query(for: text)
    guard query != applied else { return nil }
    guard !query.isEmpty else { return .apply(query: query) }
    return .search(query: query, after: pausing ? pause : .zero)
  }
}
