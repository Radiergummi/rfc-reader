import Foundation
import Testing

@testable import RFCKit

/// Recognising ABNF by parsing it (#45): RFC 5234, the RFC 7405 `%s`/`%i` extension and
/// the `#` list of RFC 9110 and RFC 2616, as the 72-column text sets it.
@Suite("ABNF")
struct ABNFTests {
  private static func text(_ lines: String...) -> String {
    lines.joined(separator: "\n")
  }

  // MARK: Parsing

  @Test func `a grammar parses into its rules, with what each refers to`() throws {
    let rules = try #require(
      ABNF.parse(
        Self.text(
          "greeting    = salutation SP name [ SP title ] CRLF",
          "salutation  = %s\"Hello\" / %s\"Hi\"",
          "name        = 1*ALPHA *( \"-\" 1*ALPHA )")))
    #expect(rules.map(\.name) == ["greeting", "salutation", "name"])
    #expect(rules[0].references == ["salutation", "SP", "name", "title", "CRLF"])
    #expect(rules[1].references.isEmpty)
    #expect(rules[2].references == ["ALPHA"])
  }

  /// A rule continues on any line set deeper than the one it starts on, and a comment
  /// runs from `;` to the end of its line, even inside a continued rule.
  @Test func `continuation lines and comments belong to their rule`() throws {
    let rules = try #require(
      ABNF.parse(
        Self.text(
          "; the header of a record",
          "record-line = field-name \":\" OWS    ; the name first",
          "              field-value OWS",
          "",
          "field-name  = token")))
    #expect(rules.map(\.name) == ["record-line", "field-name"])
    #expect(rules[0].references == ["field-name", "OWS", "field-value"])
  }

  @Test(arguments: [
    "digit-range  = %x30-39",
    "line-end     = %d13.10",
    "flag-bits    = %b0101",
    "insensitive  = %i\"yes\"",
    "prose        = <any octet the sender chooses>",
    "item-list    = 1#item",
    "some-items   = #( item / other-item )",
    "bounded      = 2*4DIGIT",
    "exact        = 3HEXDIG",
    "choice       = \"a\" / \"b\" / ( \"c\" [ \"d\" ] )",
  ])
  func `each kind of element parses`(line: String) {
    #expect(ABNF.parse(line) != nil, "\(line)")
  }

  /// RFCXML keeps a block's indentation inside `<sourcecode>`: the least indented line
  /// is where rules start.
  @Test func `a grammar indented as a whole parses`() throws {
    let rules = try #require(
      ABNF.parse(Self.text("   first  = second / third", "            fourth", "   second = ALPHA"))
    )
    #expect(rules.map(\.name) == ["first", "second"])
  }

  /// A comment heading a grammar may sit further left than its rules.
  @Test func `a comment left of the rules does not set their column`() throws {
    let rules = try #require(
      ABNF.parse(Self.text("; the record grammar", "   record = 1*field", "   field  = ALPHA")))
    #expect(rules.map(\.name) == ["record", "field"])
  }

  @Test func `an incremental alternative adds to its rule`() throws {
    let rules = try #require(
      ABNF.parse(Self.text("command = \"open\"", "command =/ \"close\"")))
    #expect(rules.map(\.isIncremental) == [false, true])
  }

  @Test(arguments: [
    "x = y + 1;",
    "result = compute(a, b)",
    "value ::= first | second",
    "+--------+--------+",
    "Field    | Value",
    "a = \"unclosed",
    "   indented without a rule before it",
    "rule = ( open",
    "name = element\nThis line is prose at the rule's own column.",
  ])
  func `what is not ABNF does not parse`(text: String) {
    #expect(ABNF.parse(text) == nil, "\(text)")
  }

  // MARK: Recognising

  /// `count = max;` is valid ABNF, a rule with one element and a comment. Code and
  /// configuration look like that; a grammar has more than one rule, or syntax only a
  /// grammar has.
  @Test func `one plain assignment is not recognised as a grammar`() {
    #expect(!ABNF.recognizes("count = max;"))
    #expect(!ABNF.recognizes("key = value"))
    #expect(!ABNF.recognizes("title = <the title>"))
  }

  @Test func `one rule with syntax only ABNF has is recognised`() {
    #expect(ABNF.recognizes("token = 1*tchar"))
    #expect(ABNF.recognizes("sign = \"+\" / \"-\""))
    #expect(ABNF.recognizes("octet = %x00-FF"))
    #expect(ABNF.recognizes("maybe = [ thing ]"))
    #expect(ABNF.recognizes("list = 1#element"))
  }

  /// Test vectors are valid ABNF by the letter: `4c0ffee` reads as four of a rule
  /// named `c0ffee`, and `0x7` as none of `x7`. A count before a name of hex digits, or
  /// before `x`, is a hex number.
  @Test func `hex data is not a grammar`() {
    #expect(!ABNF.recognizes(Self.text("key    = 4c0ffee1234abcd5678", "nonce  = 9aa0b1c2d3e4f5")))
    #expect(!ABNF.recognizes("mask = 0x7"))
    #expect(ABNF.recognizes("four-digits = 4DIGIT"), "a count before a real name is a repetition")
  }

  /// Assignments in pseudocode or a configuration parse as plain rules: without syntax
  /// only a grammar has, the rules have to refer to one another.
  @Test func `plain rules that refer to nothing among them are not a grammar`() {
    #expect(!ABNF.recognizes(Self.text("lowest = infinity", "current = infinity")))
    #expect(!ABNF.recognizes(Self.text("e=<email-address>", "p=<phone-number>")))
  }

  @Test func `two plain rules are recognised`() {
    #expect(ABNF.recognizes(Self.text("start = first-part", "first-part = ALPHA")))
  }

  // MARK: Through parse

  /// RFC 5234 sets its own grammar and its core rules as ABNF: both come out as
  /// source code typed `abnf`, as RFCXML writes it.
  @Test func `RFC 5234's grammars are source code typed abnf`() throws {
    let document = LegacyTextParser.parse(try Fixtures.string("rfc5234.txt"))
    let grammars = document.blocks.compactMap { block -> Preformatted? in
      guard case .preformatted(let preformatted) = block, preformatted.type == "abnf" else {
        return nil
      }
      return preformatted
    }
    #expect(grammars.allSatisfy { $0.kind == .sourceCode })
    #expect(grammars.contains { $0.text.contains("rulelist") })
    #expect(grammars.contains { $0.text.contains("ALPHA") && $0.text.contains("%x41-5A") })
  }

  /// A diagram stays artwork.
  @Test func `RFC 793's diagrams stay artwork`() throws {
    let document = LegacyTextParser.parse(try Fixtures.string("rfc793.txt"))
    let typed = document.blocks.filter { block in
      if case .preformatted(let preformatted) = block { return preformatted.type == "abnf" }
      return false
    }
    #expect(typed.isEmpty)
  }
}
