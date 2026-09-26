import Testing

@testable import RFCKit

/// `<u>` spelled out, tested at the guard: `UnicodeNotation.expand` is a pure
/// function of one element's text and attributes, so these hand it those rather
/// than a document. The formats are the ones the prepped corpus uses (issue #63):
/// `lit-name-num` 34 times, then `num-name`, `num-lit-name`, `num-name-lit` and
/// `num`, plus the template form the vocabulary defines and nothing uses yet.
@Suite("Unicode notation (<u>)")
struct UnicodeNotationTests {
  private let shin = "\u{05E9}"

  private func expand(_ format: String?, _ text: String? = nil, ascii: String? = nil) -> [Inline] {
    UnicodeNotation.expand(text ?? shin, format: format, ascii: ascii)
  }

  /// RFC 9290's rendering, and the vocabulary's default.
  @Test func theDefaultIsLiteralThenNameAndNumber() {
    let expected: [Inline] = [.text("\""), .code(shin), .text("\" (HEBREW LETTER SHIN, U+05E9)")]
    #expect(expand(nil) == expected)
    #expect(expand("") == expected)
    #expect(expand("lit-name-num") == expected)
  }

  @Test func theNumberAlone() {
    #expect(expand("num") == [.text("U+05E9")])
  }

  @Test func theFirstKeywordStandsAloneAndTheRestAreBracketed() {
    #expect(expand("num-name") == [.text("U+05E9 (HEBREW LETTER SHIN)")])
    let second = Inline.text("U+05E9 (\"")
    #expect(expand("num-lit-name") == [second, .code(shin), .text("\", HEBREW LETTER SHIN)")])
    let last = Inline.text("U+05E9 (HEBREW LETTER SHIN, \"")
    #expect(expand("num-name-lit") == [last, .code(shin), .text("\")")])
  }

  /// The literal is code wherever it lands, so no linker or reflow can touch it.
  @Test func theLiteralIsCodeAndCharIsItUnquoted() {
    #expect(expand("char-num") == [.code(shin), .text(" (U+05E9)")])
  }

  @Test func asciiIsTheElementsOwnSpelling() {
    #expect(expand("ascii-num", ascii: "shin") == [.text("shin (U+05E9)")])
  }

  /// Nothing to spell it with, so it is left out rather than printed empty.
  @Test func asciiWithoutTheAttributeIsSkipped() {
    #expect(expand("num-ascii") == [.text("U+05E9")])
  }

  @Test func aStringIsSpelledScalarByScalar() {
    let text = "\u{05E9}\u{05DC}"
    #expect(
      expand("num-name", text)
        == [.text("U+05E9 U+05DC (HEBREW LETTER SHIN, HEBREW LETTER LAMED)")])
  }

  /// Four digits is a minimum, not a width.
  @Test func aCodePointBeyondTheBasicPlaneKeepsAllItsDigits() {
    #expect(expand("num", "\u{1F600}") == [.text("U+1F600")])
    #expect(expand("num", "\u{E9}") == [.text("U+00E9")])
  }

  @Test func aTemplateReplacesItsPlaceholdersInPlace() {
    #expect(
      expand("{lit} character ({num})")
        == [.text("\""), .code(shin), .text("\" character (U+05E9)")])
  }

  @Test func aTemplateKeepsAPlaceholderItDoesNotKnow() {
    #expect(expand("{num} {size}") == [.text("U+05E9 {size}")])
    #expect(expand("{num} {unclosed") == [.text("U+05E9 {unclosed")])
  }

  @Test func anUnknownKeywordIsSkipped() {
    #expect(expand("num-size-name") == [.text("U+05E9 (HEBREW LETTER SHIN)")])
  }

  /// A format that names nothing the vocabulary defines still spells the
  /// character out, rather than dropping it.
  @Test func aFormatThatLeavesNothingFallsBackToTheDefault() {
    #expect(expand("size") == expand(nil))
  }

  /// A scalar with no name is still identified, by its code point.
  @Test func aScalarWithNoNameIsNamedByItsCodePoint() {
    #expect(UnicodeNotation.name(Unicode.Scalar(UInt32(0xE000))!) == "U+E000")
  }
}
