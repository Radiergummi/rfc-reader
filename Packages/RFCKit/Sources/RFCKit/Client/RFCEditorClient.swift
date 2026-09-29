import Foundation

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

/// Abstraction over `URLSession` so the client can be tested without a network.
public protocol HTTPTransport: Sendable {
  func data(for url: URL) async throws -> (Data, HTTPURLResponse)
}

/// The transport over a `URLSession`, asking for the formats the RFC Editor serves.
public struct URLSessionTransport: HTTPTransport {
  private let session: URLSession
  private let userAgent: String?

  /// `userAgent` names a client that fetches in bulk, so the server's operators can
  /// tell who it is; nil keeps the session's own.
  public init(session: URLSession = .shared, userAgent: String? = nil) {
    self.session = session
    self.userAgent = userAgent
  }

  public func data(for url: URL) async throws -> (Data, HTTPURLResponse) {
    var request = URLRequest(url: url)
    request.setValue("application/xml, text/plain, application/json", forHTTPHeaderField: "Accept")
    if let userAgent { request.setValue(userAgent, forHTTPHeaderField: "User-Agent") }
    let (data, response) = try await session.data(for: request)
    guard let http = response as? HTTPURLResponse else {
      throw RFCEditorClient.ClientError.invalidResponse(url)
    }
    return (data, http)
  }
}

/// Fetches and parses documents from the RFC Editor.
///
/// Callers decide about caching; this type only knows how to get bytes and turn them
/// into models. It holds nothing but its transport, so it is a value any task can
/// share, and a method that parses is `@concurrent`: a large document is parsed off
/// the caller's actor, and two fetches parse side by side rather than in turn.
public struct RFCEditorClient: Sendable {
  public enum ClientError: Error, Sendable {
    case invalidResponse(URL)
    case httpStatus(Int, URL)
    case notFound(DocumentID)
    /// The body at the URL did not decode; the decoder's own error.
    case decoding(URL, any Error)
  }

  private let transport: any HTTPTransport

  public init(transport: any HTTPTransport = URLSessionTransport()) {
    self.transport = transport
  }

  @concurrent
  public func fetchIndex() async throws -> RFCIndex {
    let data = try await fetch(RFCEditorEndpoints.index)
    do {
      return try RFCIndexParser.parse(data)
    } catch {
      throw ClientError.decoding(RFCEditorEndpoints.index, error)
    }
  }

  /// Raw bytes of a document in the given format, for caching.
  public func fetchDocumentData(_ id: DocumentID, format: FileFormat) async throws -> Data {
    try await fetch(RFCEditorEndpoints.document(id, format: format), notFoundAs: id)
  }

  /// Parses a document, preferring the semantic XML source when available and
  /// falling back to the plain-text rendering otherwise.
  @concurrent
  public func fetchDocument(_ id: DocumentID, availableFormats: [FileFormat]? = nil) async throws
    -> RFCDocument
  {
    try await fetchPreferredDocument(id, availableFormats: availableFormats).document
  }

  /// A document fetched in the best format it has, with the bytes it came as.
  public struct FetchedDocument: Sendable {
    public let data: Data
    public let format: FileFormat
    public let document: RFCDocument
    /// Why the XML was not used, when it was there but did not parse: a parser bug
    /// worth knowing about, and not the same thing as there being no XML.
    public let xmlParseFailure: (any Error)?
  }

  /// The XML where the index lists it, the plain text otherwise (#125).
  ///
  /// The text is fetched only when there is no XML: a 404 for it. A canceled
  /// load, a server error or a network failure is the error, and asking for the
  /// text after one would start a second request and report *its* failure instead.
  /// XML that is there but does not parse falls back to the text too, so the
  /// document stays readable, and the parse error comes back beside it.
  @concurrent
  public func fetchPreferredDocument(_ id: DocumentID, availableFormats: [FileFormat]? = nil)
    async throws -> FetchedDocument
  {
    var xmlParseFailure: (any Error)?
    if availableFormats?.contains(.xml) ?? true {
      do {
        let data = try await fetchDocumentData(id, format: .xml)
        do {
          return FetchedDocument(
            data: data, format: .xml, document: try RFCXMLParser.parse(data), xmlParseFailure: nil)
        } catch {
          xmlParseFailure = error
        }
      } catch ClientError.notFound {
        // No XML: the text is all there is.
      }
    }
    let data: Data
    do {
      data = try await fetchDocumentData(id, format: .text)
    } catch ClientError.notFound where xmlParseFailure != nil {
      // No text to fall back to: the XML that would not parse is why the document
      // cannot be read, and the text's 404 would hide the parser bug.
      throw xmlParseFailure ?? ClientError.notFound(id)
    }
    return FetchedDocument(
      data: data, format: .text, document: LegacyTextParser.parse(data),
      xmlParseFailure: xmlParseFailure)
  }

  /// The RFC index as bytes, so the caller can both parse and keep it.
  public func fetchIndexData() async throws -> Data {
    try await fetch(RFCEditorEndpoints.index)
  }

  @concurrent
  public func fetchRecent() async throws -> [RecentRFC] {
    let data = try await fetch(RFCEditorEndpoints.recentFeed)
    return try RecentFeedParser.parse(data)
  }

  // MARK: - Private

  private func fetch(_ url: URL, notFoundAs id: DocumentID? = nil) async throws -> Data {
    let (data, response) = try await transport.data(for: url)
    switch response.statusCode {
    case 200..<300:
      return data
    case 404:
      if let id { throw ClientError.notFound(id) }
      throw ClientError.httpStatus(404, url)
    default:
      throw ClientError.httpStatus(response.statusCode, url)
    }
  }
}

/// One entry of the "Recent RFCs" RSS feed.
public struct RecentRFC: Sendable, Hashable, Identifiable {
  public var id: DocumentID
  public var title: String
  public var summary: String
  public var link: URL?
  public var publishedAt: Date?

  public init(
    id: DocumentID, title: String, summary: String, link: URL? = nil, publishedAt: Date? = nil
  ) {
    self.id = id
    self.title = title
    self.summary = summary
    self.link = link
    self.publishedAt = publishedAt
  }
}

public enum RecentFeedParser {
  public enum ParseError: Error, Sendable, Equatable {
    case malformed(XMLSyntaxError)
  }

  nonisolated(unsafe) private static let titlePattern = #/^RFC\s*(?<number>\d+):\s*(?<title>.+)$/#

  public static func parse(_ data: Data) throws(ParseError) -> [RecentRFC] {
    let root: XMLTree.Element
    do {
      root = try XMLTree.parse(data)
    } catch {
      throw .malformed(error)
    }
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"

    var items: [RecentRFC] = []
    for item in root.first("channel")?.all("item") ?? [] {
      let rawTitle = item.first("title")?.text.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      guard let match = rawTitle.firstMatch(of: titlePattern), let number = Int(match.number) else {
        continue
      }
      items.append(
        RecentRFC(
          id: .rfc(number),
          title: String(match.title).trimmingCharacters(in: .whitespaces),
          summary: item.first("description")?.text.collapsingWhitespace() ?? "",
          link: item.first("link").flatMap {
            URL(string: $0.text.trimmingCharacters(in: .whitespacesAndNewlines))
          },
          publishedAt: item.first("pubDate").flatMap {
            formatter.date(from: $0.text.trimmingCharacters(in: .whitespacesAndNewlines))
          }
        ))
    }
    return items
  }
}
