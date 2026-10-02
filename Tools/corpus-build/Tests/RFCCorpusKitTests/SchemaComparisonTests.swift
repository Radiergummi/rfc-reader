import Foundation
import RFCCorpusKit
import RFCKit
import Testing

/// What a convert run makes of its schema results against the report it replaced. A
/// document that stops validating is a regression and fails the run; one that starts
/// cannot offset it.
@Suite("Schema check: against the previous report")
struct SchemaComparisonTests {
  /// Report entries with these schema results, the rest of each entry zero.
  private static func reports(_ schemas: KeyValuePairs<String, [String]>) throws
    -> [DocumentReport]
  {
    let entries = schemas.map { id, schema in
      let causes = schema.map { "\"\($0)\"" }.joined(separator: ", ")
      return """
        {"id": "\(id)", "title": "", "sections": 0, "paragraphs": 0, "lists": 0, "artwork": 0, \
        "references": 0, "resolvedDocuments": 0, "overridden": false, "warnings": [], \
        "schema": [\(causes)]}
        """
    }
    let json = "[\(entries.joined(separator: ", "))]"
    return try JSONDecoder().decode([DocumentReport].self, from: Data(json.utf8))
  }

  @Test func `a document that stops validating is a regression`() throws {
    let comparison = SchemaComparison(
      reports: try Self.reports(["rfc1": [], "rfc2": ["empty-middle"], "rfc3": ["duplicate-id"]]),
      previouslyValid: ["rfc1", "rfc2"])
    #expect(comparison.stoppedValidating == ["rfc2"])
    #expect(comparison.isRegression)
  }

  @Test func `documents that start validating do not offset one that stops`() throws {
    let comparison = SchemaComparison(
      reports: try Self.reports(["rfc1": ["empty-middle"], "rfc2": [], "rfc3": []]),
      previouslyValid: ["rfc1"])
    #expect(comparison.startedValidating == 2)
    #expect(comparison.stoppedValidating == ["rfc1"])
    #expect(comparison.isRegression)
  }

  @Test func `a document that still fails is no regression`() throws {
    let comparison = SchemaComparison(
      reports: try Self.reports(["rfc1": [], "rfc2": ["empty-middle"]]),
      previouslyValid: ["rfc1"])
    #expect(comparison.stoppedValidating == [])
    #expect(comparison.startedValidating == 0)
    #expect(!comparison.isRegression)
  }

  /// A run over part of the corpus is compared on the documents it converted: one the
  /// previous report held and this run did not convert has not stopped validating.
  @Test func `a document this run did not convert is no regression`() throws {
    let comparison = SchemaComparison(
      reports: try Self.reports(["rfc1": []]), previouslyValid: ["rfc1", "rfc2"])
    #expect(!comparison.isRegression)
  }

  /// A document skipped by a decision of its own (#316) has no XML to check, and has
  /// not stopped validating: four of the six stubs validated as empty documents.
  @Test func `a skipped document is no regression`() throws {
    var reports = try Self.reports(["rfc1119": []])
    reports[0].schema = nil
    reports[0].skipped = .publishedOnlyAsPDF
    let comparison = SchemaComparison(reports: reports, previouslyValid: ["rfc1119"])
    #expect(!comparison.isRegression)
    #expect(comparison.startedValidating == 0)
  }

  @Test func `regressions are listed in report order`() throws {
    let comparison = SchemaComparison(
      reports: try Self.reports([
        "rfc9": ["unexplained"], "rfc10": ["empty-middle"], "rfc2": ["duplicate-id"],
      ]),
      previouslyValid: ["rfc2", "rfc9", "rfc10"])
    #expect(comparison.stoppedValidating == ["rfc9", "rfc10", "rfc2"])
  }
}
