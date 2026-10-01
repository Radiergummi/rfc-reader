import Foundation

extension Span<UInt8> {
  /// Whether `literal`'s bytes start at `index`: a substring test that does not start
  /// the regex engine or break graphemes, for literals the caller knows are ASCII.
  func holds(_ literal: StaticString, at index: Int) -> Bool {
    let length = literal.utf8CodeUnitCount
    guard index >= 0, index + length <= count else { return false }
    // The one unsafe read in RFCKit (#147): `utf8Start` points at the literal's
    // `utf8CodeUnitCount` bytes, which `offset` stays below, and a `StaticString` is
    // never freed. The safe ways to its bytes copy them, on a scan's hot path.
    for offset in 0..<length where unsafe self[index + offset] != literal.utf8Start[offset] {
      return false
    }
    return true
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

  public func trimmingTrailingWhitespace() -> String {
    var result = self
    while let last = result.last, last.isWhitespace { result.removeLast() }
    return result
  }

  /// A table-of-contents leader, `Title ....... 7`, which `trimmingTrailingDots` cuts off
  /// every title `heading(from:)` reads, a contents entry's included: a static pattern,
  /// as a literal in the function was a new `Regex` per line (#146).
  private static let contentsLeaderPattern = Pattern(#/\s*\.{3,}\s*\d*$/#)

  func trimmingTrailingDots() -> String {
    var result = trimmingTrailingWhitespace()
    // Table-of-contents style "Title ....... 7" leaders.
    if let match = result.firstMatch(of: Self.contentsLeaderPattern) {
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
