import Foundation
import Testing

@testable import RFCKit

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

/// A draft's revisions from Datatracker, and its text from the IETF's archive (#728).
@Suite("Draft fetch")
struct DraftFetchTests {
  /// Answers each URL it has a body for, with the type the archive and Datatracker
  /// serve it as, and 404 for every other; and keeps the URLs it was asked for.
  private final class Archive: HTTPTransport, @unchecked Sendable {
    private let bodies: [String: Data]
    private let lock = NSLock()
    private var asked: [String] = []

    init(_ bodies: [String: Data]) {
      self.bodies = bodies
    }

    var requested: [String] { lock.withLock { asked } }

    func response(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
      let url = request.url!
      lock.withLock { asked.append(url.absoluteString) }
      guard let body = bodies[url.absoluteString] else {
        return (Data(), HTTPURLResponse.served(from: url, statusCode: 404))
      }
      let type =
        switch url.pathExtension {
        case "json": "application/json"
        case "xml": "text/xml; charset=utf-8"
        default: "text/plain; charset=utf-8"
        }
      return (
        body,
        HTTPURLResponse(
          url: url, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": type])!
      )
    }
  }

  private static let draft = DraftID(parsing: "draft-ietf-example-protocol-03")!

  /// Datatracker's `doc.json`, in its shape, with the history of a draft that
  /// replaced another and was then published.
  private static let info = Data(
    """
    {
      "name": "draft-ietf-example-protocol",
      "rev": "03",
      "title": "An Example Protocol",
      "state": "RFC",
      "rev_history": [
        {"name": "draft-someone-example", "rev": "00", "published": "2024-01-02T10:00:00+00:00"},
        {"name": "draft-ietf-example-protocol", "rev": "00", "published": "2024-05-01T10:00:00+00:00"},
        {"name": "draft-ietf-example-protocol", "rev": "01", "published": "2024-09-01T10:00:00+00:00"},
        {"name": "draft-ietf-example-protocol", "rev": "02", "published": "2025-01-01T10:00:00+00:00"},
        {"name": "draft-ietf-example-protocol", "rev": "03", "published": "2025-04-01T10:00:00+00:00"},
        {"name": "rfc9999", "rev": "rfc9999", "published": "2025-10-01T10:00:00+00:00"}
      ]
    }
    """.utf8)

  @Test func `Datatracker's description lists the draft's own revisions and its RFC`() throws {
    let info = try DraftInfo.decode(Self.info)
    #expect(info.name == "draft-ietf-example-protocol")
    #expect(info.title == "An Example Protocol")
    #expect(info.newestRevision == "03")
    #expect(info.newest == Self.draft)
    #expect(info.state == "RFC")
    #expect(info.revisions.map(\.revision) == ["00", "01", "02", "03"])
    #expect(info.revisions.first?.published == Date(timeIntervalSince1970: 1_714_557_600))
    #expect(info.publishedAs == .rfc(9999))
  }

  @Test func `a draft never published names no RFC`() throws {
    let json = String(decoding: Self.info, as: UTF8.self)
      .replacingOccurrences(
        of: #"{"name": "rfc9999", "rev": "rfc9999""#,
        with: #"{"name": "draft-ietf-example-successor", "rev": "00""#)
    let info = try DraftInfo.decode(Data(json.utf8))
    #expect(info.publishedAs == nil)
    #expect(info.revisions.count == 4)
  }

  @Test func `the description is asked of Datatracker, by the draft's name alone`() async throws {
    let archive = Archive([
      "https://datatracker.ietf.org/doc/draft-ietf-example-protocol/doc.json": Self.info
    ])
    let fetched = try await RFCEditorClient(transport: archive).fetchDraftInfo(Self.draft)
    #expect(fetched.info.newestRevision == "03")
    #expect(fetched.data == Self.info)
  }

  @Test func `a draft Datatracker does not know is not found`() async throws {
    let client = RFCEditorClient(transport: Archive([:]))
    await #expect(throws: RFCEditorClient.ClientError.self) {
      try await client.fetchDraftInfo(Self.draft)
    }
    do {
      _ = try await client.fetchDraftInfo(Self.draft)
    } catch RFCEditorClient.ClientError.draftNotFound(let id) {
      #expect(id == Self.draft)
    }
  }

  /// Any RFC's XML stands in for a draft's: what is pinned is which file is asked
  /// for, and that its header names the revision.
  @Test func `a revision is read from its XML where the archive has it`() async throws {
    let xml = try Fixtures.data("rfc9220.xml")
    let archive = Archive([
      "https://www.ietf.org/archive/id/draft-ietf-example-protocol-03.xml": xml
    ])
    let fetched = try await RFCEditorClient(transport: archive).fetchDraft(Self.draft)
    #expect(fetched.format == .xml)
    #expect(fetched.data == xml)
    #expect(fetched.document.header.draftName == "draft-ietf-example-protocol-03")
    #expect(archive.requested == [
      "https://www.ietf.org/archive/id/draft-ietf-example-protocol-03.xml"
    ])
  }

  @Test func `a revision submitted as text is read from its text`() async throws {
    let text = try Fixtures.data("rfc2119.txt")
    let archive = Archive([
      "https://www.ietf.org/archive/id/draft-ietf-example-protocol-03.txt": text
    ])
    let fetched = try await RFCEditorClient(transport: archive).fetchDraft(Self.draft)
    #expect(fetched.format == .text)
    #expect(fetched.document.header.draftName == "draft-ietf-example-protocol-03")
    #expect(fetched.xmlParseFailure == nil)
    #expect(archive.requested == [
      "https://www.ietf.org/archive/id/draft-ietf-example-protocol-03.xml",
      "https://www.ietf.org/archive/id/draft-ietf-example-protocol-03.txt",
    ])
  }

  @Test func `a revision the archive does not have is not found`() async throws {
    do {
      _ = try await RFCEditorClient(transport: Archive([:])).fetchDraft(Self.draft)
      Issue.record("fetched a revision that is not there")
    } catch RFCEditorClient.ClientError.draftNotFound(let id) {
      #expect(id == Self.draft)
    }
  }

  @Test func `the endpoints`() {
    #expect(
      RFCEditorEndpoints.draftInfo("draft-ietf-example-protocol").absoluteString
        == "https://datatracker.ietf.org/doc/draft-ietf-example-protocol/doc.json")
    #expect(
      RFCEditorEndpoints.draft(Self.draft, format: .text).absoluteString
        == "https://www.ietf.org/archive/id/draft-ietf-example-protocol-03.txt")
  }
}
