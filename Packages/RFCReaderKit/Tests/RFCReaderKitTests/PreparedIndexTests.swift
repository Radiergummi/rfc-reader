import Foundation
import RFCKit
import Testing

@testable import RFCReaderKit

/// Everything the library derives from a freshly parsed index, built in one value so
/// it can be made off the main actor (#124). Parsing the 14 MB index took about a
/// second on the main actor, and building the search and the sidebar's working groups
/// after it held it longer still.
@Suite("Prepared index")
struct PreparedIndexTests {
  private func rfc(_ number: Int, title: String = "Title", group: String? = nil) -> RFCMetadata {
    Fixtures.metadata(number, title: title, workingGroup: group)
  }

  @Test func `the working groups are the twelve with the most RFCs`() {
    var rfcs = [rfc(1, group: "httpbis"), rfc(2, group: "httpbis"), rfc(3, group: "httpbis")]
    rfcs += [rfc(4, group: "tls"), rfc(5, group: "tls")]
    rfcs += (0..<14).map { rfc(100 + $0, group: "group\($0)") }
    rfcs.append(rfc(200))

    let prepared = PreparedIndex(index: RFCIndex(rfcs: rfcs))

    #expect(prepared.topWorkingGroups.count == 12)
    #expect(Array(prepared.topWorkingGroups.prefix(2)) == ["httpbis", "tls"])
  }

  /// Equal counts are ordered by name. By count alone, ties came out in dictionary
  /// order, which Swift randomizes per process: the sidebar reordered from launch to
  /// launch, and which of the tied groups made the cut changed with it.
  @Test func `working groups with equal counts are ordered by name`() {
    var rfcs = [rfc(1, group: "httpbis"), rfc(2, group: "httpbis"), rfc(3, group: "httpbis")]
    rfcs += [rfc(4, group: "tls"), rfc(5, group: "tls")]
    rfcs += (0..<14).map { rfc(100 + $0, group: "group\($0)") }

    let prepared = PreparedIndex(index: RFCIndex(rfcs: rfcs))

    #expect(
      prepared.topWorkingGroups == [
        "httpbis", "tls", "group0", "group1", "group10", "group11", "group12", "group13",
        "group2", "group3", "group4", "group5",
      ])
  }

  /// The sidebar's counts (#344), for every filter the index alone decides.
  @Test func `every filter the index decides is counted`() {
    let index = RFCIndex(rfcs: [
      Fixtures.metadata(
        9110, title: "HTTP Semantics", year: 2022, currentStatus: .internetStandard,
        stream: .ietf, workingGroup: "httpbis"),
      Fixtures.metadata(
        9111, title: "HTTP Caching", year: 2022, currentStatus: .internetStandard,
        stream: .ietf, workingGroup: "httpbis"),
      Fixtures.metadata(
        2119, title: "Key words", year: 1997, currentStatus: .bestCurrentPractice, stream: .ietf),
      Fixtures.metadata(
        9000, title: "QUIC", year: 2021, currentStatus: .proposedStandard, stream: .ietf,
        workingGroup: "quic"),
      Fixtures.metadata(
        1149, title: "Avian carriers", year: 1990, currentStatus: .experimental, stream: .legacy),
    ])

    let counts = PreparedIndex(index: index).counts

    #expect(counts[.all] == 5)
    #expect(counts[.standards] == 2)
    #expect(counts[.bestCurrentPractice] == 1)
    #expect(counts[.stream(.ietf)] == 4)
    #expect(counts[.stream(.legacy)] == 1)
    #expect(counts[.workingGroup("httpbis")] == 2)
    #expect(counts[.workingGroup("quic")] == 1)
  }

  /// No entry rather than a zero, and none for the filters the reader's own data
  /// decides: those the index cannot count.
  @Test func `a filter nothing is in has no count`() {
    let index = RFCIndex(rfcs: [rfc(9110, group: "httpbis")])

    let counts = PreparedIndex(index: index).counts

    #expect(counts[.stream(.iab)] == nil)
    #expect(counts[.bookmarks] == nil)
    #expect(counts[.recent] == nil)
  }

  @Test func `the search is over the same index`() {
    let index = RFCIndex(rfcs: [
      rfc(9110, title: "HTTP Semantics"), rfc(791, title: "Internet Protocol"),
    ])

    let prepared = PreparedIndex(index: index)

    #expect(prepared.index.rfcs.map(\.number) == [791, 9110])
    #expect(prepared.search.search("semantics").map(\.rfc.number) == [9110])
  }

  @Test func `parsing prepares what it parsed`() throws {
    let data = Data(
      """
      <?xml version="1.0" encoding="UTF-8"?>
      <rfc-index xmlns="https://www.rfc-editor.org/rfc-index">
        <rfc-entry>
          <doc-id>RFC9110</doc-id>
          <title>HTTP Semantics</title>
          <date><month>June</month><year>2022</year></date>
          <wg_acronym>httpbis</wg_acronym>
        </rfc-entry>
      </rfc-index>
      """.utf8)

    let prepared = try PreparedIndex.parse(data)

    #expect(prepared.index[9110]?.title == "HTTP Semantics")
    #expect(prepared.topWorkingGroups == ["httpbis"])
  }
}
