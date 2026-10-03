import Foundation
import Testing

@testable import RFCKit

@Suite("Highlighting: which lexer a type names")
struct LexersTests {
  private func language(_ declared: String) -> Lexers.Language? {
    ArtworkType.canonical(declared).flatMap(Lexers.language(of:))
  }

  @Test func `every lexer's definition is valid`() throws {
    _ = try Lexer(states: JSONLexer.states)
    _ = try Lexer(states: XMLLexer.states, options: XMLLexer.options)
    _ = try Lexer(states: HTTPLexer.headStates)
  }

  @Test(arguments: [
    ("json", Lexers.Language.json), ("JSON", .json), ("application/json", .json),
    ("application/problem+json", .json), ("sdf+json", .json),
    ("xml", .xml), ("application/xml", .xml), ("text/xml", .xml),
    ("application/problem+xml", .xml),
    ("http-message", .httpMessage), (#"message/http; msgtype="request""#, .httpMessage),
  ])
  func `a type names its language`(declared: String, expected: Lexers.Language) {
    #expect(language(declared) == expected)
  }

  @Test(arguments: ["abnf", "asn.1", "yang", "cbor-diag", "pseudocode"])
  func `a type with no lexer names none`(declared: String) {
    #expect(language(declared) == nil)
  }

  @Test func `every claimed name and suffix names a language`() {
    for name in Lexers.claimedNames {
      #expect(Lexers.language(of: ArtworkType(name: name)) != nil, "\(name)")
    }
    for suffix in Lexers.claimedSuffixes {
      #expect(Lexers.language(of: ArtworkType(name: "x+\(suffix)")) != nil, "\(suffix)")
    }
  }

  @Test func `a block over the size limit is not highlighted`() {
    let text = String(repeating: " ", count: Lexers.sizeLimit + 1)
    #expect(Lexers.highlight(text, as: ArtworkType(name: "json")) == nil)
  }

  @Test func `a block at the size limit is`() {
    let text = String(repeating: " ", count: Lexers.sizeLimit)
    #expect(Lexers.highlight(text, as: ArtworkType(name: "json"))?.cover(text) == true)
  }

  @Test func `a type with no lexer is not highlighted`() {
    #expect(Lexers.highlight("a = b", as: ArtworkType(name: "abnf")) == nil)
  }
}
