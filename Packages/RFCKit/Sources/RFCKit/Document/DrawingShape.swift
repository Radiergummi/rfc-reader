import Foundation

/// Whether verbatim text is a drawing, by its shape: what the legacy parser types a
/// drawing by (#361), and what the reader asks of artwork RFCXML left untyped.
public enum DrawingShape {
  /// A drawing is mostly lines, boxes and arrows: at least this share of the
  /// characters that are not white space are drawing characters. Measured, RFC 793's
  /// header diagram sits at 0.76 and its state diagram at 0.71, RFC 5234's core
  /// rules at 0.07 and RFC 8999's packet notation near 0.
  public static let drawingShare = 0.3

  /// A drawing, unless most of its lines are words: then it is a table, whose
  /// borders or underlines pass `drawingShare` but whose rows are data to be heard.
  ///
  /// A line is words when it has a letter and more than half of its characters
  /// that are not white space are letters and digits. The letter keeps a bit
  /// layout's numbered ruler out; "more than half" keeps out a box's middle line,
  /// `| Client | -------> | Server |`, which is exactly half. "Most" is strictly
  /// more than half of the lines that are not blank, because a bit layout
  /// alternates field rows and borders: RFC 793's header has 7 lines of words in
  /// 19, and its option layouts 2 in 4. So a bordered table needs more rows than
  /// borders to be read, which one with a header row and two data rows does not.
  public static func looksLikeDrawing(_ text: String) -> Bool {
    var characters = 0
    var drawing = 0
    var lines = 0
    var linesOfWords = 0
    for line in text.split(whereSeparator: \.isNewline) {
      var lineCharacters = 0
      var alphanumerics = 0
      var hasLetter = false
      for scalar in line.unicodeScalars where !scalar.properties.isWhitespace {
        lineCharacters += 1
        if isDrawing(scalar) {
          drawing += 1
        }
        if scalar.properties.isAlphabetic {
          hasLetter = true
          alphanumerics += 1
        } else if scalar.properties.numericType != nil {
          alphanumerics += 1
        }
      }
      guard lineCharacters > 0 else { continue }
      characters += lineCharacters
      lines += 1
      if hasLetter && 2 * alphanumerics > lineCharacters {
        linesOfWords += 1
      }
    }
    return characters > 0
      && Double(drawing) >= drawingShare * Double(characters)
      && 2 * linesOfWords <= lines
  }

  /// The ASCII an RFC draws with, and Unicode's box drawing and block elements.
  private static let asciiDrawing = Set("+-|/\\_=<>^*~".unicodeScalars)

  private static func isDrawing(_ scalar: Unicode.Scalar) -> Bool {
    asciiDrawing.contains(scalar) || (0x2500...0x259F).contains(scalar.value)
  }
}
