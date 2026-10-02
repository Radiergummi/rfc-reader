import Foundation

/// JSON as RFCs set it: often a fragment — members without their object, an array's
/// elements — and elided with `...`.
///
/// Adapted from Chroma's `lexers/embedded/json.xml` (github.com/alecthomas/chroma,
/// commit e4159240b179, MIT License), itself converted from Pygments' JSON lexer
/// (BSD 2-Clause License); both notices are in THIRD_PARTY_NOTICES. Chroma's states
/// follow objects and arrays, and lose their place in a fragment; here a key is told
/// by the colon after it, so one state reads a fragment as well as a document.
/// Strings end at their line, as JSON's do, so one left open colors nothing after
/// it — unless RFC 8792 folded the line, with a backslash at its end, which a
/// string continues across, set in on the next line. Every repetition is
/// possessive, so none can backtrack.
enum JSONLexer {
  static let states: [String: [Lexer.Rule]] = [
    "root": [
      Lexer.Rule(#"\s++"#, .plain),
      Lexer.Rule(#"//[^\n]*+"#, .comment),
      Lexer.Rule(#""(?:[^"\\\n]++|\\\n[ \t]*+\\?|\\.)*+"(?=\s*+:)"#, .name),
      Lexer.Rule(#""(?:[^"\\\n]++|\\\n[ \t]*+\\?|\\.)*+""#, .string),
      Lexer.Rule(#"-?(?:0|[1-9][0-9]*+)(?:\.[0-9]++)?(?:[eE][+-]?[0-9]++)?"#, .number),
      Lexer.Rule(#"(?:true|false|null)\b"#, .keyword),
      Lexer.Rule(#"\.\.\.|…"#, .comment),
      Lexer.Rule(#"[{}\[\],:]"#, .punctuation),
    ]
  ]

  static let lexer = Lexer.defined(states)
}
