import Foundation

extension UnsafeBufferPointer<UInt8> {
  /// Whether `literal`'s bytes start at `index`: a substring test that does not start
  /// the regex engine or break graphemes, for literals the caller knows are ASCII.
  func holds(_ literal: StaticString, at index: Int) -> Bool {
    let count = literal.utf8CodeUnitCount
    guard index >= 0, index + count <= self.count else { return false }
    return (0..<count).allSatisfy { self[index + $0] == literal.utf8Start[$0] }
  }
}

extension String {
  var isBlank: Bool { allSatisfy(\.isWhitespace) }

  /// Whitespace rather than a space: `depaginate` expands tabs before any line reaches
  /// the heuristics (RFC 1142's contents listing is tab-indented, and every entry
  /// otherwise matched the numbered-heading pattern), and this stays general so a
  /// caller that has not been through it cannot read a tab as column zero.
  var startsAtColumnZero: Bool { first?.isWhitespace == false }

  var leadingSpaceCount: Int {
    var count = 0
    for character in self {
      if character == " " { count += 1 } else { break }
    }
    return count
  }

  /// Tabs replaced by spaces to the next multiple-of-eight column, which is what the
  /// line printers and terminals these documents were typed for did with them.
  func expandingTabs() -> String {
    // Over UTF-8: this runs on every line of every document, and `contains` over
    // Characters is an order of magnitude dearer for a test that almost always fails.
    guard utf8.contains(9) else { return self }
    var result = ""
    result.reserveCapacity(count + 8)
    var column = 0
    for character in self {
      if character == "\t" {
        let width = 8 - column % 8
        result.append(contentsOf: repeatElement(" ", count: width))
        column += width
      } else {
        result.append(character)
        column += 1
      }
    }
    return result
  }

  func trimmingTrailingWhitespace() -> String {
    var result = self
    while let last = result.last, last.isWhitespace { result.removeLast() }
    return result
  }

  func trimmingTrailingDots() -> String {
    var result = trimmingTrailingWhitespace()
    // Table-of-contents style "Title ....... 7" leaders.
    if let match = result.firstMatch(of: #/\s*\.{3,}\s*\d*$/#) {
      result.removeSubrange(match.range)
    }
    return result
  }

  func trimmingTrailingPunctuation() -> String {
    var result = self
    while let last = result.last, ".,;:)]>\"'".contains(last) { result.removeLast() }
    return result
  }

  func slugified() -> String {
    var result = ""
    var lastWasDash = false
    for scalar in lowercased().unicodeScalars {
      if scalar.properties.isAlphabetic || (scalar.value >= 48 && scalar.value <= 57) {
        result.unicodeScalars.append(scalar)
        lastWasDash = false
      } else if !lastWasDash, !result.isEmpty {
        result.append("-")
        lastWasDash = true
      }
    }
    if result.hasSuffix("-") { result.removeLast() }
    return result
  }

  /// Collapses any run of whitespace (including newlines) to a single space and trims the ends.
  func collapsingWhitespace() -> String {
    var result = ""
    result.reserveCapacity(count)
    var previousWasSpace = true
    for scalar in unicodeScalars {
      // XML whitespace is #x20, #x9, #xD and #xA only. U+00A0 and friends are
      // content: collapsing them would undo non-breaking reference labels.
      if scalar == " " || scalar == "\t" || scalar == "\r" || scalar == "\n" {
        if !previousWasSpace { result.append(" ") }
        previousWasSpace = true
      } else {
        result.unicodeScalars.append(scalar)
        previousWasSpace = false
      }
    }
    if result.hasSuffix(" ") { result.removeLast() }
    return result
  }
}
