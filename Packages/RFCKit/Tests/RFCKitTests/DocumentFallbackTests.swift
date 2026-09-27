import Foundation
import Testing

@testable import RFCKit

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

/// When the client falls back from a document's XML to its plain text (#125): only
/// when there is no XML. A cancelled load, a server error or a network failure is
/// the real error, not a reason to start a second request.
@Suite("Client: document fallback")
struct DocumentFallbackTests {
  private enum Answer: Sendable {
    case body(Data)
    case status(Int)
    case failure(any Error)
  }

  /// Answers each format as scripted, and records what was asked for.
  private final class Transport: HTTPTransport, @unchecked Sendable {
    private let answers: [String: Answer]
    private let lock = NSLock()
    private var asked: [String] = []

    init(xml: Answer? = nil, text: Answer? = nil) {
      var answers: [String: Answer] = [:]
      answers["xml"] = xml
      answers["txt"] = text
      self.answers = answers
    }

    var requested: [String] {
      lock.withLock { asked }
    }

    func data(for url: URL) async throws -> (Data, HTTPURLResponse) {
      lock.withLock { asked.append(url.pathExtension) }
      let answer = answers[url.pathExtension] ?? .status(404)
      switch answer {
      case .body(let data):
        return (
          data, HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
        )
      case .status(let status):
        return (
          Data(),
          HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!
        )
      case .failure(let error):
        throw error
      }
    }
  }

  @Test func `a document with XML is read from it, and its text is not fetched`() async throws {
    let transport = Transport(xml: .body(try Fixtures.data("rfc8999.xml")))
    let fetched = try await RFCEditorClient(transport: transport).fetchPreferredDocument(.rfc(8999))
    #expect(fetched.format == .xml)
    #expect(fetched.document.source == .xml)
    #expect(fetched.xmlParseFailure == nil)
    #expect(transport.requested == ["xml"])
  }

  @Test func `no XML falls back to the text`() async throws {
    let transport = Transport(xml: .status(404), text: .body(try Fixtures.data("rfc1149.txt")))
    let fetched = try await RFCEditorClient(transport: transport).fetchPreferredDocument(.rfc(1149))
    #expect(fetched.format == .text)
    #expect(fetched.document.source == .text)
    #expect(transport.requested == ["xml", "txt"])
  }

  /// The index says which formats exist; one without XML is not asked for it.
  @Test func `a document the index lists without XML is fetched as text alone`() async throws {
    let transport = Transport(text: .body(try Fixtures.data("rfc1149.txt")))
    _ = try await RFCEditorClient(transport: transport)
      .fetchPreferredDocument(.rfc(1149), availableFormats: [.text, .pdf])
    #expect(transport.requested == ["txt"])
  }

  @Test func `a server error is the error, and no text is fetched`() async throws {
    let transport = Transport(xml: .status(503), text: .body(Data("unused".utf8)))
    await #expect(throws: RFCEditorClient.ClientError.self) {
      _ = try await RFCEditorClient(transport: transport).fetchPreferredDocument(.rfc(9110))
    }
    #expect(transport.requested == ["xml"])
  }

  @Test func `a network failure is the error, and no text is fetched`() async throws {
    let transport = Transport(xml: .failure(URLError(.notConnectedToInternet)), text: .body(Data()))
    await #expect(throws: URLError.self) {
      _ = try await RFCEditorClient(transport: transport).fetchPreferredDocument(.rfc(9110))
    }
    #expect(transport.requested == ["xml"])
  }

  /// A cancelled load stops; it does not go on to ask for the text.
  @Test func `a cancelled load is cancelled, and no text is fetched`() async throws {
    let transport = Transport(xml: .failure(CancellationError()), text: .body(Data()))
    await #expect(throws: CancellationError.self) {
      _ = try await RFCEditorClient(transport: transport).fetchPreferredDocument(.rfc(9110))
    }
    #expect(transport.requested == ["xml"])
  }

  /// XML that exists but does not parse is a parser bug worth knowing about. The
  /// document is still read from its text, and the failure comes back with it
  /// rather than being indistinguishable from there being no XML.
  @Test func `unparseable XML is read from the text, its failure kept`() async throws {
    let transport = Transport(
      xml: .body(Data("<rfc><front>".utf8)), text: .body(try Fixtures.data("rfc1149.txt")))
    let fetched = try await RFCEditorClient(transport: transport).fetchPreferredDocument(.rfc(1149))
    #expect(fetched.format == .text)
    #expect(fetched.xmlParseFailure != nil)
    #expect(transport.requested == ["xml", "txt"])
  }

  @Test func `the index is fetched through the client`() async throws {
    let transport = Transport(xml: .body(Data("<rfc-index/>".utf8)))
    #expect(
      try await RFCEditorClient(transport: transport).fetchIndexData() == Data("<rfc-index/>".utf8))

    let failing = Transport(xml: .status(500))
    await #expect(throws: RFCEditorClient.ClientError.self) {
      _ = try await RFCEditorClient(transport: failing).fetchIndexData()
    }
  }
}
