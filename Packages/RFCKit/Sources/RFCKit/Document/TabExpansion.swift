import Foundation

extension String {
  /// Tabs replaced by spaces to the next multiple-of-eight column: what the line
  /// printers and terminals the legacy documents were typed for did with them, and
  /// what the RFC Editor's text rendering still does with a tab in RFCXML artwork.
  ///
  /// Each line counts from its own column 0, so a whole block can be expanded at
  /// once. `LegacyTextParser` expands before any heuristic counts an indent (#40),
  /// and the reader before an RFCXML figure is drawn and scaled (#31).
  public func expandingTabs() -> String {
    // Over UTF-8: this runs on every line of every document, and `contains` over
    // Characters is an order of magnitude dearer for a test that almost always fails.
    guard utf8.contains(9) else { return self }
    var result = ""
    result.reserveCapacity(utf8.count + 8)
    var column = 0
    for character in self {
      if character == "\t" {
        let width = 8 - column % 8
        result.append(contentsOf: repeatElement(" ", count: width))
        column += width
      } else if character.isNewline {
        // `isNewline`, not `== "\n"`: a CRLF pair is one Character, and not "\n".
        result.append(character)
        column = 0
      } else {
        result.append(character)
        column += 1
      }
    }
    return result
  }
}
