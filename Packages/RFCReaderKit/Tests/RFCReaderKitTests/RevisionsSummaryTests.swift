import Foundation
import RFCKit
import Testing

@testable import RFCReaderKit

/// What the banner and the inspector say about drafts revising an RFC. Dates in
/// en_GB and UTC, so "25 September" reads the same on any machine.
@Suite("Revisions summary")
struct RevisionsSummaryTests {
  private static let now = Date(timeIntervalSince1970: 1_790_000_000)  // 2026-09-21T14:13:20Z
  private static let day: TimeInterval = 86_400
  private static let locale = Locale(identifier: "en_GB")
  private static let utc = TimeZone(identifier: "UTC")!

  private static func revision(
    _ draft: String, _ relation: RevisionRelation = .obsoletes,
    stage: RevisionStage = .inGroup, stream: String = "ietf", revision: String = "22",
    published: Date = now - 30 * day
  ) -> RFCRevisions.Revision {
    RFCRevisions.Revision(
      relation: relation, draft: draft, revision: revision, published: published, stream: stream,
      group: "example", intendedStatus: "Proposed Standard", stage: stage)
  }

  private static func summary(
    _ revisions: [RFCRevisions.Revision], generated: Date = now - day
  ) -> RevisionsSummary {
    RevisionsSummary(
      RFCRevisions(generatedAt: generated, revisions: [9990: revisions]), rfc: 9990, now: now,
      locale: locale, timeZone: utc)
  }

  @Test func `drafts are ordered by stage, then obsoletes before updates, then name`() {
    let summary = Self.summary([
      Self.revision("draft-c", .updates, stage: .rfcEditorQueue),
      Self.revision("draft-b", .obsoletes, stage: .inGroup),
      Self.revision("draft-a", .updates, stage: .inGroup),
      Self.revision("draft-d", .obsoletes, stage: .rfcEditorQueue),
    ])
    #expect(summary.revisions.map(\.draft) == ["draft-d", "draft-c", "draft-b", "draft-a"])
  }

  @Test func `a banner line names the relation, the draft and its stage`() throws {
    let line = try #require(
      Self.summary([Self.revision("draft-ietf-example-rfc9990bis", stage: .rfcEditorQueue)])
        .bannerLines.first)
    #expect(line.relation == "Being replaced by")
    #expect(line.title == "draft-ietf-example-rfc9990bis-22")
    #expect(line.detail == "In the RFC Editor queue")
    #expect(
      line.url.absoluteString == "https://datatracker.ietf.org/doc/draft-ietf-example-rfc9990bis/")
    #expect(
      line.accessibilityLabel
        == "Being replaced by draft-ietf-example-rfc9990bis, revision 22, in the RFC Editor queue")
  }

  @Test func `an update is being updated by`() {
    #expect(
      Self.summary([Self.revision("draft-a", .updates)]).bannerLines.first?.relation
        == "Being updated by")
  }

  @Test func `a file three days old is current, and one older is stale`() {
    #expect(!Self.summary([Self.revision("draft-a")], generated: Self.now - 3 * Self.day).isStale)
    let stale = Self.summary(
      [Self.revision("draft-a", stage: .rfcEditorQueue)], generated: Self.now - 4 * Self.day)
    #expect(stale.isStale)
    #expect(stale.bannerLines.first?.detail == "In the RFC Editor queue, as of 17 September")
    #expect(stale.bannerLines.first?.accessibilityLabel.hasSuffix(", as of 17 September") == true)
  }

  /// A device offline since last year would otherwise read last year's date as
  /// this year's.
  @Test func `a file from an earlier year says the year`() {
    let lastYear = Self.summary(
      [Self.revision("draft-a", stage: .rfcEditorQueue)], generated: Self.now - 400 * Self.day)
    #expect(lastYear.bannerLines.first?.detail == "In the RFC Editor queue, as of 17 August 2025")
  }

  /// An active draft can sit in one state for years.
  @Test func `a revision over a year old carries its date`() {
    let old = Self.revision(
      "draft-a", stage: .iesgReview, revision: "05",
      published: Date(timeIntervalSince1970: 1_397_482_769))  // April 2014
    let line = Self.summary([old]).bannerLines.first
    #expect(line?.detail == "Under IESG review, revision of April 2014")
    #expect(
      line?.accessibilityLabel
        == "Being replaced by draft-a, revision 5 from April 2014, under IESG review")
  }

  @Test func `a stale file and a dormant draft say both`() {
    let old = Self.revision(
      "draft-a", stage: .iesgReview, published: Date(timeIntervalSince1970: 1_397_482_769))
    #expect(
      Self.summary([old], generated: Self.now - 5 * Self.day).bannerLines.first?.detail
        == "Under IESG review, revision of April 2014, as of 16 September")
  }

  @Test func `the banner shows two drafts and counts the rest`() {
    let summary = Self.summary(
      ["draft-a", "draft-b", "draft-c", "draft-d"].map { Self.revision($0) })
    #expect(summary.bannerLines.count == 2)
    #expect(summary.moreText == "and 2 more")
    #expect(Self.summary(["draft-a", "draft-b"].map { Self.revision($0) }).moreText == nil)
  }

  @Test func `an RFC nothing revises has no lines`() {
    let summary = RevisionsSummary(
      RFCRevisions(generatedAt: Self.now, revisions: [9991: [Self.revision("draft-a")]]), rfc: 9990,
      now: Self.now)
    #expect(summary.isEmpty)
    #expect(summary.bannerLines.isEmpty)
    #expect(summary.moreText == nil)
  }

  @Test func `no file has no lines`() {
    #expect(RevisionsSummary(nil, rfc: 9990, now: Self.now).isEmpty)
  }

  @Test func `an inspector line lists everything`() {
    let line = Self.summary([
      Self.revision(
        "draft-a", stage: .rfcEditorQueue, published: Date(timeIntervalSince1970: 1_764_613_661))
    ]).inspectorLines(.obsoletes).first
    #expect(line?.title == "draft-a-22")
    #expect(
      line?.detail
        == "1 December 2025 · EXAMPLE · intended Proposed Standard · In the RFC Editor queue")
  }

  @Test func `an inspector list holds only its relation`() {
    let summary = Self.summary([
      Self.revision("draft-a", .obsoletes), Self.revision("draft-b", .updates),
    ])
    #expect(summary.inspectorLines(.updates).map(\.title) == ["draft-b-22"])
  }

  @Test(arguments: [
    (RevisionStage.rfcEditorQueue, "In the RFC Editor queue"),
    (.approved, "Approved for publication"),
    (.iesgReview, "Under IESG review"),
    (.ietfLastCall, "In IETF Last Call"),
    (.submitted, "Submitted for publication"),
    (.lastCall, "In working group last call"),
    (.inGroup, "In the working group"),
  ])
  func `each stage has its words`(stage: RevisionStage, words: String) {
    #expect(RevisionsSummary.stageName(stage, stream: "ietf") == words)
  }

  @Test func `an Independent draft in no group is under review`() {
    #expect(RevisionsSummary.stageName(.inGroup, stream: "ise") == "Under review")
  }
}
