import Foundation
import Testing

@testable import RFCKit

@Suite("Highlighting: JSON")
struct JSONLexerTests {
  private func tokens(_ text: String) -> [SyntaxToken] {
    JSONLexer.lexer.tokens(in: text)
  }

  @Test func `a key is a name and its value a string`() {
    let text = #"{"title": "Example", "count": 3, "open": true, "none": null}"#
    let tokens = tokens(text)
    #expect(tokens.cover(text))
    #expect(tokens.kind(of: #""title""#, in: text) == .name)
    #expect(tokens.kind(of: #""Example""#, in: text) == .string)
    #expect(tokens.kind(of: "3", in: text) == .number)
    #expect(tokens.kind(of: "true", in: text) == .keyword)
    #expect(tokens.kind(of: "null", in: text) == .keyword)
    #expect(tokens.kind(of: "{", in: text) == .punctuation)
    #expect(tokens.kind(of: ":", in: text) == .punctuation)
  }

  @Test func `members without their object are still keys and values`() {
    let text = "\"alg\": \"ES256\",\n\"kid\": \"k1\""
    let tokens = tokens(text)
    #expect(tokens.cover(text))
    #expect(tokens.text(of: .name, in: text) == [#""alg""#, #""kid""#])
    #expect(tokens.text(of: .string, in: text) == [#""ES256""#, #""k1""#])
  }

  @Test func `a key whose colon is on the next line is a name`() {
    let text = "{\"key\"\n  : 1}"
    #expect(tokens(text).kind(of: #""key""#, in: text) == .name)
  }

  @Test func `an escaped quote does not end a string`() {
    let text = #"["say \"hi\"", 1]"#
    let tokens = tokens(text)
    #expect(tokens.text(of: .string, in: text) == [#""say \"hi\"""#])
  }

  @Test func `numbers in every form are one token`() {
    let text = "[-0.5e+10, 0, 12, 3.25, 1E3]"
    let tokens = tokens(text)
    #expect(tokens.text(of: .number, in: text) == ["-0.5e+10", "0", "12", "3.25", "1E3"])
  }

  @Test func `an elision is set apart and what follows it is still read`() {
    let text = "{\n  \"a\": 1,\n  ...\n  \"b\": 2\n}"
    let tokens = tokens(text)
    #expect(tokens.cover(text))
    #expect(tokens.kind(of: "...", in: text) == .comment)
    #expect(tokens.kind(of: #""b""#, in: text) == .name)
  }

  /// A string left open ends at its line, as JSON's strings do.
  @Test func `a string left open does not swallow the lines after it`() {
    let text = "{\"a\": \"open\n  \"b\": 2}"
    let tokens = tokens(text)
    #expect(tokens.cover(text))
    #expect(tokens.kind(of: #""b""#, in: text) == .name)
    #expect(tokens.kind(of: "2", in: text) == .number)
    #expect(tokens.text(of: .string, in: text).allSatisfy { !$0.contains("\n") })
  }

  /// RFC 8792 folds a long line with a backslash at its end and goes on, set in, on
  /// the next; the reader shows a folded block as published where unfolding it
  /// would not fit.
  @Test func `a string folded per RFC 8792 is one string`() {
    let text = "{\n  \"key\": \"abcdef\\\n      ghijkl\",\n  \"next\": 1\n}"
    let tokens = tokens(text)
    #expect(tokens.cover(text))
    #expect(tokens.text(of: .string, in: text) == ["\"abcdef\\\n      ghijkl\""])
    #expect(tokens.kind(of: #""next""#, in: text) == .name)
  }

  /// RFC 8792's second strategy marks the continuation with a backslash too.
  @Test func `a string folded with a backslash on both lines is one string`() {
    let text = "[\"abcdef\\\n   \\ghijkl\"]"
    #expect(tokens(text).text(of: .string, in: text) == ["\"abcdef\\\n   \\ghijkl\""])
  }

  @Test func `a character outside the BMP keeps the ranges after it right`() {
    let text = #"{"emoji": "😀", "next": 1}"#
    let tokens = tokens(text)
    #expect(tokens.cover(text))
    #expect(tokens.kind(of: #""😀""#, in: text) == .string)
    #expect(tokens.kind(of: #""next""#, in: text) == .name)
  }

  @Test func `a long string left open is lexed in bounded time`() {
    let text = "\"" + String(repeating: "a", count: 20_000)
    let elapsed = ContinuousClock().measure { #expect(tokens(text).cover(text)) }
    #expect(elapsed < .seconds(2))
  }

  @Test func `deeply nested brackets are lexed in bounded time`() {
    let text = String(repeating: "{[", count: 10_000)
    let elapsed = ContinuousClock().measure { #expect(tokens(text).cover(text)) }
    #expect(elapsed < .seconds(2))
  }
}
