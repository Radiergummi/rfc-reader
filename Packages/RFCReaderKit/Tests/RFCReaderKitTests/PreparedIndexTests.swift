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
    RFCMetadata(
      id: .rfc(number), title: title, date: PublicationDate(year: 2020), workingGroup: group)
  }

  @Test func theWorkingGroupsAreTheTwelveWithTheMostRFCs() {
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
  @Test func workingGroupsWithEqualCountsAreOrderedByName() {
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

  @Test func theSearchIsOverTheSameIndex() {
    let index = RFCIndex(rfcs: [
      rfc(9110, title: "HTTP Semantics"), rfc(791, title: "Internet Protocol"),
    ])

    let prepared = PreparedIndex(index: index)

    #expect(prepared.index.rfcs.map(\.number) == [791, 9110])
    #expect(prepared.search.search("semantics").map(\.rfc.number) == [9110])
  }

  @Test func parsingPreparesWhatItParsed() throws {
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
