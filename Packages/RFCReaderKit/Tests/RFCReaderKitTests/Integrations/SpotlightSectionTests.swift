import CoreSpotlight
import Foundation
import RFCKit
import Testing

@testable import RFCReaderKit

/// What system search knows about a section (#178): one item per section of each
/// document the app holds, kept to that set by a plan that compares it with what the
/// last indexing recorded.
@Suite("Spotlight section")
struct SpotlightSectionTests {
  private static let rows = [
    FullTextIndex.Row(
      anchor: FullTextIndex.abstractAnchor, number: nil, heading: "Abstract", body: "Opening."),
    FullTextIndex.Row(
      anchor: "section-10.2.3", number: "10.2.3", heading: "Retry-After", body: "Delay words."),
    FullTextIndex.Row(
      anchor: "acknowledgements", number: nil, heading: "Acknowledgements", body: "Thanks."),
  ]

  private static let entries = SpotlightSection.entries(
    of: .rfc(9110), titled: "HTTP Semantics", rows: rows)

  /// The RFC's own item indexes the abstract; a second hit for it is noise.
  @Test func `every section but the abstract is an entry`() {
    #expect(Self.entries.map(\.identifier.anchor) == ["section-10.2.3", "acknowledgements"])
  }

  @Test func `a section is titled with its number and heading, and names its document`() {
    let entry = Self.entries[0]
    #expect(entry.title == "10.2.3 Retry-After")
    #expect(entry.description == "RFC 9110: HTTP Semantics")
    #expect(entry.text == "Delay words.")
    #expect(Self.entries[1].title == "Acknowledgements")
  }

  /// A document the index has no metadata for still says which document it is.
  @Test func `a document without a title is named by its designation`() {
    let entries = SpotlightSection.entries(of: .rfc(9110), titled: nil, rows: Self.rows)
    #expect(entries[0].description == "RFC 9110")
  }

  /// The identifier is what a chosen result comes back as: the section's stable
  /// anchor, never its position.
  @Test func `a section is identified by its document and anchor`() {
    #expect(Self.entries[0].identifier.description == "rfc9110#section-10.2.3")
  }

  /// One domain per document, under the index's, so a document's items are deleted
  /// together.
  @Test func `a section's domain is its document's`() {
    #expect(Self.entries[0].domainIdentifier == "rfc-sections.rfc9110")
    #expect(Self.entries[0].domainIdentifier.hasPrefix(SpotlightSection.domain + "."))
  }

  @Test func `the document's number and the section's are keywords`() {
    let keywords = Self.entries[0].keywords
    for expected in ["9110", "RFC 9110", "RFC9110", "RFC 9110 10.2.3", "§10.2.3"] {
      #expect(keywords.contains(expected))
    }
    #expect(!Self.entries[1].keywords.contains { $0.hasPrefix("§") })
  }

  // MARK: - The plan

  private static let earlier = Date(timeIntervalSinceReferenceDate: 800_000_000)
  private static let later = Date(timeIntervalSinceReferenceDate: 800_086_400)

  /// What the last indexing left: its record, and the client state written with it.
  private static func plan(
    held: [DocumentID: Date], recorded documents: [DocumentID: Date]
  ) -> SpotlightSection.Plan {
    let record = SpotlightSection.Plan.record(documents)
    return SpotlightSection.Plan(
      held: held, record: record,
      clientState: SpotlightSection.Plan.clientState(forRecord: record))
  }

  @Test func `a document new to the app is indexed`() {
    let plan = Self.plan(
      held: [.rfc(9110): Self.earlier, .rfc(1): Self.earlier],
      recorded: [.rfc(1): Self.earlier])
    #expect(!plan.removesEverything)
    #expect(plan.removed.isEmpty)
    #expect(plan.indexed == [.rfc(9110)])
    #expect(plan.kept == [.rfc(1): Self.earlier])
  }

  @Test func `a document the app no longer holds is removed`() {
    let plan = Self.plan(
      held: [.rfc(1): Self.earlier],
      recorded: [.rfc(1): Self.earlier, .rfc(9110): Self.earlier])
    #expect(plan.removed == [.rfc(9110)])
    #expect(plan.indexed.isEmpty)
    #expect(plan.kept == [.rfc(1): Self.earlier])
  }

  /// A body written again may have other sections: the old ones go before the new
  /// are indexed, so none is left behind under an anchor that went away.
  @Test func `a document indexed again is removed and indexed`() {
    let plan = Self.plan(held: [.rfc(9110): Self.later], recorded: [.rfc(9110): Self.earlier])
    #expect(plan.removed == [.rfc(9110)])
    #expect(plan.indexed == [.rfc(9110)])
    #expect(plan.kept.isEmpty)
  }

  @Test func `nothing changed is nothing to do`() {
    let held: [DocumentID: Date] = [.rfc(9110): Self.earlier]
    #expect(Self.plan(held: held, recorded: held).isEmpty)
  }

  /// No state is an index never written; a record without one is not known to be what
  /// Spotlight holds. Either way it is emptied and every document indexed.
  @Test func `no record or no state starts over`() {
    let held: [DocumentID: Date] = [.rfc(9110): Self.earlier]
    let record = SpotlightSection.Plan.record(held)
    let state = SpotlightSection.Plan.clientState(forRecord: record)
    for (record, state) in [(nil, nil), (record, nil), (nil, state), (record, Data())] {
      let plan = SpotlightSection.Plan(held: held, record: record, clientState: state)
      #expect(plan.removesEverything)
      #expect(plan.indexed == [.rfc(9110)])
      #expect(plan.kept.isEmpty)
    }
  }

  /// The record is written before each batch and the state with it: a batch that
  /// failed leaves a record its state does not match, and Spotlight's contents are
  /// not known.
  @Test func `a record the state was not written for starts over`() {
    let held: [DocumentID: Date] = [.rfc(9110): Self.earlier]
    let before = SpotlightSection.Plan.record([:])
    let plan = SpotlightSection.Plan(
      held: held, record: SpotlightSection.Plan.record(held),
      clientState: SpotlightSection.Plan.clientState(forRecord: before))
    #expect(plan.removesEverything)
  }

  /// Spotlight refuses a client state of more than about a kilobyte, so the state is
  /// a digest, however many documents the record names.
  @Test func `the client state stays small`() {
    let many = Dictionary(
      uniqueKeysWithValues: (1...2000).map { (DocumentID.rfc($0), Self.earlier) })
    let state = SpotlightSection.Plan.clientState(
      forRecord: SpotlightSection.Plan.record(many))
    #expect(state.count <= 64)
  }

  /// A date is written and read back to the same instant, so a document is not
  /// indexed again at every launch.
  @Test func `the record reads back what it was written from`() {
    let documents: [DocumentID: Date] = [
      .rfc(9110): Date(timeIntervalSinceReferenceDate: 812_345_678.123_456),
      .rfc(1): .distantPast,
    ]
    #expect(Self.plan(held: documents, recorded: documents).kept == documents)
  }

  // MARK: - A chosen result

  @Test func `a chosen section opens at its anchor`() {
    let activity = NSUserActivity(activityType: CSSearchableItemActionType)
    activity.userInfo = [
      CSSearchableItemActivityIdentifier: Self.entries[0].identifier.description
    ]
    #expect(
      SpotlightEntry.link(from: activity) == RFCLink(id: .rfc(9110), anchor: "section-10.2.3"))
  }
}
