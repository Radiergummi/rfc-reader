import Foundation
import RFCKit
import Testing

@testable import RFCReaderKit

/// What the reader says about a failed load depends on what failed (#125): every
/// failure used to read as a lost connection, under the same Wi-Fi symbol.
@Suite("Load failure")
struct LoadFailureTests {
  private let url = URL(string: "https://www.rfc-editor.org/rfc/rfc9110.xml")!

  /// Only the device's own connection: a host that does not answer is the server's.
  @Test(arguments: [URLError.Code.notConnectedToInternet, .networkConnectionLost])
  func `a lost connection is offline`(code: URLError.Code) {
    #expect(LoadFailure(error: URLError(code)).kind == .offline)
  }

  /// Cellular data turned off, for the app or while roaming, is a setting to change
  /// rather than a connection to check (#759).
  @Test(arguments: [URLError.Code.dataNotAllowed, .internationalRoamingOff])
  func `cellular data turned off is cellular denied`(code: URLError.Code) {
    #expect(LoadFailure(error: URLError(code)).kind == .cellularDenied)
  }

  /// What a network's login page or a proxy does to a TLS connection (#759).
  @Test(arguments: [
    URLError.Code.secureConnectionFailed, .serverCertificateHasBadDate,
    .serverCertificateUntrusted, .serverCertificateHasUnknownRoot,
    .serverCertificateNotYetValid, .clientCertificateRejected, .clientCertificateRequired,
  ])
  func `a TLS failure is a secure connection failure`(code: URLError.Code) {
    #expect(LoadFailure(error: URLError(code)).kind == .secureConnection)
  }

  @Test(arguments: [URLError.Code.timedOut, .cannotFindHost, .cannotConnectToHost])
  func `a host that does not answer is the server's`(code: URLError.Code) {
    #expect(LoadFailure(error: URLError(code)).kind == .server)
  }

  @Test func `a document the RFC Editor does not have is not found`() {
    let error = RFCEditorClient.ClientError.notFound(.rfc(9110))
    #expect(LoadFailure(error: error).kind == .notFound)
  }

  @Test(arguments: [429, 500, 502, 503, 504])
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
      LoadFailure(error: RFCXMLParser.ParseError.notAnRFC(rootElement: "reference")).kind
        == .unreadable)
    let decoding = RFCEditorClient.ClientError.decoding(context: "rfc9110.xml", underlying: syntax)
    #expect(LoadFailure(error: decoding).kind == .unreadable)
  }

  /// An HTML page where the XML should be is an error page, or a captive portal's.
  @Test func `a web page instead of the document is the server's`() {
    let error = RFCXMLParser.ParseError.notAnRFC(rootElement: "html")
    #expect(LoadFailure(error: error).kind == .server)
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
    #expect(kinds.allSatisfy { !$0.recoverySuggestion(for: .document, locale: .english).isEmpty })
  }

  /// The original text is missing when the RFC has no plain-text version, which is
  /// not the RFC Editor lacking the document; any other failure reads the same.
  @Test func `the original text has its own not found`() {
    for kind in LoadFailure.Kind.allCases {
      let document = kind.recoverySuggestion(for: .document, locale: .english)
      let originalText = kind.recoverySuggestion(for: .originalText, locale: .english)
      #expect((document == originalText) == (kind != .notFound))
    }
  }

  /// The index is not a document: what its status line says about a failure never
  /// sends the reader to a document's page, and a failure of the connection reads
  /// as it does for a document (#759).
  /// An index that does not parse has its own words, rather than "try again in a
  /// moment", which would not help.
  @Test func `an index that does not parse is unreadable`() {
    let syntax = XMLSyntaxError(line: 1, column: 2, message: "unexpected end")
    #expect(LoadFailure(error: RFCIndexParser.ParseError.malformed(syntax)).kind == .unreadable)
  }

  @Test func `the index is not a document`() {
    let ownWording: Set<LoadFailure.Kind> = [.notFound, .unreadable, .other]
    for kind in LoadFailure.Kind.allCases {
      let document = kind.recoverySuggestion(for: .document, locale: .english)
      let index = kind.recoverySuggestion(for: .index, locale: .english)
      #expect((document == index) == !ownWording.contains(kind))
      #expect(!index.contains("document"))
    }
  }
}
