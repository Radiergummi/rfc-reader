import Foundation
import Testing

@testable import RFCKit

@Suite("Highlighting: XML")
struct XMLLexerTests {
  private func tokens(_ text: String) -> [SyntaxToken] {
    XMLLexer.lexer.tokens(in: text)
  }

  @Test func `tags are names, attributes attributes, and values strings`() {
    let text = #"<entry id="e1" lang='en'>text &amp; more</entry>"#
    let tokens = tokens(text)
    #expect(tokens.cover(text))
    #expect(tokens.kind(of: "<entry", in: text) == .name)
    #expect(tokens.kind(of: "id", in: text) == .attribute)
    #expect(tokens.kind(of: #""e1""#, in: text) == .string)
    #expect(tokens.kind(of: "'en'", in: text) == .string)
    #expect(tokens.kind(of: "text", in: text) == .plain)
    #expect(tokens.kind(of: "&amp;", in: text) == .keyword)
    #expect(tokens.kind(of: "</entry>", in: text) == .name)
  }

  @Test func `a comment runs across lines to its end`() {
    let text = "<!-- one\n two -->\n<a/>"
    let tokens = tokens(text)
    #expect(tokens.cover(text))
    #expect(tokens.text(of: .comment, in: text) == ["<!-- one\n two -->"])
    #expect(tokens.kind(of: "<a", in: text) == .name)
  }

  @Test func `a declaration and an instruction are keywords`() {
    let text = "<?xml version=\"1.0\"?>\n<!DOCTYPE note>\n<note/>"
    let tokens = tokens(text)
    #expect(tokens.kind(of: "<?xml version=\"1.0\"?>", in: text) == .keyword)
    #expect(tokens.kind(of: "<!DOCTYPE note>", in: text) == .keyword)
  }

  @Test func `an elision between elements is text`() {
    let text = "<list>\n  <item/>\n  ...\n</list>"
    let tokens = tokens(text)
    #expect(tokens.cover(text))
    #expect(tokens.kind(of: "</list>", in: text) == .name)
  }

  @Test func `a quote never closed does not swallow the next element`() {
    let text = "<a id=\"open\n<b>x</b>"
    let tokens = tokens(text)
    #expect(tokens.cover(text))
    #expect(tokens.kind(of: "<b", in: text) == .name)
    #expect(tokens.kind(of: "</b>", in: text) == .name)
  }

  @Test func `a value folded per RFC 8792 is one value`() {
    let text = "<a href=\"https://example.com/abc\\\n    def\">x</a>"
    let tokens = tokens(text)
    #expect(tokens.cover(text))
    #expect(tokens.text(of: .string, in: text) == ["\"https://example.com/abc\\\n    def\""])
    #expect(tokens.kind(of: "</a>", in: text) == .name)
  }

  @Test func `a tag never closed does not swallow the next element`() {
    let text = "<a href=x\n<b>y</b>"
    let tokens = tokens(text)
    #expect(tokens.kind(of: "<b", in: text) == .name)
  }

  @Test func `a CDATA section and an instruction run across lines to their ends`() {
    let text = "<![CDATA[ a < b\n c ]]>\n<?pi one\n two?>\n<note/>"
    let tokens = tokens(text)
    #expect(tokens.cover(text))
    #expect(tokens.text(of: .keyword, in: text) == ["<![CDATA[ a < b\n c ]]>", "<?pi one\n two?>"])
    #expect(tokens.kind(of: "<note", in: text) == .name)
  }

  @Test func `an instruction never closed colors nothing and leaves the next line to the root`() {
    let text = "<?xml version=\"1.0\"\n<note>x</note>"
    let tokens = tokens(text)
    #expect(tokens.cover(text))
    #expect(tokens.text(of: .keyword, in: text).isEmpty)
    #expect(tokens.kind(of: "<note", in: text) == .name)
    #expect(tokens.kind(of: "</note>", in: text) == .name)
  }

  @Test func `a CDATA section never closed leaves the next line to the root`() {
    let text = "<![CDATA[ one\n<note>x</note>"
    let tokens = tokens(text)
    #expect(tokens.cover(text))
    #expect(tokens.text(of: .keyword, in: text).allSatisfy { !$0.contains("\n") })
    #expect(tokens.kind(of: "<note", in: text) == .name)
    #expect(tokens.kind(of: "</note>", in: text) == .name)
  }

  @Test func `the declarations in a document type's internal subset are their own`() {
    let text = "<!DOCTYPE note [\n<!ENTITY e \"x\">\n]>\n<note/>"
    let tokens = tokens(text)
    #expect(tokens.cover(text))
    #expect(tokens.text(of: .keyword, in: text) == ["<!DOCTYPE note [", "<!ENTITY e \"x\">"])
    #expect(tokens.kind(of: "<note", in: text) == .name)
  }

  /// What lexing costs is the text the lexer hands its regular expressions, counted
  /// rather than timed so the bound holds on any machine: four times the text is
  /// about four times the work, where a search per token over the whole text, or a
  /// rule that searches to the end from every opener left unclosed, makes it sixteen.
  @Test(arguments: [
    #"<item id="a1" lang='en'>text &amp; more</item>"# + "\n", "<?x ", "<![CDATA[", "<!x ",
  ])
  func `the work of lexing grows linearly with the text`(unit: String) {
    func searched(_ count: Int) -> Int {
      XMLLexer.lexer.lex(String(repeating: unit, count: count)).searched
    }
    let count = Lexers.sizeLimit / 4 / unit.utf16.count
    let small = searched(count)
    let large = searched(count * 4)
    #expect(large <= small * 5, "\(small) code units searched, then \(large)")
  }

  @Test func `many opening brackets are lexed in bounded time`() {
    let text = String(repeating: "<", count: 20_000)
    let elapsed = ContinuousClock().measure { #expect(tokens(text).cover(text)) }
    #expect(elapsed < .seconds(2))
  }
}
