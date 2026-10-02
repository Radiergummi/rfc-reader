import Foundation

/// XML as RFCs set it: instances, often fragments with elided elements.
///
/// Translated from Chroma's `lexers/embedded/xml.xml` (github.com/alecthomas/chroma,
/// commit e4159240b179, MIT License), itself converted from Pygments' XML lexer
/// (BSD 2-Clause License); both notices are in THIRD_PARTY_NOTICES. Changed from it:
/// an attribute's `=` is punctuation; a quoted value ends at its line, so a quote
/// left open colors nothing after it, unless RFC 8792 folded the line; a `<` inside
/// a tag or before a value means the tag was never closed, and leaves it;
/// repetitions are possessive where that does not change what matches.
enum XMLLexer {
  static let options: NSRegularExpression.Options = [.dotMatchesLineSeparators]

  static let states: [String: [Lexer.Rule]] = [
    "root": [
      Lexer.Rule(#"[^<&]++"#, .plain),
      Lexer.Rule(#"&[^\s;<&]*+;"#, .keyword),
      Lexer.Rule(#"<!\[CDATA\[.*?\]\]>"#, .keyword),
      Lexer.Rule(#"<!--"#, .comment, .push("comment")),
      Lexer.Rule(#"<\?.*?\?>"#, .keyword),
      Lexer.Rule(#"<![^>]*+>"#, .keyword),
      Lexer.Rule(#"<\s*+[\w:.-]++"#, .name, .push("tag")),
      Lexer.Rule(#"<\s*+/\s*+[\w:.-]++\s*+>"#, .name),
    ],
    "comment": [
      Lexer.Rule(#"[^-]++"#, .comment),
      Lexer.Rule(#"-->"#, .comment, .pop(1)),
      Lexer.Rule(#"-"#, .comment),
    ],
    "tag": [
      Lexer.Rule(#"\s++"#, .plain),
      Lexer.Rule(#"([\w.:-]++)(\s*+=)"#, groups: [.attribute, .punctuation], .push("value")),
      Lexer.Rule(#"/?\s*+>"#, .name, .pop(1)),
      Lexer.Rule(#"(?=<)"#, .plain, .pop(1)),
    ],
    "value": [
      Lexer.Rule(#"\s++"#, .plain),
      Lexer.Rule(#""(?:[^"\\\n]++|\\\n[ \t]*+\\?|\\)*+""#, .string, .pop(1)),
      Lexer.Rule(#"'(?:[^'\\\n]++|\\\n[ \t]*+\\?|\\)*+'"#, .string, .pop(1)),
      Lexer.Rule(#"(?=<)"#, .plain, .pop(1)),
      Lexer.Rule(#"[^\s>]++"#, .string, .pop(1)),
    ],
  ]

  static let lexer = Lexer.defined(states, options: options)
}
