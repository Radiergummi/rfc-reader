import Foundation
import RFCKit
import RFCReaderKit
import Testing

/// What a working group's card says (#363): the group as datatracker describes it, and
/// what the index has of its RFCs.
@Suite("Working group summary")
struct WorkingGroupSummaryTests {
  private let httpbis = WorkingGroups.Group(
    acronym: "httpbis", name: "HTTP", type: "wg", state: "active",
    area: "Web and Internet Transport", chairs: ["Mark Nottingham", "Tommy Pauly"],
    listArchive: URL(string: "https://lists.w3.org/Archives/Public/ietf-http-wg/"),
    charter: "charter-ietf-httpbis")

  private let urnbis = WorkingGroups.Group(
    acronym: "urnbis", name: "Uniform Resource Names, Revised", type: "wg", state: "conclude",
    area: "Applications and Real-Time", chairs: [], listArchive: nil, charter: nil)

  private func rfc(_ number: Int, year: Int, group: String) -> RFCMetadata {
    RFCMetadata(
      id: .rfc(number), title: "RFC \(number)", date: PublicationDate(year: year, month: 1),
      workingGroup: group)
  }

  @Test func `an active group is named, placed and chaired`() {
    let summary = WorkingGroupSummary(
      acronym: "httpbis", group: httpbis,
      rfcs: [rfc(9110, year: 2022, group: "httpbis"), rfc(2616, year: 1999, group: "httpbis")])
    #expect(summary.title == "HTTP")
    #expect(summary.acronym == "HTTPBIS")
    #expect(summary.facts == ["Working Group", "Web and Internet Transport", "Active"])
    #expect(summary.chairs == ["Mark Nottingham", "Tommy Pauly"])
    #expect(summary.publications == "2 RFCs, 1999–2022")
    #expect(summary.links.map(\.title) == ["Datatracker", "Charter", "Mailing List Archive"])
  }

  /// A concluded group's chairs are not its chairs any more, and the file has none.
  @Test func `a concluded group says so, and names no chairs`() {
    let summary = WorkingGroupSummary(
      acronym: "urnbis", group: urnbis, rfcs: [rfc(8141, year: 2017, group: "urnbis")])
    #expect(summary.facts == ["Working Group", "Applications and Real-Time", "Concluded"])
    #expect(summary.chairs.isEmpty)
    #expect(summary.publications == "1 RFC, 2017")
    #expect(summary.links.map(\.title) == ["Datatracker"])
  }

  /// Before the file has ever been fetched, or for a group datatracker does not know:
  /// the acronym and what the index has, and nothing made up.
  @Test func `a group the file does not have shows what the index has`() {
    let summary = WorkingGroupSummary(
      acronym: "pppext",
      group: nil,
      rfcs: [rfc(1661, year: 1994, group: "pppext"), rfc(1662, year: 1994, group: "pppext")])
    #expect(summary.title == "PPPEXT")
    #expect(summary.acronym == nil)
    #expect(summary.facts.isEmpty)
    #expect(summary.chairs.isEmpty)
    #expect(summary.publications == "2 RFCs, 1994")
    #expect(summary.links.isEmpty)
  }

  /// A type or state datatracker adds later is shown as its slug, not dropped.
  @Test func `an unknown type and state are named by their slug`() {
    var group = httpbis
    group.type = "newkind"
    group.state = "paused"
    group.area = nil
    #expect(
      WorkingGroupSummary(acronym: "x", group: group, rfcs: []).facts == ["Newkind", "Paused"])
  }

  /// Datatracker allows a group with no type or state, which the file records as
  /// "unknown": that says nothing, so the card leaves both out.
  @Test func `a group with no type or state shows neither`() {
    var group = httpbis
    group.type = "unknown"
    group.state = "unknown"
    #expect(
      WorkingGroupSummary(acronym: "x", group: group, rfcs: []).facts == [
        "Web and Internet Transport"
      ])
  }

  @Test func `a group with no RFCs in the index says nothing about publications`() {
    #expect(WorkingGroupSummary(acronym: "x", group: httpbis, rfcs: []).publications == nil)
  }

  /// A group whose name is its acronym is not named twice.
  @Test func `a name that is the acronym is not repeated under it`() {
    var group = httpbis
    group.name = "IAB"
    #expect(WorkingGroupSummary(acronym: "iab", group: group, rfcs: []).acronym == nil)
  }
}
