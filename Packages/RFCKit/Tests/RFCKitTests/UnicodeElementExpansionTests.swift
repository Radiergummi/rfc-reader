import Foundation
import Testing

@testable import RFCKit

/// `<u>` marks non-ASCII text a protocol depends on, and its `format` says how
/// to spell it out. The expected strings are the RFC Editor's own plain-text
/// renderings of the same documents.
@Suite("RFCXML <u> expansion")
struct UnicodeElementExpansionTests {
  static func paragraphs(in name: String) throws -> [Paragraph] {
    let document = try RFCXMLParser.parse(try Fixtures.data(name))
    return document.allSections.flatMap(\.blocks).flatMap(Self.paragraphs(in:))
  }

  private static func paragraphs(in block: Block) -> [Paragraph] {
    switch block {
    case .paragraph(let paragraph):
      return [paragraph]
    case .list(let list):
      return list.items.flatMap(\.blocks).flatMap(paragraphs(in:))
    default:
      return []
    }
  }

  // MARK: Through the parser

  /// RFC 9682 uses the default format, `lit-name-num`, on a character outside
  /// the Basic Multilingual Plane.
  @Test func theDefaultFormatIsLiteralNameAndNumber() throws {
    let paragraphs = try Self.paragraphs(in: "rfc9682.xml")
    let paragraph = try #require(
      paragraphs.first { $0.plainText.contains("no need to escape the") })
    #expect(
      paragraph.plainText.contains(
        "no need to escape the \"🁳\" (DOMINO TILE VERTICAL-02-02, U+1F073) or \"⌘\" (PLACE OF INTEREST SIGN, U+2318); however"
      ))
    #expect(
      paragraph.inlines.contains(.code("🁳")), "the literal is set apart from the prose around it")
  }

  @Test func aNumberAloneReplacesTheCharacter() throws {
    let paragraphs = try Self.paragraphs(in: "rfc8771.xml")
    let paragraph = try #require(
      paragraphs.first { $0.plainText.contains("one-character sequence") })
    #expect(paragraph.plainText.contains("the magical one-character sequence U+002E is believed"))
  }

  @Test func theFirstKeywordLeadsAndTheRestAreParenthesised() throws {
    let paragraphs = try Self.paragraphs(in: "rfc8771.xml")
    let paragraph = try #require(paragraphs.first { $0.plainText.contains("be declared a Letter") })
    #expect(
      paragraph.plainText.contains(
        "For that purpose, U+002D (\"-\", HYPHEN-MINUS) SHALL be declared"))
  }

  @Test func tableCellsAreExpandedToo() throws {
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
  /// written in XML at all; the author typed its number beside it instead.
  @Test func anEmptyElementAddsNothing() throws {
    let paragraphs = try Self.paragraphs(in: "rfc8771.xml")
    let paragraph = try #require(
      paragraphs.first { $0.plainText.contains("DISALLOWED characters") })
    #expect(
      paragraph.plainText
        == "There are two IDNA2008 DISALLOWED characters: U+000C (for good reason!) and U+04A4.")
  }

  // MARK: The expansion itself

  @Test func aStringIsSpelledOutScalarByScalar() {
    let inlines = UnicodeElementExpansion.inlines(for: "λμ", format: "num-name", ascii: nil)
    #expect(inlines == [.text("U+03BB U+03BC (GREEK SMALL LETTER LAMDA, GREEK SMALL LETTER MU)")])
  }

  @Test func charIsTheLiteralWithoutQuotes() {
    let inlines = UnicodeElementExpansion.inlines(for: "ü", format: "char-num", ascii: nil)
    #expect(inlines == [.code("ü"), .text(" (U+00FC)")])
  }

  @Test func asciiIsTheElementsOwnTransliteration() {
    let inlines = UnicodeElementExpansion.inlines(for: "ü", format: "ascii-num", ascii: "ue")
    #expect(inlines == [.text("\"ue\" (U+00FC)")])
  }

  @Test func aMissingFormatIsTheDefault() {
    let inlines = UnicodeElementExpansion.inlines(for: "ש", format: nil, ascii: nil)
    #expect(inlines == [.text("\""), .code("ש"), .text("\" (HEBREW LETTER SHIN, U+05E9)")])
  }

  @Test func aTemplateIsFilledInPlace() {
    let inlines = UnicodeElementExpansion.inlines(
      for: "ש", format: "{lit} character ({num})", ascii: nil)
    #expect(inlines == [.text("\""), .code("ש"), .text("\" character (U+05E9)")])
  }

  /// A control character has no name of its own; the number stands in, as it
  /// does in the RFC Editor's renderer.
  @Test func aScalarWithoutANameIsNamedByItsNumber() {
    let inlines = UnicodeElementExpansion.inlines(for: "\u{7F}", format: "name", ascii: nil)
    #expect(inlines == [.text("U+007F")])
  }
}
