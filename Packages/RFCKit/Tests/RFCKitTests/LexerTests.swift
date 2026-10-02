import Foundation
import Testing

@testable import RFCKit

/// The engine's semantics, on lexers made up to show one rule each.
@Suite("Highlighting: the lexer engine")
struct LexerTests {
  private func lexer(
    _ states: [String: [Lexer.Rule]], options: NSRegularExpression.Options = []
  ) throws -> Lexer {
    try Lexer(states: states, options: options)
  }

  private let words: [String: [Lexer.Rule]] = [
    "root": [Lexer.Rule("[a-z]++", .name), Lexer.Rule("[0-9]++", .number)]
  ]

  @Test func `tokens cover the text exactly once`() throws {
    let text = "abc 12 de"
    let tokens = try lexer(words).tokens(in: text)
    #expect(tokens.cover(text))
    #expect(tokens.text(of: .name, in: text) == ["abc", "de"])
    #expect(tokens.text(of: .number, in: text) == ["12"])
  }

  @Test func `what no rule matches is plain`() throws {
    let text = "abc ?! de"
    let tokens = try lexer(words).tokens(in: text)
    #expect(tokens.cover(text))
    #expect(tokens.text(of: .plain, in: text) == [" ?! "])
  }

  @Test func `an empty text has no tokens`() throws {
    #expect(try lexer(words).tokens(in: "").isEmpty)
  }

  @Test func `white space alone is covered as plain`() throws {
    let text = " \n\t "
    let tokens = try lexer(words).tokens(in: text)
    #expect(tokens.cover(text))
    #expect(tokens.allSatisfy { $0.kind == .plain })
  }

  @Test func `ranges are UTF-16 and land on the right characters`() throws {
    let text = "ab😀cd"
    let tokens = try lexer(words).tokens(in: text)
    #expect(tokens.cover(text))
    #expect(tokens.text(of: .name, in: text) == ["ab", "cd"])
    #expect(tokens.text(of: .plain, in: text) == ["😀"])
  }

  @Test func `a push enters a state and a pop leaves it`() throws {
    let states: [String: [Lexer.Rule]] = [
      "root": [Lexer.Rule("[a-z]++", .name), Lexer.Rule(#"\("#, .punctuation, .push("inner"))],
      "inner": [Lexer.Rule("[a-z]++", .keyword), Lexer.Rule(#"\)"#, .punctuation, .pop(1))],
    ]
    let text = "a(b)c"
    let tokens = try lexer(states).tokens(in: text)
    #expect(tokens.cover(text))
    #expect(tokens.text(of: .name, in: text) == ["a", "c"])
    #expect(tokens.text(of: .keyword, in: text) == ["b"])
  }

  @Test func `a pop deeper than the stack stops at the root`() throws {
    let states: [String: [Lexer.Rule]] = [
      "root": [Lexer.Rule("[a-z]++", .name), Lexer.Rule(#"\)"#, .punctuation, .pop(3))]
    ]
    let text = ")a"
    let tokens = try lexer(states).tokens(in: text)
    #expect(tokens.cover(text))
    #expect(tokens.kind(of: "a", in: text) == .name)
  }

  @Test func `a pop of two leaves two states`() throws {
    let states: [String: [Lexer.Rule]] = [
      "root": [Lexer.Rule("[a-z]++", .name), Lexer.Rule(#"\{"#, .punctuation, .push("one"))],
      "one": [Lexer.Rule(#"\["#, .punctuation, .push("two"))],
      "two": [Lexer.Rule(#"\}"#, .punctuation, .pop(2)), Lexer.Rule("[a-z]++", .keyword)],
    ]
    let text = "{[x}y"
    let tokens = try lexer(states).tokens(in: text)
    #expect(tokens.kind(of: "x", in: text) == .keyword)
    #expect(tokens.kind(of: "y", in: text) == .name)
  }

  @Test func `groups take their kinds and the rest of the match is plain`() throws {
    let states: [String: [Lexer.Rule]] = [
      "root": [Lexer.Rule(#"([a-z]++)=([a-z]++);"#, groups: [.name, .string])]
    ]
    let text = "key=value;"
    let tokens = try lexer(states).tokens(in: text)
    #expect(tokens.cover(text))
    #expect(tokens.text(of: .name, in: text) == ["key"])
    #expect(tokens.text(of: .string, in: text) == ["value"])
    #expect(tokens.text(of: .plain, in: text) == ["=", ";"])
  }

  @Test func `a lookbehind sees the characters before the match`() throws {
    let states: [String: [Lexer.Rule]] = [
      "root": [
        Lexer.Rule("(?<=@)[a-z]++", .keyword), Lexer.Rule("@", .punctuation),
        Lexer.Rule("[a-z]++", .name),
      ]
    ]
    let text = "a@b"
    let tokens = try lexer(states).tokens(in: text)
    #expect(tokens.kind(of: "b", in: text) == .keyword)
  }

  @Test func `a caret matches only at the start of a line`() throws {
    let states: [String: [Lexer.Rule]] = [
      "root": [
        Lexer.Rule("^#[^\n]*+", .comment), Lexer.Rule("#", .punctuation),
        Lexer.Rule("[a-z]++", .name),
      ]
    ]
    let text = "a #x\n#y"
    let tokens = try lexer(states).tokens(in: text)
    #expect(tokens.cover(text))
    #expect(tokens.text(of: .comment, in: text) == ["#y"])
  }

  /// A state that has lost its place, as an unclosed tag has, gives up at the next
  /// newline after a character it could not match, so the next line is read from the
  /// root, as Pygments recovers.
  @Test func `after an unmatched character the next newline returns to the root`() throws {
    let states: [String: [Lexer.Rule]] = [
      "root": [Lexer.Rule("[a-z]++", .keyword), Lexer.Rule("<", .punctuation, .push("tag"))],
      "tag": [
        Lexer.Rule("[a-z]++", .name), Lexer.Rule(#"\s++"#, .plain),
        Lexer.Rule(">", .punctuation, .pop(1)),
      ],
    ]
    let text = "<a ! \nb"
    let tokens = try lexer(states).tokens(in: text)
    #expect(tokens.cover(text))
    #expect(tokens.kind(of: "a", in: text) == .name)
    #expect(tokens.kind(of: "b", in: text) == .keyword)
  }

  /// When the newline that gives a state up is the last unmatched character, the
  /// match the lost state found after it is not taken: it is searched for again from
  /// the root.
  @Test func `a state given up at a newline does not take its own match after it`() throws {
    let states: [String: [Lexer.Rule]] = [
      "root": [
        Lexer.Rule("<", .punctuation, .push("tag")), Lexer.Rule("[a-z]++", .keyword),
      ],
      "tag": [Lexer.Rule("[a-z]++", .name), Lexer.Rule(">", .punctuation, .pop(1))],
    ]
    let text = "<a !\nb"
    let tokens = try lexer(states).tokens(in: text)
    #expect(tokens.cover(text))
    #expect(tokens.kind(of: "a", in: text) == .name)
    #expect(tokens.kind(of: "b", in: text) == .keyword)
  }

  @Test func `a lookahead may change state without consuming`() throws {
    let states: [String: [Lexer.Rule]] = [
      "root": [Lexer.Rule("[a-z]++", .plain), Lexer.Rule("(?=<)", .plain, .push("tag"))],
      "tag": [Lexer.Rule("<[a-z]++", .name), Lexer.Rule(">", .name, .pop(1))],
    ]
    let text = "x<a>y"
    let tokens = try lexer(states).tokens(in: text)
    #expect(tokens.cover(text))
    #expect(tokens.text(of: .name, in: text) == ["<a>"])
  }

  @Test func `states that only trade places cannot loop forever`() throws {
    let states: [String: [Lexer.Rule]] = [
      "root": [Lexer.Rule("(?=a)", .plain, .push("other"))],
      "other": [Lexer.Rule("(?=a)", .plain, .pop(1))],
    ]
    let text = "aa"
    #expect(try lexer(states).tokens(in: text).cover(text))
  }

  @Test func `a definition without a root state is refused`() {
    #expect(throws: Lexer.DefinitionError.noRootState) {
      try lexer(["other": [Lexer.Rule("a", .name)]])
    }
  }

  @Test func `a push to a state that does not exist is refused`() {
    #expect(throws: Lexer.DefinitionError.unknownState("missing")) {
      try lexer(["root": [Lexer.Rule("a", .name, .push("missing"))]])
    }
  }

  @Test func `a pattern that does not compile is refused`() {
    #expect(throws: Lexer.DefinitionError.invalidPattern("(")) {
      try lexer(["root": [Lexer.Rule("(", .name)]])
    }
  }

  @Test func `kinds for groups must match the groups`() {
    #expect(throws: Lexer.DefinitionError.groupCountMismatch("(a)(b)")) {
      try lexer(["root": [Lexer.Rule("(a)(b)", groups: [.name])]])
    }
  }

  @Test func `nested groups are refused`() {
    #expect(throws: Lexer.DefinitionError.nestedGroups("((a)b)")) {
      try lexer(["root": [Lexer.Rule("((a)b)", groups: [.name, .string])]])
    }
  }

  /// Each state is compiled to one alternation, which renumbers the groups.
  @Test func `a backreference is refused`() {
    #expect(throws: Lexer.DefinitionError.backreference(#"(a)\1"#)) {
      try lexer(["root": [Lexer.Rule(#"(a)\1"#, groups: [.name])]])
    }
  }

  @Test func `a rule that can match nothing must change state`() {
    #expect(throws: Lexer.DefinitionError.matchesEmptyWithoutTransition("a*")) {
      try lexer(["root": [Lexer.Rule("a*", .name)]])
    }
  }
}
