import Foundation
import RFCKit
import Testing

@testable import RFCCorpusKit

/// What one document's `report.json` entry counts, and what it warns about. The
/// documents are built as model values: the report reads the model, not RFC text.
@Suite("Report: one document")
struct DocumentReportTests {
  private static let artwork = Block.preformatted(Preformatted(kind: .artwork, text: "+--+"))

  private static func document(
    title: String = "A Title", abstract: [Block] = [], sections: [Section]
  ) -> RFCDocument {
    RFCDocument(
      header: DocumentHeader(
        id: DocumentID(series: .rfc, number: 1000), title: title, abstract: abstract),
      sections: sections, source: .text)
  }

  @Test func `blocks are counted however deeply they are nested, in every section`() {
    let introduction = Section(
      anchor: "section-1", number: "1", title: "Introduction",
      blocks: [
        .paragraph(Paragraph(text: "Top-level prose.")),
        .list(
          ListBlock(
            style: .bullet,
            items: [ListItem(blocks: [.paragraph(Paragraph(text: "An item.")), Self.artwork])])),
        .figure(Figure(title: nil, blocks: [Self.artwork])),
      ],
      subsections: [
        Section(
          anchor: "section-1.1", number: "1.1", title: "Terms",
          blocks: [
            .definitionList([
              DefinitionItem(
                term: [.text("Term")], definition: [.paragraph(Paragraph(text: "Meaning."))])
            ]),
            .references(
              ReferenceList(
                title: "References",
                entries: [
                  Reference(anchor: "one", title: "One"), Reference(anchor: "two", title: "Two"),
                ])),
          ])
      ])
    let report = DocumentReport(
      document: Self.document(sections: [introduction]), id: "rfc1000", overridden: false)
    #expect(report.sections == 2)
    #expect(report.paragraphs == 3)
    #expect(report.lists == 1)
    #expect(report.artwork == 2)
    #expect(report.references == 2)
    #expect(report.warnings == [])
  }

  /// The abstract has never been counted, and counting it would move every
  /// document's numbers against older reports.
  @Test func `the abstract is not counted`() {
    let section = Section(
      anchor: "section-1", number: "1", title: "Introduction",
      blocks: [.paragraph(Paragraph(text: "Prose."))])
    let report = DocumentReport(
      document: Self.document(
        abstract: [.paragraph(Paragraph(text: "Abstract prose."))], sections: [section]),
      id: "rfc1000", overridden: false)
    #expect(report.paragraphs == 1)
  }

  @Test func `a document with nothing recovered warns about each missing part`() {
    let report = DocumentReport(
      document: RFCDocument(header: DocumentHeader(title: ""), sections: [], source: .text),
      id: "rfc1", overridden: false)
    #expect(
      report.warnings == [
        "no RFC number recognised in front matter", "no title", "no sections",
        "no prose paragraphs",
      ])
  }

  @Test func `more artwork than prose is flagged`() {
    let section = Section(
      anchor: "section-1", number: "1", title: "Diagrams",
      blocks: [.paragraph(Paragraph(text: "Prose.")), Self.artwork, Self.artwork])
    let report = DocumentReport(
      document: Self.document(sections: [section]), id: "rfc1000", overridden: true)
    #expect(report.warnings == ["more artwork than prose (2 vs 1); check classification"])
    #expect(report.overridden)
  }
}

/// `ProseReport.merge`: documents are diagnosed apart and folded together in order,
/// and the result must be what one pass over the corpus would have kept.
@Suite("Report: prose diagnostics merged")
struct ProseReportMergeTests {
  /// A report of `count` near misses from `document`, numbered by first line.
  private static func report(_ document: String, nearMisses count: Int) -> ProseReport {
    var report = ProseReport()
    report.documents = 1
    report.blocks = count * 2
    report.prose = count
    report.nearMisses = count
    report.soleRejection = ["internalGap": count]
    report.sample = (0..<min(count, ProseReport.sampleLimit)).map { line in
      ProseReport.NearMiss(
        document: document, section: "1", firstLine: "\(line)", lineCount: 1,
        rejection: "internalGap", indent: 3, firstLineIndent: 3, artworkMatches: 0,
        sentenceRatio: 1)
    }
    return report
  }

  @Test func `counts add up exactly`() {
    var merged = ProseReport()
    merged.merge(Self.report("rfc1", nearMisses: 3))
    merged.merge(Self.report("rfc2", nearMisses: 4))
    #expect(merged.documents == 2)
    #expect(merged.blocks == 14)
    #expect(merged.prose == 7)
    #expect(merged.nearMisses == 7)
    #expect(merged.soleRejection == ["internalGap": 7])
  }

  @Test func `the sample is the corpus's first near misses, in document order`() {
    var merged = ProseReport()
    merged.merge(Self.report("rfc1", nearMisses: 1500))
    merged.merge(Self.report("rfc2", nearMisses: 1000))
    merged.merge(Self.report("rfc3", nearMisses: 10))
    #expect(merged.sample.count == ProseReport.sampleLimit)
    #expect(merged.sample.prefix(1500).allSatisfy { $0.document == "rfc1" })
    #expect(merged.sample.dropFirst(1500).map(\.firstLine) == (0..<500).map { "\($0)" })
    #expect(merged.sample.dropFirst(1500).allSatisfy { $0.document == "rfc2" })
    #expect(merged.nearMisses == 2510, "the count stays exact past the cap")
  }
}
