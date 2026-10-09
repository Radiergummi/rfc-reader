import Foundation
import Testing

@testable import RFCKit

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

/// When the client falls back from a document's XML to its plain text (#125): only
/// when there is no XML. A canceled load, a server error or a network failure is
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

    func response(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
      let url = request.url!
      lock.withLock { asked.append(url.pathExtension) }
      let answer = answers[url.pathExtension] ?? .status(404)
      switch answer {
      case .body(let data):
        return (
          data, HTTPURLResponse.served(from: url, statusCode: 200)
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

  /// The text's header is the index entry's where the caller has it, as a converted
  /// document's is (#767): its authors, here ones the title page doesn't have.
  @Test func `the text fallback takes its header from the index entry`() async throws {
    let transport = Transport(xml: .status(404), text: .body(try Fixtures.data("rfc1149.txt")))
    var entry = try #require(try Fixtures.sampleIndex()[1149])
    entry.authors = [Author(name: "B. Second", role: .editor), Author(name: "A. First")]
    let fetched = try await RFCEditorClient(transport: transport)
      .fetchPreferredDocument(.rfc(1149), entry: entry)
    #expect(fetched.document.header.authors == entry.authors)
    #expect(fetched.document.header.date == entry.date)
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

  /// A canceled load stops; it does not go on to ask for the text.
  @Test func `a canceled load is canceled, and no text is fetched`() async throws {
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

  /// Unparseable XML and no text: the parse failure is the reason the document
  /// cannot be read, not the text's 404, which would hide the parser bug.
  @Test func `unparseable XML with no text fails with the parse error`() async throws {
    let transport = Transport(xml: .body(Data("<rfc><front>".utf8)), text: .status(404))
    do {
      _ = try await RFCEditorClient(transport: transport).fetchPreferredDocument(.rfc(9110))
      Issue.record("expected the parse failure")
    } catch let error as RFCEditorClient.ClientError {
      Issue.record("the text's \(error), not the parse failure")
    } catch {
      // The parser's own error.
    }
    #expect(transport.requested == ["xml", "txt"])
  }

  @Test func `the index is fetched through the client`() async throws {
    let transport = Transport(xml: .body(Data("<rfc-index/>".utf8)))
    let fetched = try await RFCEditorClient(transport: transport)
      .fetchIndexData(unlessMatching: nil, onExpensiveNetworks: true)
    #expect(fetched == .changed(Data("<rfc-index/>".utf8), nil))

    let failing = Transport(xml: .status(500))
    await #expect(throws: RFCEditorClient.ClientError.self) {
      _ = try await RFCEditorClient(transport: failing)
        .fetchIndexData(unlessMatching: nil, onExpensiveNetworks: true)
    }
  }
}
