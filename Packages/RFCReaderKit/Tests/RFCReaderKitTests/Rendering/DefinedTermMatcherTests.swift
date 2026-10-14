import Foundation
import RFCKit
import Testing

@testable import RFCReaderKit

/// Which uses of a document's defined terms the reader marks (#396): the first in a
/// paragraph, matched case-sensitively, as a whole word, the longest term where two
/// start together, and never a common English word.
struct DefinedTermMatcherTests {
  private static func term(_ spelling: String) -> DefinedTerm {
    DefinedTerm(
      term: spelling, anchor: "def-\(spelling)",
      definition: [.paragraph(Paragraph(text: "What \(spelling) means."))])
  }

  private static func matcher(_ spellings: String..., common: Set<String> = [])
    -> DefinedTermMatcher
  {
    DefinedTermMatcher(
      Dictionary(uniqueKeysWithValues: spellings.map { ($0, term($0)) }), commonWords: common)
  }

  /// The words `uses` marks, in order.
  private static func marked(
    _ matcher: DefinedTermMatcher, in text: String, skipping: Set<String> = []
  ) -> [String] {
    matcher.uses(in: text, skipping: skipping).map { (text as NSString).substring(with: $0.range) }
  }

  @Test func `a term is marked at its first use only`() {
    let matcher = Self.matcher("relay")
    #expect(Self.marked(matcher, in: "A relay forwards; the relay waits.") == ["relay"])
  }

  @Test func `a term already marked in the paragraph is not marked again`() {
    let matcher = Self.matcher("relay")
    #expect(Self.marked(matcher, in: "the relay", skipping: ["relay"]).isEmpty)
  }

  @Test func `a term is matched case-sensitively`() {
    let matcher = Self.matcher("relay")
    #expect(Self.marked(matcher, in: "Relay and RELAY are not it.").isEmpty)
  }

  @Test func `a term inside a longer word is not a use`() {
    let matcher = Self.matcher("relay")
    #expect(Self.marked(matcher, in: "relays, relaying, prerelay, relay-node").isEmpty)
  }

  @Test func `a term before punctuation or a possessive is a use`() {
    let matcher = Self.matcher("relay")
    #expect(Self.marked(matcher, in: "the relay's queue") == ["relay"])
    #expect(Self.marked(matcher, in: "(relay)") == ["relay"])
  }

  @Test func `the longest term starting at a word wins`() {
    let matcher = Self.matcher("origin", "origin server")
    #expect(
      Self.marked(matcher, in: "an origin server and an origin") == ["origin server", "origin"])
  }

  /// Once marked, the longer term is passed over whole: the shorter one starting at
  /// the same word is not its use.
  @Test func `a longer term already marked is not glossed as the shorter term`() {
    let matcher = Self.matcher("origin", "origin server")
    #expect(
      Self.marked(matcher, in: "an origin server, an origin server", skipping: ["origin server"])
        .isEmpty)
  }

  @Test func `a common word capitalized as a term is common too, an acronym is not`() {
    let matcher = Self.matcher("Server", "IP", common: ["server", "ip"])
    #expect(Self.marked(matcher, in: "Server and IP") == ["IP"])
  }

  @Test func `a term whose first word holds punctuation is found`() {
    let matcher = Self.matcher("X.509 certificate", "TCP/IP stack")
    #expect(
      Self.marked(matcher, in: "an X.509 certificate on a TCP/IP stack")
        == ["X.509 certificate", "TCP/IP stack"])
  }

  @Test func `a common word is not marked, but a term of several common words is`() {
    let matcher = Self.matcher("client", "user agent", common: ["client", "user", "agent"])
    #expect(Self.marked(matcher, in: "a client and a user agent") == ["user agent"])
  }

  @Test func `an acronym is never common`() {
    let matcher = Self.matcher("TCB", common: ["tcb"])
    #expect(Self.marked(matcher, in: "the TCB holds it") == ["TCB"])
  }

  @Test func `ranges are in UTF-16 offsets`() throws {
    let matcher = Self.matcher("relay")
    let use = try #require(matcher.uses(in: "😀 relay", skipping: []).first)
    #expect(use.range == NSRange(location: 3, length: 5))
    #expect(use.term.term == "relay")
  }

  @Test func `the bundled common words are read`() {
    #expect(DefinedTermMatcher.bundledCommonWords.contains("client"))
    #expect(!DefinedTermMatcher.bundledCommonWords.contains("upstream"))
  }
}
