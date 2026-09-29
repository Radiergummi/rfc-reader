import Foundation
import Testing

@testable import RFCKit

/// A numbered list's counter, its punctuation and its start, read once from either
/// source and written back and rendered from the one value.
@Suite("List numbering")
struct ListNumberingTests {
  // MARK: RFCXML `type`

  @Test(arguments: [
    ("1", ListNumbering.Counter.decimal, "", "."),
    ("a", .lowerAlpha, "", "."),
    ("A", .upperAlpha, "", "."),
    ("i", .lowerRoman, "", "."),
    ("I", .upperRoman, "", "."),
    ("(%c)", .lowerAlpha, "(", ")"),
    ("%d)", .decimal, "", ")"),
    ("Step %C:", .upperAlpha, "Step ", ":"),
  ])
  func `an RFCXML type is read as a counter between its punctuation`(
    type: String, counter: ListNumbering.Counter, prefix: String, suffix: String
  ) {
    let numbering = ListNumbering(type: type, start: 1)
    #expect(numbering.counter == counter)
    #expect(numbering.prefix == prefix)
    #expect(numbering.suffix == suffix)
  }

  @Test func `no type is decimal with a full stop`() {
    #expect(ListNumbering(type: nil, start: 3) == ListNumbering(start: 3))
  }

  @Test func `a specifier with no counter here counts in decimal between the punctuation`() {
    #expect(
      ListNumbering(type: "[%o]", start: 1) == ListNumbering(prefix: "[", suffix: "]", start: 1))
  }

  @Test(arguments: ["1", "a", "A", "i", "I", "(%c)", "%d)", "Step %C:"])
  func `a type is written back as it was read`(type: String) {
    #expect(ListNumbering(type: type, start: 1).type == type)
  }

  // MARK: Markers

  @Test func `markers count from the start`() {
    #expect(ListNumbering(start: 5).marker(at: 2) == "7.")
    #expect(ListNumbering(type: "a", start: 1).marker(at: 0) == "a.")
    #expect(ListNumbering(type: "A", start: 1).marker(at: 25) == "Z.")
    #expect(ListNumbering(type: "i", start: 1).marker(at: 3) == "iv.")
    #expect(ListNumbering(type: "I", start: 1).marker(at: 8) == "IX.")
    #expect(ListNumbering(type: "(%c)", start: 1).marker(at: 1) == "(b)")
    #expect(ListNumbering(type: "%d)", start: 1).marker(at: 2) == "3)")
  }

  /// xml2rfc's `int2letter` writes `n - 1` in base 26 with `a` as the zero digit,
  /// so the letter after `z` is `ba`, not `aa`. The published RFCs are rendered by
  /// it, and so is a prepped document's `derivedCounter`.
  @Test func `letters past z continue as xml2rfc writes them`() {
    let letters = ListNumbering(type: "a", start: 1)
    #expect(letters.marker(at: 25) == "z.")
    #expect(letters.marker(at: 26) == "ba.")
    #expect(letters.marker(at: 27) == "bb.")
  }

  /// A letter or a numeral has no zero and no negatives, and Roman numerals stop at
  /// 3999: the number is shown instead, rather than a crash or nothing.
  @Test func `a value with no letter or numeral is shown as a number`() {
    #expect(ListNumbering(type: "a", start: 0).marker(at: 0) == "0.")
    #expect(ListNumbering(type: "(%c)", start: -2).marker(at: 0) == "(-2)")
    #expect(ListNumbering(type: "i", start: 4000).marker(at: 0) == "4000.")
  }

  // MARK: A legacy marker

  /// A plain-text list interrupted by prose, or set with a blank line between its
  /// items, arrives in pieces. A piece continues the list before it when its first
  /// marker is the next one that list would draw: `i.` after `h.` is the ninth
  /// letter, not the Roman one, and `1)` after `1)` is a new list.
  @Test func `a piece continues a list when its marker is the next one`() throws {
    let letters = ListNumbering(counter: .lowerAlpha, start: 7)
    let roman = try #require(ListNumbering(marker: "i."))
    #expect(roman.continues(letters, itemCount: 2))
    #expect(!roman.continues(letters, itemCount: 1))

    let decimal = ListNumbering(start: 1)
    #expect(try #require(ListNumbering(marker: "3.")).continues(decimal, itemCount: 2))
    #expect(!(try #require(ListNumbering(marker: "1.")).continues(decimal, itemCount: 2)))
    #expect(!(try #require(ListNumbering(marker: "3)")).continues(decimal, itemCount: 2)))
  }

  @Test(arguments: [
    ("1.", ListNumbering(start: 1)),
    ("3.", ListNumbering(start: 3)),
    ("2)", ListNumbering(suffix: ")", start: 2)),
    ("(a)", ListNumbering(counter: .lowerAlpha, prefix: "(", suffix: ")", start: 1)),
    ("c.", ListNumbering(counter: .lowerAlpha, start: 3)),
    ("i.", ListNumbering(counter: .lowerRoman, start: 1)),
    ("(iv)", ListNumbering(counter: .lowerRoman, prefix: "(", suffix: ")", start: 4)),
  ])
  func `a legacy marker is read as the numbering it starts`(
    marker: String, numbering: ListNumbering
  ) {
    #expect(ListNumbering(marker: marker) == numbering)
  }

  // MARK: Through the parsers

  private static func lists(in document: RFCDocument) -> [ListBlock] {
    document.blocks.compactMap(\.list)
  }

  private static func numbering(ofListStarting text: String, in document: RFCDocument)
    -> ListNumbering?
  {
    let list = lists(in: document).first { list in
      guard case .paragraph(let paragraph)? = list.items.first?.blocks.first else { return false }
      return paragraph.plainText.hasPrefix(text)
    }
    guard case .numbered(let numbering)? = list?.style else { return nil }
    return numbering
  }

  /// RFC 793 letters its list `(a)`, `(b)`: read as letters in parentheses, not as
  /// numbers.
  @Test func `a legacy lettered list keeps its letters`() throws {
    let document = LegacyTextParser.parse(try Fixtures.data("rfc793.txt"))
    let numbering = try #require(
      Self.numbering(ofListStarting: "Determining that an acknowledgment", in: document))
    #expect(numbering == ListNumbering(counter: .lowerAlpha, prefix: "(", suffix: ")", start: 1))
  }

  /// RFC 1927 numbers with a closing parenthesis, `1)`, which is not `1.`.
  @Test func `a legacy list keeps its punctuation`() throws {
    let document = LegacyTextParser.parse(try Fixtures.data("rfc1927.txt"))
    let numbering = try #require(Self.numbering(ofListStarting: "New MIME Types", in: document))
    #expect(numbering == ListNumbering(suffix: ")", start: 1))
  }

  /// RFC 1927 starts every one of its lists at `1)`, a blank line apart. Merged by
  /// style alone they were one list of 33 items, drawn `1)` to `33)`.
  @Test func `lists that each start at one stay apart`() throws {
    let document = LegacyTextParser.parse(try Fixtures.data("rfc1927.txt"))
    let longest = Self.lists(in: document).map(\.items.count).max() ?? 0
    #expect(longest <= 4)
  }

  /// RFC 8771 letters a nested list, `<ol type="a" start="1">`.
  @Test func `the XML parser reads the type and the start`() throws {
    let document = try RFCXMLParser.parse(try Fixtures.data("rfc8771.xml"))
    let numberings = Self.lists(in: document).compactMap { list -> ListNumbering? in
      if case .numbered(let numbering) = list.style { return numbering }
      return nil
    }
    #expect(numberings.contains(ListNumbering(counter: .lowerAlpha, start: 1)))
  }

  /// Written back as RFCXML and read again, a numbering is the same value.
  @Test func `a numbering survives a round trip`() throws {
    let numbering = ListNumbering(counter: .lowerRoman, prefix: "(", suffix: ")", start: 4)
    let document = RFCDocument(
      header: DocumentHeader(title: "Lists"),
      sections: [
        Section(
          anchor: "section-1", number: "1", title: "Lists",
          blocks: [
            .list(ListBlock(style: .numbered(numbering), items: [ListItem(text: "fourth")]))
          ])
      ],
      source: .text)
    let reparsed = try RFCXMLParser.parse(Data(RFCXMLSerializer().serialize(document).utf8))
    #expect(Self.lists(in: reparsed).first?.style == .numbered(numbering))
  }
}
