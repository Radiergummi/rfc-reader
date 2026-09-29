import Foundation
import Testing

@testable import RFCKit

/// `revisions.json`, which the scanner writes and the app reads: one format, so both
/// sides go through the same coders.
@Suite("RFC revisions file")
struct RFCRevisionsTests {
  private let sample = RFCRevisions(
    generatedAt: Date(timeIntervalSince1970: 1_790_000_000),
    revisions: [
      9999: [
        RFCRevisions.Revision(
          relation: .obsoletes, draft: "draft-ietf-example-rfc9999bis", revision: "04",
          published: Date(timeIntervalSince1970: 1_780_000_000), stream: "ietf",
          group: "example", intendedStatus: "Proposed Standard", stage: .rfcEditorQueue)
      ]
    ])

  @Test func `a file round-trips through its own coders`() throws {
    #expect(try RFCRevisions.decode(sample.encoded()) == sample)
  }

  /// JSON has no integer keys. The number is written as a string and read back as
  /// the number, which is what the app looks it up by.
  @Test func `an RFC number is a string key in the JSON`() throws {
    let json = String(decoding: try sample.encoded(), as: UTF8.self)
    #expect(json.contains("\"9999\""))
  }

  @Test func `a file of an unknown version is refused`() throws {
    var json = String(decoding: try sample.encoded(), as: UTF8.self)
    json = json.replacingOccurrences(of: "\"version\" : 1", with: "\"version\" : 2")
    #expect(throws: RFCRevisions.VersionError.unknown(2)) {
      try RFCRevisions.decode(Data(json.utf8))
    }
  }

  @Test func `stages are ordered from earliest to furthest along`() {
    #expect(
      RevisionStage.allCases.sorted() == [
        .inGroup, .lastCall, .submitted, .ietfLastCall, .iesgReview, .approved, .rfcEditorQueue,
      ])
    #expect(RevisionStage.rfcEditorQueue > .approved)
  }
}
