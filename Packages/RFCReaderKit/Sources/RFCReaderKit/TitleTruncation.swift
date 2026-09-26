import Foundation

extension String {
  /// The string shortened to `limit` characters, ending at a word boundary and an
  /// ellipsis.
  ///
  /// For the window subtitle. AppKit truncates a title that does not fit its window,
  /// but a tab is far narrower than the window it belongs to and clips instead, and
  /// RFC titles run long — "Locator/ID Separation Protocol (LISP) Geo-Coordinates"
  /// is mid-length by the standards of the series.
  ///
  /// Cutting at a word boundary rather than mid-word: the first few words are what
  /// distinguishes one title from another, and "Locator/ID Separation Protocol…"
  /// reads as a title where "Locator/ID Separation Proto…" reads as a bug.
  /// A string already within the limit is returned untouched, so short titles never
  /// gain an ellipsis they did not need.
  public func truncated(to limit: Int) -> String {
    guard limit > 0 else { return "" }
    guard count > limit else { return self }
    let clipped = prefix(limit)
    // A cut that lands exactly on a word's end needs no backing up: the character
    // after it is the space. Backing up regardless would throw away a whole word
    // that fitted.
    let head: Substring
    if self[index(startIndex, offsetBy: limit)] == " " {
      head = clipped
    } else if let boundary = clipped.lastIndex(of: " ") {
      head = clipped[clipped.startIndex..<boundary]
    } else {
      // A first word longer than the limit has no boundary to find.
      head = clipped
    }
    let trimmed = head.trimmingCharacters(in: .whitespacesAndNewlines)
    return (trimmed.isEmpty ? String(clipped) : trimmed) + "…"
  }
}
