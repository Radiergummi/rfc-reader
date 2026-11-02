import CoreSpotlight
import Foundation
import RFCKit
import Testing

@testable import RFCReaderKit

/// What system search knows about a section (#178): one item per section of each
/// document the app holds, kept to that set by a plan that compares it with what the
/// last indexing recorded, and sent in batches that record what they hold.
@Suite("Spotlight section")
struct SpotlightSectionTests {
  private static let rows = [
    FullTextIndex.Row(
      anchor: FullTextIndex.abstractAnchor, number: nil, heading: "Abstract", body: "Opening.",
      title: "Abstract"),
    FullTextIndex.Row(
      anchor: "section-10.2.3", number: "10.2.3", heading: "Retry-After", body: "Delay words.",
      label: "10.2.3", title: "10.2.3. Retry-After"),
    FullTextIndex.Row(
      anchor: "appendix-A", number: "A", heading: "Collected ABNF", body: "Rules.",
      label: "Appendix A", title: "Appendix A. Collected ABNF"),
    FullTextIndex.Row(
      anchor: "acknowledgements", number: nil, heading: "Acknowledgements", body: "Thanks.",
      title: "Acknowledgements"),
  ]

  private static let entries = SpotlightSection.entries(
    of: .rfc(9110), titled: "HTTP Semantics", rows: rows)

  /// The RFC's own item indexes the abstract; a second hit for it is noise.
  @Test func `every section but the abstract is an entry`() {
    #expect(
      Self.entries.map(\.identifier.anchor) == [
        "section-10.2.3", "appendix-A", "acknowledgements",
      ])
  }

  @Test func `a section is titled with its number and heading, and names its document`() {
    let entry = Self.entries[0]
    #expect(entry.title == "10.2.3 Retry-After")
    #expect(entry.description == "RFC 9110: HTTP Semantics")
    #expect(entry.text == "Delay words.")
    #expect(Self.entries[2].title == "Acknowledgements")
  }

  /// An appendix is named by its word, as its heading names it.
  @Test func `an appendix keeps its word`() {
    let appendix = Self.entries[1]
    #expect(appendix.title == "Appendix A Collected ABNF")
    #expect(appendix.keywords.contains("Appendix A"))
  }

  /// The App Intents entity an item carries is titled as the section query titles it,
  /// so one identifier has one title.
  @Test func `the entity's title is the reader's`() {
    #expect(Self.entries[0].displayTitle == "10.2.3. Retry-After")
    #expect(Self.entries[1].displayTitle == "Appendix A. Collected ABNF")
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

  /// The document's number is the RFC's own item's to match: on every section too,
  /// it would bury that item under the document's sections.
  @Test func `the section's number is a keyword, the document's is not`() {
    let keywords = Self.entries[0].keywords
    #expect(keywords == ["10.2.3", "§10.2.3"])
    #expect(Self.entries[2].keywords.isEmpty)
  }

  // MARK: - The plan

  private static let earlier = Date(timeIntervalSinceReferenceDate: 800_000_000)
  private static let later = Date(timeIntervalSinceReferenceDate: 800_086_400)

  /// The plan after an indexing that recorded `record`, with its client state.
  private static func plan(held: [DocumentID: Date], record: Data) -> SpotlightSection.Plan {
    SpotlightSection.Plan(
      held: held, record: record,
      clientState: SpotlightSection.Plan.clientState(forRecord: record))
  }

  private static func plan(
    held: [DocumentID: Date], recorded documents: [DocumentID: Date]
  ) -> SpotlightSection.Plan {
    plan(held: held, record: SpotlightSection.Plan.record(documents))
  }

  @Test func `a document new to the app is indexed`() {
    let plan = Self.plan(
      held: [.rfc(9110): Self.earlier, .rfc(1): Self.earlier],
      recorded: [.rfc(1): Self.earlier])
    #expect(!plan.removesEverything)
    #expect(!plan.deletes)
    #expect(plan.indexed == [.rfc(9110)])
    #expect(plan.kept == [.rfc(1): Self.earlier])
  }

  @Test func `a document the app no longer holds is removed`() {
    let plan = Self.plan(
      held: [.rfc(1): Self.earlier],
      recorded: [.rfc(1): Self.earlier, .rfc(9110): Self.earlier])
    #expect(plan.removed == [.rfc(9110)])
    #expect(plan.deletes)
    #expect(plan.indexed.isEmpty)
    #expect(plan.kept == [.rfc(1): Self.earlier])
  }

  /// A body written again may have other sections: the old ones go before the new
  /// are indexed, so none is left behind under an anchor that went away.
  @Test func `a document written again is removed and indexed`() {
    let plan = Self.plan(held: [.rfc(9110): Self.later], recorded: [.rfc(9110): Self.earlier])
    #expect(plan.removed == [.rfc(9110)])
    #expect(plan.indexed == [.rfc(9110)])
    #expect(plan.kept.isEmpty)
  }

  /// An indexing stopped inside a document leaves some of its sections: they go, and
  /// the document is indexed again whole.
  @Test func `a document indexed in part is removed and indexed`() {
    let plan = Self.plan(
      held: [.rfc(9110): Self.earlier],
      record: SpotlightSection.Plan.record([:], partial: [.rfc(9110)]))
    #expect(plan.removed == [.rfc(9110)])
    #expect(plan.indexed == [.rfc(9110)])
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

  /// A new full-text index version empties that index and indexes the bodies again,
  /// under the dates they had: only the format tells that the rows may differ.
  @Test func `a record of another full-text index version starts over`() {
    let held: [DocumentID: Date] = [.rfc(9110): Self.earlier]
    let older = SpotlightSection.Plan.record(
      held, partial: [], format: "sections-2.fts-\(FullTextIndex.version - 1)")
    #expect(Self.plan(held: held, record: older).removesEverything)
    #expect(SpotlightSection.Plan.format.hasSuffix("fts-\(FullTextIndex.version)"))
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

  // MARK: - Batches

  private static func sections(_ count: Int, of id: DocumentID) -> [SpotlightSection] {
    let rows = (1...count).map {
      FullTextIndex.Row(
        anchor: "section-\($0)", number: "\($0)", heading: "Part", body: "", label: "\($0)",
        title: "\($0). Part")
    }
    return SpotlightSection.entries(of: id, titled: nil, rows: rows)
  }

  @Test func `small documents share a batch`() throws {
    var batches = SpotlightSection.Batches(kept: [:], size: 4)
    #expect(batches.add(Self.sections(1, of: .rfc(1)), of: .rfc(1), written: Self.earlier).isEmpty)
    #expect(batches.add(Self.sections(2, of: .rfc(2)), of: .rfc(2), written: Self.earlier).isEmpty)
    let finished = batches.finish()
    let last = try #require(finished)
    #expect(last.sections.count == 3)
    let held: [DocumentID: Date] = [.rfc(1): Self.earlier, .rfc(2): Self.earlier]
    #expect(Self.plan(held: held, record: last.record).isEmpty)
    #expect(batches.finish() == nil)
  }

  /// No batch is larger than the size, however large one document is; the batches it
  /// is cut across record it as partial until its last section is sent.
  @Test func `a large document is cut across batches, partial until its last`() throws {
    var batches = SpotlightSection.Batches(kept: [.rfc(1): Self.earlier], size: 4)
    let full = batches.add(Self.sections(9, of: .rfc(9110)), of: .rfc(9110), written: Self.later)
    #expect(full.map(\.sections.count) == [4, 4])
    for batch in full {
      let plan = Self.plan(
        held: [.rfc(1): Self.earlier, .rfc(9110): Self.later], record: batch.record)
      #expect(plan.removed == [.rfc(9110)])
      #expect(plan.kept == [.rfc(1): Self.earlier])
    }
    let finished = batches.finish()
    let last = try #require(finished)
    #expect(last.sections.count == 1)
    let plan = Self.plan(
      held: [.rfc(1): Self.earlier, .rfc(9110): Self.later], record: last.record)
    #expect(plan.isEmpty)
  }

  /// A document that fills a batch exactly is held once it is sent.
  @Test func `a document ending a batch is held with it`() {
    var batches = SpotlightSection.Batches(kept: [:], size: 4)
    let full = batches.add(Self.sections(4, of: .rfc(9110)), of: .rfc(9110), written: Self.later)
    #expect(full.count == 1)
    #expect(Self.plan(held: [.rfc(9110): Self.later], record: full[0].record).isEmpty)
    #expect(batches.finish() == nil)
  }

  /// A document with no sections to index is held all the same, so it is not read
  /// again at every indexing.
  @Test func `a document without sections is held`() throws {
    var batches = SpotlightSection.Batches(kept: [:], size: 4)
    #expect(batches.add([], of: .rfc(9110), written: Self.later).isEmpty)
    let finished = batches.finish()
    let last = try #require(finished)
    #expect(last.sections.isEmpty)
    #expect(Self.plan(held: [.rfc(9110): Self.later], record: last.record).isEmpty)
  }

  @Test func `each batch carries the digest of its record`() throws {
    var batches = SpotlightSection.Batches(kept: [:], size: 4)
    _ = batches.add(Self.sections(1, of: .rfc(1)), of: .rfc(1), written: Self.earlier)
    let finished = batches.finish()
    let last = try #require(finished)
    #expect(last.clientState == SpotlightSection.Plan.clientState(forRecord: last.record))
  }

  // MARK: - A chosen result

  @Test func `a chosen section opens at its number`() {
    let activity = NSUserActivity(activityType: CSSearchableItemActionType)
    activity.userInfo = [
      CSSearchableItemActivityIdentifier: Self.entries[0].identifier.description
    ]
    #expect(SpotlightEntry.link(from: activity) == RFCLink(id: .rfc(9110), section: "10.2.3"))
  }

  @Test func `a chosen unnumbered section opens at its anchor`() {
    let activity = NSUserActivity(activityType: CSSearchableItemActionType)
    activity.userInfo = [
      CSSearchableItemActivityIdentifier: Self.entries[2].identifier.description
    ]
    #expect(
      SpotlightEntry.link(from: activity) == RFCLink(id: .rfc(9110), anchor: "acknowledgements"))
  }
}
