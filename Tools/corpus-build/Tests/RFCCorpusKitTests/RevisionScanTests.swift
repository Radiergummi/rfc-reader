import Foundation
import RFCCorpusKit
import RFCKit
import Testing

/// The scanner's memory: what it reads again, what it keeps, and what it publishes.
/// Everything is built in code; nothing touches the network.
@Suite("Revision scan")
struct RevisionScanTests {
  private static let states: [Int: DraftState] = [
    1: DraftState("draft", "active"),
    38: DraftState("draft-stream-ietf", "wg-doc"),
    41: DraftState("draft-stream-ietf", "wg-lc"),
    17: DraftState("draft-iesg", "rfcqueue"),
  ]

  private static func listed(_ name: String, rev: String = "03", states: [Int] = [1, 38])
    -> Datatracker.ListedDraft
  {
    Datatracker.ListedDraft(
      name: name, rev: rev, states: states.map { "/api/v1/doc/state/\($0)/" },
      stream: "/api/v1/name/streamname/ietf/")
  }

  private static func reading(rev: String = "03", obsoletes: [Int] = [9990], updates: [Int] = [])
    -> RevisionScan.Reading
  {
    RevisionScan.Reading(
      rev: rev, obsoletes: obsoletes, updates: updates,
      published: Date(timeIntervalSince1970: 1_780_000_000), group: "example",
      intendedStatus: "Proposed Standard")
  }

  private static func entry(
    stateIDs: [Int] = [1, 38], reading: RevisionScan.Reading = RevisionScanTests.reading()
  ) -> RevisionScan.Entry {
    RevisionScan.Entry(stateIDs: stateIDs, stage: .inGroup, stream: "ietf", reading: reading)
  }

  // MARK: What to read

  @Test func `a new draft is read in full`() {
    #expect(RevisionScan.work(for: Self.listed("draft-a"), previous: nil) == .full)
  }

  @Test func `a new revision is read in full`() {
    #expect(
      RevisionScan.work(for: Self.listed("draft-a", rev: "04"), previous: Self.entry()) == .full)
  }

  @Test func `a changed state alone reads only the record`() {
    #expect(
      RevisionScan.work(for: Self.listed("draft-a", states: [1, 41]), previous: Self.entry())
        == .record)
  }

  @Test func `an unchanged draft reads nothing`() {
    #expect(
      RevisionScan.work(for: Self.listed("draft-a", states: [38, 1]), previous: Self.entry())
        == .none)
  }

  // MARK: Merge

  @Test func `a draft that left the listing is dropped`() {
    let previous = RevisionScan(drafts: ["draft-gone": Self.entry()])
    let next = RevisionScan.next(
      adopted: [], states: Self.states, previous: previous, readings: [:])
    #expect(next.drafts.isEmpty)
  }

  @Test func `a read draft takes its new reading, revision and stage`() {
    let previous = RevisionScan(drafts: ["draft-a": Self.entry()])
    let next = RevisionScan.next(
      adopted: [Self.listed("draft-a", rev: "04", states: [1, 17])], states: Self.states,
      previous: previous, readings: ["draft-a": Self.reading(rev: "04", obsoletes: [9991])])
    let entry = next.drafts["draft-a"]
    #expect(entry?.reading.rev == "04")
    #expect(entry?.reading.obsoletes == [9991])
    #expect(entry?.stage == .rfcEditorQueue)
  }

  /// A new revision whose read failed keeps the old reading, whose revision no longer
  /// matches the listing, so the next run reads the draft again in full.
  @Test func `a failed read of a new revision keeps the old reading and is read again`() {
    let listed = Self.listed("draft-a", rev: "04")
    let next = RevisionScan.next(
      adopted: [listed], states: Self.states,
      previous: RevisionScan(drafts: ["draft-a": Self.entry()]), readings: [:])
    #expect(next.drafts["draft-a"]?.reading == Self.reading())
    #expect(RevisionScan.work(for: listed, previous: next.drafts["draft-a"]) == .full)
  }

  /// A failed record read keeps the old state IDs, which no longer match the listing,
  /// while the stage already follows today's states.
  @Test func `a failed record read keeps its old states and is read again`() {
    let listed = Self.listed("draft-a", states: [1, 17])
    let next = RevisionScan.next(
      adopted: [listed], states: Self.states,
      previous: RevisionScan(drafts: ["draft-a": Self.entry()]), readings: [:])
    #expect(next.drafts["draft-a"]?.stateIDs == [1, 38])
    #expect(next.drafts["draft-a"]?.stage == .rfcEditorQueue)
    #expect(RevisionScan.work(for: listed, previous: next.drafts["draft-a"]) == .record)
  }

  /// The case a filter on datatracker's `time` would lose: nothing about the draft
  /// changes, so nothing would select it again.
  @Test func `a draft that failed on its first read is read again`() {
    let first = RevisionScan.next(
      adopted: [Self.listed("draft-a")], states: Self.states, previous: nil, readings: [:])
    #expect(first.drafts["draft-a"] == nil)
    #expect(
      RevisionScan.work(for: Self.listed("draft-a"), previous: first.drafts["draft-a"]) == .full)
  }

  @Test func `an unchanged draft is kept, with its stage from today's states`() {
    let previous = RevisionScan(drafts: ["draft-a": Self.entry()])
    let next = RevisionScan.next(
      adopted: [Self.listed("draft-a")], states: Self.states, previous: previous, readings: [:])
    #expect(next.drafts["draft-a"]?.reading == Self.reading())
    #expect(next.drafts["draft-a"]?.stage == .inGroup)
  }

  // MARK: Projection

  @Test func `a draft that revises nothing stays in the record and out of the file`() {
    let scan = RevisionScan(drafts: ["draft-a": Self.entry(reading: Self.reading(obsoletes: []))])
    #expect(scan.revisions(generatedAt: .now).revisions.isEmpty)
  }

  @Test func `each relation becomes a revision under its RFC`() {
    let scan = RevisionScan(drafts: [
      "draft-a": Self.entry(reading: Self.reading(obsoletes: [9990], updates: [9991]))
    ])
    let file = scan.revisions(generatedAt: Date(timeIntervalSince1970: 1_790_000_000))
    #expect(file.revisions[9990]?.map(\.relation) == [.obsoletes])
    #expect(file.revisions[9991]?.map(\.relation) == [.updates])
    #expect(file.revisions[9990]?.first?.draft == "draft-a")
    #expect(file.revisions[9990]?.first?.revision == "03")
    #expect(file.generatedAt == Date(timeIntervalSince1970: 1_790_000_000))
  }

  // MARK: Shrink guard

  private static func file(rfcs count: Int) -> RFCRevisions {
    let revision = RFCRevisions.Revision(
      relation: .obsoletes, draft: "draft-a", revision: "01", published: .now, stream: "ietf",
      group: nil, intendedStatus: nil, stage: .inGroup)
    return RFCRevisions(
      generatedAt: .now,
      revisions: Dictionary(uniqueKeysWithValues: (0..<count).map { ($0, [revision]) }))
  }

  @Test func `the guard trips at more than half gone`() {
    #expect(
      !RevisionScan.mayPublish(
        Self.file(rfcs: 9), replacing: Self.file(rfcs: 20), allowShrink: false))
    #expect(
      RevisionScan.mayPublish(
        Self.file(rfcs: 10), replacing: Self.file(rfcs: 20), allowShrink: false))
  }

  @Test func `the guard does not trip below ten`() {
    #expect(
      RevisionScan.mayPublish(Self.file(rfcs: 1), replacing: Self.file(rfcs: 9), allowShrink: false)
    )
  }

  @Test func `the guard gives way when told to`() {
    #expect(
      RevisionScan.mayPublish(Self.file(rfcs: 0), replacing: Self.file(rfcs: 50), allowShrink: true)
    )
  }

  @Test func `a first run has nothing to shrink from`() {
    #expect(RevisionScan.mayPublish(Self.file(rfcs: 0), replacing: nil, allowShrink: false))
  }

  // MARK: Format

  @Test func `a scan record round-trips`() throws {
    let scan = RevisionScan(drafts: [
      "draft-a": Self.entry(), "draft-b": Self.entry(reading: Self.reading(obsoletes: [])),
    ])
    #expect(try RevisionScan.decode(scan.encoded()) == scan)
  }
}
