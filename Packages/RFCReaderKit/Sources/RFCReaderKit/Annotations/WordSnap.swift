import Foundation

/// A selection made into what a highlight covers (#522): out to the words it starts
/// and ends in, so a highlight never begins or ends inside a word, and without the
/// white space at either end.
public enum WordSnap {
  public static func snapped(_ range: NSRange, in text: NSString) -> NSRange {
    var start = range.location
    var end = NSMaxRange(range)
    guard end > start, end <= text.length else { return range }
    while start < end, isSpace(text.character(at: start)) { start += 1 }
    while end > start, isSpace(text.character(at: end - 1)) { end -= 1 }
    guard end > start else { return NSRange(location: range.location, length: 0) }
    while start > 0, isWord(text.character(at: start - 1)), isWord(text.character(at: start)) {
      start -= 1
    }
    while end < text.length, isWord(text.character(at: end)), isWord(text.character(at: end - 1)) {
      end += 1
    }
    return NSRange(location: start, length: end - start)
  }

  private static func isSpace(_ unit: unichar) -> Bool {
    guard let scalar = Unicode.Scalar(unit) else { return false }
    return CharacterSet.whitespacesAndNewlines.contains(scalar)
      || scalar == "\u{FFFC}" || scalar == "\u{2060}"
  }

  /// A letter or a digit, or half a surrogate pair, which is part of one.
  private static func isWord(_ unit: unichar) -> Bool {
    guard let scalar = Unicode.Scalar(unit) else { return true }
    return scalar.properties.isAlphabetic || scalar.properties.numericType != nil
  }
}
