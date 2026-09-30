import Foundation
import RFCKit
import Testing

@testable import RFCReaderKit

/// What the reader says about a failed load depends on what failed (#125): every
/// failure used to read as a lost connection, under the same Wi-Fi symbol.
@Suite("Load failure")
struct LoadFailureTests {
  private let url = URL(string: "https://www.rfc-editor.org/rfc/rfc9110.xml")!

  @Test(arguments: [
    URLError.Code.notConnectedToInternet, .networkConnectionLost, .timedOut,
    .cannotFindHost, .cannotConnectToHost, .dataNotAllowed,
  ])
  func `a lost connection is offline`(code: URLError.Code) {
    #expect(LoadFailure(error: URLError(code)).kind == .offline)
  }

  @Test func `a document the RFC Editor does not have is not found`() {
    let error = RFCEditorClient.ClientError.notFound(.rfc(9110))
    #expect(LoadFailure(error: error).kind == .notFound)
  }

  @Test(arguments: [500, 502, 503, 504])
  func `a server error is the server's`(status: Int) {
    let error = RFCEditorClient.ClientError.httpStatus(status, url)
    #expect(LoadFailure(error: error).kind == .server)
  }

  @Test func `a client error is not the server's`() {
    #expect(LoadFailure(error: RFCEditorClient.ClientError.httpStatus(403, url)).kind == .other)
  }

  /// XML that does not parse, with no text to fall back to: the document is there,
  /// and this reader cannot read it.
  @Test func `a document that does not parse is unreadable`() {
    let syntax = XMLSyntaxError(line: 1, column: 2, message: "unexpected end")
    #expect(LoadFailure(error: RFCXMLParser.ParseError.malformed(syntax)).kind == .unreadable)
    #expect(
      LoadFailure(error: RFCXMLParser.ParseError.notAnRFC(rootElement: "html")).kind == .unreadable)
    let decoding = RFCEditorClient.ClientError.decoding(context: "rfc9110.xml", underlying: syntax)
    #expect(LoadFailure(error: decoding).kind == .unreadable)
  }

  @Test func `anything else is a failure of its own`() {
    struct Unexpected: Error {}
    #expect(LoadFailure(error: Unexpected()).kind == .other)
    #expect(LoadFailure(error: URLError(.badServerResponse)).kind == .other)
  }

  /// Each kind shows as itself: only a lost connection has the Wi-Fi symbol, and
  /// each says what to do about it. The symbol is one SF Symbols has, since a name
  /// it lacks draws nothing.
  @Test func `each kind has a symbol and a suggestion of its own`() {
    let kinds = LoadFailure.Kind.allCases
    #expect(Set(kinds.map(\.symbol)).count == kinds.count)
    #expect(kinds.filter { $0.symbol.hasPrefix("wifi") } == [.offline])
    #expect(kinds.allSatisfy { PlatformImage(systemName: $0.symbol) != nil })
    #expect(kinds.allSatisfy { !$0.recoverySuggestion.isEmpty })
  }
}
