import Foundation
import Testing

@testable import RFCKit

/// Recognizing ABNF by parsing it (#45): RFC 5234, the RFC 7405 `%s`/`%i` extension and
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

  /// Rule names are case-insensitive: a name mentioned in two spellings is one reference,
  /// kept as first spelled.
  @Test func `a reference is listed once whatever its case`() throws {
    let rules = try #require(ABNF.parse("mixed = LETTER / letter / Letter"))
    #expect(rules[0].references == ["LETTER"])
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

  /// The parser recurses once per group, and `recognizes` runs on every candidate
  /// block of the legacy corpus, so a group nested deeper than any grammar's is not
  /// ABNF, rather than a stack overflow (#757).
  @Test func `groups nested past the cap are not ABNF`() {
    let depth = ABNF.maximumNesting + 1
    let text =
      "rule = " + String(repeating: "(", count: depth) + "element"
      + String(repeating: ")", count: depth)
    #expect(ABNF.parse(text) == nil)
    #expect(!ABNF.recognizes(text))
  }

  @Test func `groups nested up to the cap parse`() {
    let depth = ABNF.maximumNesting
    let text =
      "rule = " + String(repeating: "[", count: depth) + "element"
      + String(repeating: "]", count: depth)
    #expect(ABNF.parse(text) != nil)
  }

  /// A grammar defines each rule once and adds to it only with `=/`. Pseudocode and
  /// listings of settings assign one name twice, which ABNF does not, so such a
  /// block is not recognized as a grammar. It still parses: a block its author typed
  /// `abnf` gets its links whatever its mistakes (#185).
  @Test func `a rule defined twice parses but is not recognized`() {
    let text = Self.text("limit = first-bound", "limit = second-bound")
    #expect(ABNF.parse(text) != nil)
    #expect(!ABNF.recognizes(text))
  }

  /// Rule names are case-insensitive, so two spellings of one name are one rule.
  @Test func `a rule defined twice in two spellings is not recognized`() {
    #expect(!ABNF.recognizes(Self.text("Limit = first-bound", "LIMIT = second-bound")))
  }

  /// A listing of settings quotes its values and a message layout marks what is
  /// optional; neither makes a repeated definition a grammar's.
  @Test(arguments: [
    ["Region  = \"North\"", "Unit    = \"Records\"", "Unit    = \"Archive\""],
    ["kind=OPEN   [id] name arguments", "kind=CLOSE  id   outcome results"],
    ["limit = first-bound / other-bound", "limit = second-bound"],
  ])
  func `a rule defined twice with no repetition or numeric value is not recognized`(
    lines: [String]
  ) {
    #expect(!ABNF.recognizes(lines.joined(separator: "\n")), "\(lines)")
  }

  /// Grammars in the legacy series define a name twice where `=/` or another name was
  /// meant. A repetition or a numeric value says the block is a grammar all the same.
  @Test(arguments: [
    ["stamp = \"at\" \"=\" day-part [ day-part ]", "day-part = 8DIGIT", "day-part = 6DIGIT"],
    ["entry = LF 1*SP entry-id", "entry-id = 1*3DIGIT", "entry = name SP entry-id"],
    ["marker = open-marker / close-marker", "marker = %x00-0F"],
  ])
  func `a rule defined twice beside a repetition or a numeric value is recognized`(
    lines: [String]
  ) {
    #expect(ABNF.recognizes(lines.joined(separator: "\n")), "\(lines)")
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

  // MARK: Recognizing

  /// `count = max;` is valid ABNF, a rule with one element and a comment. Code and
  /// configuration look like that; a grammar has more than one rule, or syntax only a
  /// grammar has.
  @Test func `one plain assignment is not recognized as a grammar`() {
    #expect(!ABNF.recognizes("count = max;"))
    #expect(!ABNF.recognizes("key = value"))
    #expect(!ABNF.recognizes("title = <the title>"))
  }

  @Test func `one rule with syntax only ABNF has is recognized`() {
    #expect(ABNF.recognizes("token = 1*tchar"))
    #expect(ABNF.recognizes("sign = \"+\" / \"-\""))
    #expect(ABNF.recognizes("octet = %x00-FF"))
    #expect(ABNF.recognizes("maybe = [ thing ]"))
    #expect(ABNF.recognizes("list = 1#element"))
  }

  /// Test vectors are valid ABNF by the letter: `4c0ffee` reads as four of a rule
  /// named `c0ffee`, and `0x7` as none of `x7`. A count before a name of hex digits, or
  /// before `x`, is a hex number.
  /// Hex data parses, as a count and a name, and is refused by recognizing.
  @Test func `hex data parses but is not a grammar`() {
    #expect(ABNF.parse("mask = 0x7") != nil)
  }

  @Test func `hex data is not a grammar`() {
    #expect(!ABNF.recognizes(Self.text("key    = 4c0ffee1234abcd5678", "nonce  = 9aa0b1c2d3e4f5")))
    #expect(!ABNF.recognizes("mask = 0x7"))
    #expect(ABNF.recognizes("four-digits = 4DIGIT"), "a count before a real name is a repetition")
  }

  /// A rule name runs on past a hyphen: a first part made only of hex letters does not
  /// make a counted name a hex number.
  @Test func `a counted name with a hyphen after hex letters is a repetition`() {
    #expect(ABNF.recognizes("quad = 4bead-part"))
  }

  /// Hex joined by hyphens is one number too: `7e0c-11ab` is not seven of a rule named
  /// `e0c-11ab`. A part that is not hex makes it a name again.
  @Test func `hex joined by hyphens is not a grammar`() {
    #expect(!ABNF.recognizes("serial = 3c0ffee0-1b2c-4d5e-8f9a-0b1c2d3e4f5a"))
    #expect(!ABNF.recognizes("tag = 7e0c-11ab"))
  }

  /// Only `x` followed by hex is a hex number: a count before a name that merely starts
  /// with `x` is a repetition.
  @Test func `a counted name starting with x is a repetition`() {
    #expect(ABNF.recognizes("pair = 2xname"))
    #expect(ABNF.recognizes("quad = 4x-part"))
    #expect(!ABNF.recognizes("mask = 0x7f"))
  }

  /// A rule that refers only to itself refers to no other rule: `total = total` beside
  /// another plain assignment is pseudocode.
  @Test func `a rule referring only to itself does not make plain rules a grammar`() {
    #expect(!ABNF.recognizes(Self.text("total = total", "next = none")))
  }

  /// Assignments in pseudocode or a configuration parse as plain rules: without syntax
  /// only a grammar has, the rules have to refer to one another.
  @Test func `plain rules that refer to nothing among them are not a grammar`() {
    #expect(!ABNF.recognizes(Self.text("smallest = unbounded", "latest = unbounded")))
    #expect(!ABNF.recognizes(Self.text("k=<first-setting>", "m=<second-setting>")))
  }

  @Test func `two plain rules are recognized`() {
    #expect(ABNF.recognizes(Self.text("start = first-part", "first-part = ALPHA")))
  }

  // MARK: Where the names are (#185)

  /// The ranges are UTF-16, into the text as given, indentation, continuation lines
  /// and comments included: what the reader marks as a definition and its links.
  private static func substring(_ text: String, _ range: NSRange) -> String {
    (text as NSString).substring(with: range)
  }

  @Test func `a rule's name is found where it is defined`() throws {
    let text = Self.text("   greeting = salutation SP name", "   name     = 1*ALPHA")
    let rules = try #require(ABNF.parse(text))
    #expect(rules.map { Self.substring(text, $0.nameRange) } == ["greeting", "name"])
    #expect(
      rules[1].nameRange.location == ("   greeting = salutation SP name\n   " as NSString).length)
  }

  /// Every mention, not each name once, and on continuation lines too.
  @Test func `every use of a name is found, continuation lines included`() throws {
    let text = Self.text(
      "pair  = item \",\" item   ; two of them",
      "        [ item ]",
      "item  = 1*DIGIT")
    let rules = try #require(ABNF.parse(text))
    let uses = rules[0].uses
    #expect(uses.map(\.name) == ["item", "item", "item"])
    #expect(uses.allSatisfy { Self.substring(text, $0.range) == "item" })
    #expect(
      uses.last.map { $0.range.location }
        == (Self.text("pair  = item \",\" item   ; two of them", "        [ ") as NSString).length)
  }

  /// A quoted literal, a prose value, a numeric value and a comment hold no names.
  @Test func `literals, prose, numbers and comments hold no names`() throws {
    let text = "token = \"name\" <name of it> %x41 other  ; name"
    let rules = try #require(ABNF.parse(text))
    #expect(rules[0].uses.map(\.name) == ["other"])
  }

  /// Offsets count UTF-16 code units, so text before a name that is not ASCII, as a
  /// comment may be, moves it by what the reader's storage counts.
  @Test func `a name after text outside ASCII is found at its UTF-16 offset`() throws {
    let text = Self.text("; ünïcödé — 𝒜 comment", "first = second")
    let rules = try #require(ABNF.parse(text))
    #expect(Self.substring(text, rules[0].nameRange) == "first")
    #expect(Self.substring(text, rules[0].uses[0].range) == "second")
  }

  // MARK: RFC 822's dialect (#696)

  /// A grammar written before RFC 5234, as RFC 822's notation and RFC 2616's are,
  /// alternates with `|`: no RFC 5234 grammar, and a grammar in RFC 822's dialect.
  @Test func `a grammar that alternates with a bar is RFC 822's`() throws {
    let text = "first-rule = second-rule | third-rule\nsecond-rule = 1*DIGIT"
    #expect(ABNF.parse(text) == nil)
    #expect(!ABNF.recognizes(text))
    let rules = try #require(ABNF.parse(text, dialect: .rfc822))
    #expect(rules.map(\.name) == ["first-rule", "second-rule"])
    #expect(ABNF.recognizes(text, dialect: .rfc822))
  }

  /// A grammar of that time names rules with `_` too, which RFC 5234 does not allow.
  @Test func `RFC 822's dialect allows an underscore in a name`() throws {
    let text = "first_rule = second_rule | %x20\nsecond_rule = 1*DIGIT"
    #expect(ABNF.parse(text) == nil)
    let rules = try #require(ABNF.parse(text, dialect: .rfc822))
    #expect(rules.map(\.name) == ["first_rule", "second_rule"])
    #expect(rules[0].references == ["second_rule"])
  }

  /// `|` is C's bitwise or too, and identifiers name one another in any code, so in
  /// the bar dialect neither an alternative alone nor plain rules that refer to one
  /// another make a grammar; a literal, a repetition or an option does.
  @Test func `the bar dialect needs more than an alternative`() {
    #expect(!ABNF.recognizes("flags = SYN | ACK", dialect: .rfc822))
    #expect(!ABNF.recognizes("tmp_len = buf_len\nout_len = tmp_len", dialect: .rfc822))
    #expect(ABNF.recognizes(#"answer = "yes" | "no""#, dialect: .rfc822))
  }

  /// A grammar in the bar dialect set as several blocks is one grammar: its artwork
  /// RFC 5234 reads too, a plain rule, is typed with it; a stretch with no block in the
  /// bar dialect alone stays as it was, and so does one whose only sign is an `_`.
  @Test func `a bar-dialect grammar's blocks are typed alike`() {
    let blocks = [
      Self.verbatim(#"answer = "yes" | "no""#), Self.verbatim("choice = answer count"),
    ]
    let typed = LegacyTextParser.typingGrammars(blocks)
    #expect(
      typed.allSatisfy { block in
        if case .preformatted(let verbatim) = block { verbatim.type == "abnf822" } else { false }
      })
    let rfc5234 = [Self.verbatim("count = 1*DIGIT", abnf: true), Self.verbatim("+--+")]
    #expect(LegacyTextParser.typingGrammars(rfc5234) == rfc5234)
    let settings = [Self.verbatim("wait_time=100ms")]
    #expect(LegacyTextParser.typingGrammars(settings) == settings)
  }

  /// Between prose too: where more of a document's grammar blocks are in the bar
  /// dialect alone than in RFC 5234's, its blocks typed as RFC 5234's that the bar
  /// dialect reads are that grammar's; one with a `/` alternative stays RFC 5234's.
  @Test func `a document's grammar is in one dialect`() {
    let bar = Preformatted(kind: .sourceCode, text: #"answer = "yes" | "no""#, type: "abnf822")
    let plain = Preformatted(kind: .sourceCode, text: "count = 1*DIGIT", type: "abnf")
    let slash = Preformatted(kind: .sourceCode, text: "pick = this / that", type: "abnf")
    let sections = [
      Section(anchor: "section-1", number: "1", title: "One", blocks: [.preformatted(bar)]),
      Section(
        anchor: "section-2", number: "2", title: "Two",
        blocks: [.preformatted(plain), .preformatted(slash)]),
    ]
    let unified = LegacyTextParser.unifyingGrammarDialect(
      [sections[0], sections[0]] + [sections[1]])
    let types = unified[2].blocks.compactMap { block -> String? in
      if case .preformatted(let verbatim) = block { verbatim.type } else { nil }
    }
    #expect(types == ["abnf822", "abnf"])
    #expect(LegacyTextParser.unifyingGrammarDialect([sections[1]]) == [sections[1]])
    // An RFC 5234 grammar that slips into `|` once stays RFC 5234's.
    #expect(LegacyTextParser.unifyingGrammarDialect(sections) == sections)
  }

  /// A block that alternates with both is neither dialect's grammar.
  @Test func `a grammar mixing slash and bar is no grammar`() {
    let text = "first-rule = second-rule / third-rule | %x20\nsecond-rule = 1*DIGIT"
    #expect(!ABNF.recognizes(text))
    #expect(!ABNF.recognizes(text, dialect: .rfc822))
  }

  /// RFC 2371 writes its grammar with `|`: it is typed as RFC 822's, which the reader
  /// links and an export as RFC 5234 ABNF leaves out.
  @Test func `RFC 2371's grammar is typed as RFC 822's`() throws {
    let document = try Fixtures.document("rfc2371.txt")
    let grammar = try #require(
      document.blocks.lazy.compactMap { block -> Preformatted? in
        if case .preformatted(let preformatted) = block { preformatted } else { nil }
      }
      .first { $0.text.contains("pchar") })
    #expect(grammar.kind == .sourceCode)
    #expect(grammar.type == "abnf822")
  }

  /// RFC 2511's `|` is concatenation in pseudocode, not an alternative.
  @Test func `RFC 2511's pseudocode is no grammar`() throws {
    let document = try Fixtures.document("rfc2511.txt")
    let typed = document.blocks.filter { block in
      if case .preformatted(let preformatted) = block {
        preformatted.type == "abnf822"
      } else {
        false
      }
    }
    #expect(typed.isEmpty)
  }

  // MARK: Through parse

  /// RFC 5234 sets its own grammar and its core rules as ABNF: both come out as
  /// source code typed `abnf`, as RFCXML writes it.
  @Test func `RFC 5234's grammars are source code typed abnf`() throws {
    let document = try Fixtures.document("rfc5234.txt")
    let verbatim = document.blocks.compactMap { block -> Preformatted? in
      guard case .preformatted(let preformatted) = block else { return nil }
      return preformatted
    }
    let grammar = verbatim.filter { $0.text.contains("rulelist") }
    let coreRules = verbatim.filter { $0.text.contains("%x41-5A") }
    #expect(!grammar.isEmpty && !coreRules.isEmpty)
    #expect((grammar + coreRules).allSatisfy { $0.kind == .sourceCode && $0.type == "abnf" })
  }

  /// A rule set apart by blank lines is still its grammar's: RFC 5234 sets its
  /// examples, and a rule of its own grammar and of its core rules, one block a rule,
  /// and those whose rule was plain stayed artwork between source code (#423).
  @Test func `a plain rule beside its grammar is the grammar's`() throws {
    let document = try Fixtures.document("rfc5234.txt")
    let verbatim = document.blocks.compactMap { block -> Preformatted? in
      guard case .preformatted(let preformatted) = block else { return nil }
      return preformatted
    }
    for locator in ["mumble", "=/ alt3", "rulename defined-as", "CR LF"] {
      let block = try #require(verbatim.first { $0.text.contains(locator) }, "\(locator)")
      #expect(block.kind == .sourceCode && block.type == "abnf", "\(locator)")
    }
  }

  // MARK: Runs (#423)

  private static func verbatim(_ text: String, abnf: Bool = false) -> Block {
    .preformatted(
      abnf
        ? Preformatted(kind: .sourceCode, text: text, type: "abnf")
        : Preformatted(kind: .artwork, text: text))
  }

  /// A block of one plain rule between two of a grammar's is typed with them.
  @Test func `a plain rule between grammar blocks joins them`() {
    let blocks = [
      Self.verbatim("first-rule = second-rule / %x20", abnf: true),
      Self.verbatim("second-rule = third-rule fourth-rule"),
      Self.verbatim("third-rule = 1*DIGIT", abnf: true),
    ]
    let typed = LegacyTextParser.typingGrammars(blocks)
    #expect(
      typed == [
        blocks[0], Self.verbatim("second-rule = third-rule fourth-rule", abnf: true), blocks[2],
      ])
  }

  /// A drawing between them ends the run, and a block that does not parse stays
  /// artwork, as plain assignments that refer to nothing among them do.
  @Test func `a drawing or pseudocode beside a grammar stays artwork`() {
    let drawing = [
      Self.verbatim("first-rule = second-rule / %x20", abnf: true),
      Self.verbatim("+------+\n| box  |\n+------+"),
      Self.verbatim("second-rule = other"),
    ]
    #expect(LegacyTextParser.typingGrammars(drawing) == drawing)
    let pseudocode = [Self.verbatim("count = limit"), Self.verbatim("size = width")]
    #expect(LegacyTextParser.typingGrammars(pseudocode) == pseudocode)
  }

  /// Plain assignments that each parse and name one another are no grammar unless one
  /// block of their stretch is one alone: pseudocode reads that way as often.
  @Test func `assignments naming one another need a grammar beside them`() {
    let assignments = [Self.verbatim("lowest = unset"), Self.verbatim("highest = lowest")]
    #expect(LegacyTextParser.typingGrammars(assignments) == assignments)
  }

  /// Each block of a stretch is parsed with its own indentation: a comment set left of
  /// one block's rules does not make them continue the block above.
  @Test func `each block of a stretch keeps its own rule column`() {
    let blocks = ["first-rule = second-rule / %x20", "; the second rule\n  second-rule = 1*DIGIT"]
    #expect(ABNF.recognizes(blocks: blocks))
    // A name defined in two blocks is defined twice, as within one.
    #expect(!ABNF.recognizes(blocks: ["first-rule = second-rule", "first-rule = third-rule"]))
  }

  /// A comment set left of the rules does not set the column a page's opening line
  /// has to be deeper than: a new rule there is no continuation.
  @Test func `a comment left of the rules does not make a rule a continuation`() {
    let first = [" ; the rules", "   first-rule = alpha", "                / beta"]
    #expect(!LegacyTextParser.continuesGrammarAcrossPage(first, ["  second-rule = (", "   gamma"]))
  }

  /// The half of a grammar after a page break opens with the continuation of the
  /// rule the page cut, and is the rest of that rule's block.
  @Test func `a grammar cut by a page break goes on across it`() {
    let first = ["   first-rule = alpha", "                / beta"]
    let second = ["                / gamma", "   second-rule = first-rule"]
    #expect(LegacyTextParser.continuesGrammarAcrossPage(first, second))
    let prose = ["   This rule is not continued here, and the next page holds", "   words."]
    #expect(!LegacyTextParser.continuesGrammarAcrossPage(first, prose))
    #expect(!LegacyTextParser.continuesGrammarAcrossPage(first, ["   third-rule = alpha"]))
  }

  /// A diagram stays artwork.
  @Test func `RFC 793's diagrams stay artwork`() throws {
    let document = try Fixtures.document("rfc793.txt")
    let typed = document.blocks.filter { block in
      if case .preformatted(let preformatted) = block { return preformatted.type == "abnf" }
      return false
    }
    #expect(typed.isEmpty)
  }
}
