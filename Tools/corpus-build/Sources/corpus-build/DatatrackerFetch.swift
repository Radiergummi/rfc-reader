import Foundation
import RFCCorpusKit
import RFCKit

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

/// How the commands that read datatracker ask it: one request at a time, with a pause
/// between them, through this tool's transport.
enum DatatrackerFetch {
  private static let pause = Duration.milliseconds(250)

  /// Every page, following `meta.next` until there is none. A failure on any page fails
  /// the run: a partial listing would drop everything on the missing pages.
  static func pages<Page: Datatracker.Page>(from first: URL, as type: Page.Type) async throws
    -> [Page]
  {
    var pages: [Page] = []
    var url: URL? = first
    while let current = url {
      let page = try Datatracker.decoder().decode(Page.self, from: try await fetch(current))
      pages.append(page)
      url = Datatracker.next(page.meta.next)
    }
    return pages
  }

  /// Through the transport `fetch` uses too: this tool's User-Agent, and a bounded
  /// retry of what can pass.
  private static let transport = RetryingTransport(
    URLSessionTransport(userAgent: RetryingTransport.userAgent))

  static func fetch(_ url: URL) async throws -> Data {
    try await Task.sleep(for: pause)
    let (data, response) = try await transport.response(for: URLRequest(url: url))
    guard (200..<300).contains(response.statusCode) else {
      throw RFCEditorClient.ClientError.httpStatus(response.statusCode, url)
    }
    return data
  }
}
