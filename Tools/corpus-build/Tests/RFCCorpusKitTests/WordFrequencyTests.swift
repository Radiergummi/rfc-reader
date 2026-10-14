import Foundation
import RFCCorpusKit
import RFCKit
import Testing

/// What `corpus-build common-words` counts (#396): in how many documents each
/// lower-case word is used in prose, and which defined terms a threshold would skip.
@Suite("Word frequency")
struct WordFrequencyTests {
  /// A one-section document whose prose is `paragraphs`, defining `terms`.
  private static func document(_ paragraphs: [String], defining terms: [String] = [])
    -> RFCDocument
  {
    var document = RFCDocument(
      header: DocumentHeader(title: "T"),
      sections: [
        Section(
          anchor: "section-1", number: "1", title: "S",
          blocks: paragraphs.map { .paragraph(Paragraph(text: $0)) })
      ],
      source: .xml)
    for term in terms {
      document.definedTerms[term] = DefinedTerm(
        term: term, anchor: "section-1", definition: [.paragraph(Paragraph(text: "A thing."))])
    }
    return document
  }

  @Test func `a word keeps its inner hyphens and apostrophes, not its outer ones`() {
    #expect(
      WordFrequency.words(in: "an on-path peer's -- 'quoted' end-")
        == ["an", "on-path", "peer's", "quoted", "end"])
  }

  @Test func `a word is counted once per document, however often it is used`() {
    var frequency = WordFrequency()
    frequency.add(Self.document(["the client sends", "the client waits"]))
    frequency.add(Self.document(["a server answers"]))
    #expect(frequency.documentFrequency["client"] == 1)
    #expect(frequency.documentFrequency["the"] == 1)
    #expect(frequency.documentFrequency["server"] == 1)
  }

  @Test func `only lower-case words are counted, so an acronym is never common`() {
    var frequency = WordFrequency()
    frequency.add(Self.document(["TLS protects the Client"]))
    #expect(frequency.documentFrequency["TLS"] == nil)
    #expect(frequency.documentFrequency["Client"] == nil)
    #expect(frequency.documentFrequency["protects"] == 1)
  }

  @Test func `the common words are those used in at least the threshold's share`() {
    var frequency = WordFrequency()
    frequency.add(Self.document(["client server"]))
    frequency.add(Self.document(["client relay"]))
    frequency.add(Self.document(["client"]))
    frequency.add(Self.document(["server"]))
    #expect(frequency.commonWords(threshold: 0.5) == ["client", "server"])
    #expect(frequency.commonWords(threshold: 0.75) == ["client"])
  }

  @Test func `a cut counts the defined single-word terms it would skip`() throws {
    var frequency = WordFrequency()
    frequency.add(Self.document(["client"], defining: ["client", "user agent"]))
    frequency.add(Self.document(["client relay"], defining: ["client", "relay"]))
    let report = frequency.report(thresholds: [0.5, 1])
    #expect(report.definedSingleWords == 2, "a term of several words is never one word")
    let half = try #require(report.cuts.first)
    #expect(half.skippedTerms == 2)
    #expect(half.skippedDefinitions == 3)
    let all = try #require(report.cuts.last)
    #expect(all.skippedTerms == 1, "only client is in every document")
    #expect(report.terms.first?.term == "client")
  }
}
