import Foundation
import Testing

@testable import RFCKit

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

/// `groups.json` (#363), which `corpus-build groups` writes and the app reads: one
/// format, so both sides go through the same coders.
@Suite("Working groups file")
struct WorkingGroupsTests {
  private let sample = WorkingGroups(
    generatedAt: Date(timeIntervalSince1970: 1_790_000_000),
    groups: [
      WorkingGroups.Group(
        acronym: "httpbis", name: "HTTP", type: "wg", state: "active",
        area: "Web and Internet Transport", chairs: ["Mark Nottingham", "Tommy Pauly"],
        listArchive: URL(string: "https://lists.w3.org/Archives/Public/ietf-http-wg/"),
        charter: "charter-ietf-httpbis")
    ])

  @Test func `a file round-trips through its own coders`() throws {
    #expect(try WorkingGroups.decode(sample.encoded()) == sample)
  }

  /// The index writes an acronym as the group's chair wrote it on the document,
  /// "HTTPBIS" as often as "httpbis"; datatracker keeps them in lower case.
  @Test func `a group is found by its acronym in any case`() {
    #expect(sample.group("HTTPBIS")?.name == "HTTP")
    #expect(sample.group("httpbis")?.name == "HTTP")
    #expect(sample.group("quic") == nil)
  }

  @Test func `a file of an unknown version is refused`() throws {
    let json = String(decoding: try sample.encoded(), as: UTF8.self)
      .replacingOccurrences(of: "\"version\" : 1", with: "\"version\" : 2")
    #expect(throws: WorkingGroups.VersionError.unknown(2)) {
      try WorkingGroups.decode(Data(json.utf8))
    }
  }

  @Test func `a group's pages are on datatracker`() throws {
    let group = try #require(sample.group("httpbis"))
    #expect(group.datatracker.absoluteString == "https://datatracker.ietf.org/group/httpbis/about/")
    #expect(
      group.charterPage?.absoluteString
        == "https://datatracker.ietf.org/doc/charter-ietf-httpbis/")
  }

  /// One answer for every request.
  private struct Answer: HTTPTransport {
    let status: Int
    let body: Data

    func response(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
      (
        body,
        HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
      )
    }
  }

  @Test func `a published file is fetched and decoded, and its bytes come with it`() async throws {
    let data = try sample.encoded()
    let fetched = try await RFCEditorClient(transport: Answer(status: 200, body: data))
      .fetchWorkingGroups()
    #expect(fetched.groups == sample)
    #expect(fetched.data == data)
  }

  @Test func `the file is fetched from the revisions release`() {
    #expect(
      RFCEditorEndpoints.workingGroups.absoluteString
        == "https://github.com/Radiergummi/rfc-reader/releases/download/revisions/groups.json")
  }
}
