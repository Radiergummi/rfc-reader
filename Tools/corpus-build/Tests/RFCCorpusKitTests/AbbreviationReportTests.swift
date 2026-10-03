import Foundation
import RFCCorpusKit
import RFCKit
import Testing

/// What `corpus-build abbreviations` reports about the abbreviations the parser
/// collects (#211): each document's, and the corpus's totals.
@Suite("Abbreviation report")
struct AbbreviationReportTests {
  private static func abbreviation(_ short: String, _ expansion: String) -> Abbreviation {
    Abbreviation(short: short, expansion: expansion, sectionAnchor: "section-1")
  }

  private static func found(_ abbreviations: Abbreviation...) -> [String: Abbreviation] {
    Dictionary(uniqueKeysWithValues: abbreviations.map { ($0.short, $0) })
  }

  @Test func `each document's abbreviations are listed by short form`() {
    var report = AbbreviationReport()
    report.add(
      Self.found(
        Self.abbreviation("TLS", "Transport Layer Security"),
        Self.abbreviation("AEAD", "Authenticated Encryption with Associated Data")),
      document: "rfc1")
    #expect(report.documents["rfc1"]?.map(\.short) == ["AEAD", "TLS"])
  }

  @Test func `a document with none is read but not listed`() {
    var report = AbbreviationReport()
    report.add([:], document: "rfc1")
    report.add(Self.found(Self.abbreviation("TLS", "Transport Layer Security")), document: "rfc2")
    #expect(report.documents.keys.sorted() == ["rfc2"])
    #expect(report.totals.documentsRead == 2)
    #expect(report.totals.documentsWithAny == 1)
    #expect(report.totals.abbreviations == 1)
  }

  /// Expansions that differ only in case or spacing are one expansion: the count is of
  /// what a reader would see as different meanings.
  @Test func `a short form counts its documents and its distinct expansions`() throws {
    var report = AbbreviationReport()
    report.add(Self.found(Self.abbreviation("TLS", "Transport Layer Security")), document: "rfc1")
    report.add(Self.found(Self.abbreviation("TLS", "transport layer  security")), document: "rfc2")
    report.add(Self.found(Self.abbreviation("TLS", "Top Level Site")), document: "rfc3")
    let form = try #require(report.totals.shortForms.first)
    #expect(form.short == "TLS")
    #expect(form.documents == 3)
    #expect(form.expansions == 2)
  }

  @Test func `short forms are ordered by how many documents use them, then by name`() {
    var report = AbbreviationReport()
    report.add(
      Self.found(Self.abbreviation("B", "Bee"), Self.abbreviation("A", "Ay")), document: "rfc1")
    report.add(
      Self.found(Self.abbreviation("C", "Cee"), Self.abbreviation("B", "Bee")), document: "rfc2")
    #expect(report.totals.shortForms.map(\.short) == ["B", "A", "C"])
  }

  @Test func `the short forms listed are capped, the totals are not`() {
    var report = AbbreviationReport()
    let many = (0..<(AbbreviationReport.shortFormLimit + 5)).map {
      Self.abbreviation("X\($0)", "Expansion \($0)")
    }
    report.add(Dictionary(uniqueKeysWithValues: many.map { ($0.short, $0) }), document: "rfc1")
    #expect(report.totals.shortForms.count == AbbreviationReport.shortFormLimit)
    #expect(report.totals.abbreviations == many.count)
  }
}
