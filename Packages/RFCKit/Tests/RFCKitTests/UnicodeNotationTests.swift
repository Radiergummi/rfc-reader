import Foundation
import Testing

@testable import RFCKit

/// `<u>` spelled out (issue #63). Through the parser, RFC 8771 and RFC 9682 are
/// checked against the RFC Editor's own plain-text renderings of them. At the
/// guard, `UnicodeNotation.expand` is a pure function of one element's text and
/// attributes, so those tests hand it exactly that: the formats the prepped corpus
/// uses (`lit-name-num` 34 times, then `num-name`, `num-lit-name`, `num-name-lit`
/// and `num`), plus the template form and `ascii`, which the vocabulary defines and
/// nothing uses yet.
@Suite("Unicode notation (<u>)")
struct UnicodeNotationTests {
  // MARK: Through the parser

  private static func paragraphs(in name: String) throws -> [Paragraph] {
    let document = try RFCXMLParser.parse(try Fixtures.data(name))
    return document.allSections.flatMap(\.blocks).flatMap(paragraphs(in:))
  }

  private static func paragraphs(in block: Block) -> [Paragraph] {
    switch block {
    case .paragraph(let paragraph): [paragraph]
    case .list(let list): list.items.flatMap(\.blocks).flatMap(paragraphs(in:))
    default: []
    }
  }

  /// RFC 9682 uses the default format, on a character outside the Basic
  /// Multilingual Plane.
  @Test func theDefaultFormatThroughTheParser() throws {
    let paragraph = try #require(
      try Self.paragraphs(in: "rfc9682.xml").first {
        $0.plainText.contains("no need to escape the")
      })
    #expect(
      paragraph.plainText.contains(
        "no need to escape the \"🁳\" (DOMINO TILE VERTICAL-02-02, U+1F073) or \"⌘\" (PLACE OF INTEREST SIGN, U+2318); however"
      ))
    #expect(paragraph.inlines.contains(.code("🁳")), "the literal is set apart from the prose")
  }

  @Test func aNumberAloneReplacesTheCharacter() throws {
    let paragraph = try #require(
      try Self.paragraphs(in: "rfc8771.xml").first {
        $0.plainText.contains("one-character sequence")
      })
    #expect(paragraph.plainText.contains("the magical one-character sequence U+002E is believed"))
  }

  @Test func theFirstKeywordLeadsThroughTheParser() throws {
    let paragraph = try #require(
      try Self.paragraphs(in: "rfc8771.xml").first { $0.plainText.contains("be declared a Letter") }
    )
    #expect(
      paragraph.plainText.contains(
        "For that purpose, U+002D (\"-\", HYPHEN-MINUS) SHALL be declared"))
  }

  @Test func tableCellsAreSpelledOutToo() throws {
    let document = try RFCXMLParser.parse(try Fixtures.data("rfc8771.xml"))
    let tables = document.allSections.flatMap(\.blocks).compactMap { block -> Table? in
      if case .table(let table) = block { return table }
      return nil
    }
    let table = try #require(tables.first { $0.header.first?.first?.plainText == "Bit Seq." })
    #expect(
      table.rows.map { $0[1].plainText } == [
        "U+0063 (LATIN SMALL LETTER C)",
        "U+000C (FORM FEED (FF))",
        "U+006C (LATIN SMALL LETTER L)",
        "U+04A4 (CYRILLIC CAPITAL LIGATURE EN GHE)",
      ])
  }

  /// RFC 8771 leaves one `<u>` empty, because the form feed it means cannot be
  /// written in XML at all; the author typed its number beside it instead. The
  /// spaces either side of the empty element must not meet as two.
  @Test func anEmptyElementAddsNothing() throws {
    let paragraph = try #require(
      try Self.paragraphs(in: "rfc8771.xml").first {
        $0.plainText.contains("DISALLOWED characters")
      })
    #expect(
      paragraph.plainText
        == "There are two IDNA2008 DISALLOWED characters: U+000C (for good reason!) and U+04A4.")
  }

  // MARK: The expansion itself

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

  /// Quoted, as the literal is: both are a spelling of the character.
  @Test func asciiIsTheElementsOwnSpelling() {
    #expect(expand("ascii-num", ascii: "shin") == [.text("\"shin\" (U+05E9)")])
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

  /// A scalar with no name is still identified, by its code point. A control
  /// character's alias (`DELETE`) is not its name, and the RFC Editor's renderer
  /// does not use it either.
  @Test func aScalarWithNoNameIsNamedByItsCodePoint() {
    #expect(UnicodeNotation.name(Unicode.Scalar(UInt32(0xE000))!) == "U+E000")
    #expect(expand("name", "\u{7F}") == [.text("U+007F")])
  }

  @Test func anEmptyElementYieldsNothing() {
    #expect(expand(nil, "").isEmpty)
    #expect(expand("num-name", "").isEmpty)
  }
}
