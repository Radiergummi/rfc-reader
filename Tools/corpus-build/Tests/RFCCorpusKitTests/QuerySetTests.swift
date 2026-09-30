import Foundation
import RFCKit
import Testing

@testable import RFCCorpusKit

/// What the cross-reference query set makes of citing sentences. The documents are
/// model values with hand-written sentences in the shape of RFC prose: `QuerySet`
/// reads the model, so no RFC text is needed to pin what it cuts and drops.
@Suite("Query set")
struct QuerySetTests {
  private static let target = DocumentID(series: .rfc, number: 1000)

  /// A citation of RFC 1000's `section`.
  private static func citation(_ section: String) -> Inline {
    .crossReference(CrossReference(target: .document(target, section: section)))
  }

  /// A document of one section holding one paragraph per entry of `paragraphs`.
  private static func document(
    number: Int, sectionNumber: String = "1", paragraphs: [[Inline]] = []
  ) -> RFCDocument {
    RFCDocument(
      header: DocumentHeader(id: DocumentID(series: .rfc, number: number), title: "Title"),
      sections: [
        Section(
          anchor: "section-\(sectionNumber)", number: sectionNumber, title: "Section",
          blocks: paragraphs.map { .paragraph(Paragraph($0)) })
      ],
      source: .xml)
  }

  /// A query set over RFC 1000, whose section 3 is the target, and RFC 2000 citing it.
  private static func querySet(citing paragraphs: [[Inline]]) -> QuerySet {
    var querySet = QuerySet()
    querySet.collect(document(number: 1000, sectionNumber: "3"), id: "RFC1000")
    querySet.collect(document(number: 2000, paragraphs: paragraphs), id: "RFC2000")
    return querySet
  }

  /// A citing sentence with enough content words, distinct for each `variant`.
  private static func sentence(_ variant: Int) -> [Inline] {
    [
      .text(
        "Earlier text. Receivers that see frame type \(variant) close the connection "
          + "immediately and report a protocol error, as described in "),
      citation("3"),
      .text(". Later text."),
    ]
  }

  @Test func `the citing sentence is the query, with the citation cut out`() throws {
    let selection = Self.querySet(citing: [Self.sentence(7)])
      .select(limit: 10, seed: 11, minimumWords: 8)
    let row = try #require(selection.rows.first)
    #expect(selection.rows.count == 1)
    #expect(
      row.q
        == "Receivers that see frame type 7 close the connection immediately and report a "
        + "protocol error, as described in .")
    #expect(row.kind == "xref")
    #expect(row.primary == "RFC1000")
    #expect(row.from == "RFC2000")
    #expect(row.answers == [["RFC1000", "3"]])
  }

  @Test func `each filter drops its candidates and says why`() {
    var querySet = Self.querySet(citing: [
      Self.sentence(1),
      Self.sentence(1),
      [
        .text("Unknown targets are dropped when no parsed section matches, see "),
        Self.citation("9"), .text("."),
      ],
      [.text("Too short, see "), Self.citation("3"), .text(".")],
    ])
    querySet.collect(
      Self.document(number: 1000, sectionNumber: "4", paragraphs: [Self.sentence(2)]),
      id: "RFC1000")
    let selection = querySet.select(limit: 10, seed: 11, minimumWords: 8)
    #expect(querySet.citingSentences == 5)
    #expect(selection.usable == 1)
    #expect(
      selection.dropped == [
        "near-duplicate": 1, "target not in corpus": 1, "under 8 content words": 1,
        "self-citation": 1,
      ])
  }

  /// A citation with no sentence around it has nothing to describe its target by.
  @Test func `a citation that is its whole paragraph gives no query`() {
    let querySet = Self.querySet(citing: [[Self.citation("3")]])
    #expect(querySet.citingSentences == 0)
  }

  @Test func `the same seed draws the same sample, and another seed another`() {
    let querySet = Self.querySet(citing: (0..<40).map(Self.sentence))
    func sample(_ seed: UInt64) -> [String] {
      querySet.select(limit: 10, seed: seed, minimumWords: 8).rows.map(\.q)
    }
    #expect(sample(11).count == 10)
    #expect(sample(11) == sample(11))
    #expect(sample(11) != sample(12))
  }

  /// The published output of the reference implementation (Vigna's `splitmix64.c`)
  /// for seed 0, so a sample drawn here is the one drawn anywhere the generator is
  /// implemented faithfully.
  @Test func `the generator gives the reference implementation's SplitMix64 output`() {
    var generator = SplitMix64(seed: 0)
    #expect(
      (0..<3).map { _ in generator.next() } == [
        0xE220_A839_7B1D_CDAF, 0x6E78_9E6A_A1B9_65F4, 0x06C4_5D18_8009_454F,
      ])
    var seeded = SplitMix64(seed: 1_234_567)
    #expect(
      (0..<5).map { _ in seeded.next() } == [
        6_457_827_717_110_365_317, 3_203_168_211_198_807_973, 9_817_491_932_198_370_423,
        4_593_380_528_125_082_431, 16_408_922_859_458_223_821,
      ])
  }
}
