import Foundation
import RFCKit
import Testing

@testable import RFCReaderKit

/// Which uses of a document's defined terms and abbreviations the reader marks
/// (#396, #67): the first not yet marked, matched case-sensitively, as a whole word,
/// the longest where two start together, never a common English word, nor an
/// abbreviation right after its own expansion.
struct GlossMatcherTests {
  private static func term(_ spelling: String) -> DefinedTerm {
    DefinedTerm(
      term: spelling, anchor: "def-\(spelling)",
      definition: [.paragraph(Paragraph(text: "What \(spelling) means."))])
  }

  private static func matcher(
    _ spellings: String..., abbreviations: [Abbreviation] = [], common: Set<String> = []
  ) -> GlossMatcher {
    GlossMatcher(
      Dictionary(uniqueKeysWithValues: spellings.map { ($0, term($0)) }),
      abbreviations: Dictionary(uniqueKeysWithValues: abbreviations.map { ($0.short, $0) }),
      commonWords: common)
  }

  private static let tls = Abbreviation(
    short: "TLS", expansion: "Transport Layer Security", sectionAnchor: "section-2")

  /// The words `uses` marks, in order.
  private static func marked(
    _ matcher: GlossMatcher, in text: String, skipping: Set<String> = []
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
    #expect(use.gloss == .term(Self.term("relay")))
  }

  @Test func `an abbreviation is marked by its short form`() throws {
    let matcher = Self.matcher(abbreviations: [Self.tls])
    let use = try #require(matcher.uses(in: "over TLS 1.3", skipping: []).first)
    #expect(use.range == NSRange(location: 5, length: 3))
    #expect(use.gloss == .abbreviation(Self.tls))
  }

  /// The card would say the words right beside it.
  @Test func `an abbreviation in parentheses where it is expanded is not marked`() {
    let matcher = Self.matcher(abbreviations: [Self.tls])
    let text = "Transport Layer Security (TLS) protects it, and TLS"
    let uses = matcher.uses(in: text, skipping: [], expanded: ["TLS"])
    #expect(
      uses.map(\.range.location) == [
        (text as NSString).range(of: "TLS", options: .backwards).location
      ])
  }

  @Test func `an abbreviation after other words in parentheses is marked`() {
    let matcher = Self.matcher(abbreviations: [Self.tls])
    #expect(Self.marked(matcher, in: "a secure channel (TLS)") == ["TLS"])
  }

  /// Whatever its case and white space, and across the runs a paragraph's emphasis
  /// or link splits it into.
  @Test func `a paragraph's own expansions are found`() {
    let abbreviations = [
      "TLS": Self.tls, "IP": Abbreviation(short: "IP", expansion: "Internet Protocol"),
    ]
    #expect(
      GlossMatcher.expanded(
        in: "Uses transport layer\n   security (TLS) over IP.", among: abbreviations)
        == ["TLS"])
  }

  @Test func `an abbreviation marked in the section is not marked again`() {
    let matcher = Self.matcher(abbreviations: [Self.tls])
    #expect(matcher.uses(in: "over TLS", skipping: [], markedInSection: ["TLS"]).isEmpty)
  }

  /// An acronym is never a common word, as a term's is not: `ID` is marked, whatever
  /// `id` is.
  @Test func `an abbreviation is never common`() {
    let matcher = Self.matcher(
      abbreviations: [Abbreviation(short: "ID", expansion: "Identifier")], common: ["id"])
    #expect(Self.marked(matcher, in: "the ID") == ["ID"])
  }

  /// A term's definition says more than an abbreviation's expansion.
  @Test func `a defined term beats an abbreviation of the same spelling`() throws {
    let matcher = Self.matcher("TLS", abbreviations: [Self.tls])
    let use = try #require(matcher.uses(in: "over TLS", skipping: []).first)
    #expect(use.gloss == .term(Self.term("TLS")))
  }

  @Test func `the bundled common words are read`() {
    #expect(GlossMatcher.bundledCommonWords.contains("client"))
    #expect(!GlossMatcher.bundledCommonWords.contains("upstream"))
  }
}
