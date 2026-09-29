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

  /// The query `text` asks for.
  public static func query(for text: String) -> String {
    text.trimmingCharacters(in: .whitespaces)
  }

  /// How long to wait before applying `text` over the query `applied`: nil when it
  /// asks for the query already applied, zero when it clears the search.
  public static func delay(applying text: String, over applied: String) -> Duration? {
    let query = query(for: text)
    guard query != applied else { return nil }
    return query.isEmpty ? .zero : pause
  }
}
