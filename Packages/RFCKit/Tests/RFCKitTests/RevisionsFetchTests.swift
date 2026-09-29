import Foundation
import Testing

@testable import RFCKit

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

/// `revisions.json`, fetched through the client the rest of the app uses.
@Suite("Revisions fetch")
struct RevisionsFetchTests {
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

  private let file = RFCRevisions(
    generatedAt: Date(timeIntervalSince1970: 1_790_000_000), revisions: [:])

  @Test func `a published file is decoded, and its bytes come with it`() async throws {
    let data = try file.encoded()
    let fetched = try await RFCEditorClient(transport: Answer(status: 200, body: data))
      .fetchRevisions()
    #expect(fetched.revisions == file)
    #expect(fetched.data == data)
  }

  /// `--clobber` deletes the asset before it uploads the new one.
  @Test func `a missing file is an error, not an empty file`() async throws {
    await #expect(throws: RFCEditorClient.ClientError.self) {
      try await RFCEditorClient(transport: Answer(status: 404, body: Data())).fetchRevisions()
    }
  }

  @Test func `a file of an unknown version is an error`() async throws {
    let json = String(decoding: try file.encoded(), as: UTF8.self)
      .replacingOccurrences(of: "\"version\" : 1", with: "\"version\" : 2")
    await #expect(throws: RFCRevisions.VersionError.unknown(2)) {
      try await RFCEditorClient(transport: Answer(status: 200, body: Data(json.utf8)))
        .fetchRevisions()
    }
  }

  @Test func `the file is fetched from the revisions release`() {
    #expect(
      RFCEditorEndpoints.revisions.absoluteString
        == "https://github.com/Radiergummi/rfc-reader/releases/download/revisions/revisions.json")
  }
}
