import Foundation

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

/// Abstraction over `URLSession` so the client can be tested without a network.
public protocol HTTPTransport: Sendable {
  func response(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

/// The transport the client uses unless handed another: a `URLSession`, by default
/// `URLSession.rfcEditor`.
///
/// A struct around the session rather than an extension of `URLSession`, which would
/// add a public `response(for:)` to a system type, beside its own `data(for:)` (#148).
public struct URLSessionTransport: HTTPTransport {
  private let session: URLSession
  private let userAgent: String?

  /// `userAgent` names a client that fetches in bulk, so the server's operators can
  /// tell who it is; nil keeps the session's own.
  public init(session: URLSession = .rfcEditor, userAgent: String? = nil) {
    self.session = session
    self.userAgent = userAgent
  }

  public func response(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
    var request = request
    if let userAgent { request.setValue(userAgent, forHTTPHeaderField: "User-Agent") }
    let (data, response) = try await session.data(for: request)
    guard let http = response as? HTTPURLResponse else {
      throw RFCEditorClient.ClientError.invalidResponse(request.url ?? RFCEditorEndpoints.base)
    }
    return (data, http)
  }
}

extension URLSession {
  /// The session the client uses unless handed another: the default configuration,
  /// without a `URLCache`. Every body the client fetches is kept by its caller --
  /// documents by the app's store, the index beside its snapshot -- and RFCs never
  /// change once published, so a second copy in the shared cache is only disk, and
  /// its own revalidation would stand between the index refresh and the `304` it
  /// asks for.
  public static let rfcEditor: URLSession = {
    let configuration = URLSessionConfiguration.default
    configuration.urlCache = nil
    return URLSession(configuration: configuration)
  }()

  /// The session for a fetch nobody is waiting for, such as the daily index check:
  /// `rfcEditor`'s, except that it does not use a cellular, hotspot or Low Data
  /// Mode path, and waits for one it may use rather than failing (#314). On Linux,
  /// whose `FoundationNetworking` has none of the three settings, it is `rfcEditor`'s.
  public static let rfcEditorOnCheapNetworks: URLSession = {
    let configuration = URLSessionConfiguration.default
    configuration.urlCache = nil
    #if !canImport(FoundationNetworking)
      configuration.waitsForConnectivity = true
      configuration.allowsExpensiveNetworkAccess = false
      configuration.allowsConstrainedNetworkAccess = false
    #endif
    return URLSession(configuration: configuration)
  }()
}

/// What a server said identifies the version of a resource it sent, so a later
/// request can ask for the resource only if it has changed since (RFC 9110,
/// section 13.1).
public struct CacheValidators: Codable, Sendable, Hashable {
  public var entityTag: String?
  public var lastModified: String?

  public init(entityTag: String?, lastModified: String?) {
    self.entityTag = entityTag
    self.lastModified = lastModified
  }

  /// The response's `ETag` and `Last-Modified`, or nil when it sent neither.
  public init?(response: HTTPURLResponse) {
    let entityTag = response.value(forHTTPHeaderField: "ETag")
    let lastModified = response.value(forHTTPHeaderField: "Last-Modified")
    guard entityTag != nil || lastModified != nil else { return nil }
    self.init(entityTag: entityTag, lastModified: lastModified)
  }

  /// Asks for the resource only if it no longer matches. Both are sent: a server
  /// that honors `If-None-Match` ignores `If-Modified-Since` (RFC 9110, 13.1.3).
  func condition(_ request: inout URLRequest) {
    if let entityTag {
      request.setValue(entityTag, forHTTPHeaderField: "If-None-Match")
    }
    if let lastModified {
      request.setValue(lastModified, forHTTPHeaderField: "If-Modified-Since")
    }
  }
}

/// What asking for the index again found.
public enum IndexFetch: Sendable, Hashable {
  /// A new index, and what identifies it for the next time.
  case changed(Data, CacheValidators?)
  /// The server's `304`: the index kept is still the current one.
  case unchanged
}

/// Fetches and parses documents from the RFC Editor.
///
/// Callers decide about caching; this type only knows how to get bytes and turn them
/// into models. It holds nothing but its transport, so it is a value any task can
/// share, and a method that parses is `@concurrent`: a large document is parsed off
/// the caller's actor, and two fetches parse side by side rather than in turn.
public struct RFCEditorClient: Sendable {
  public enum ClientError: Error, LocalizedError, Sendable {
    case invalidResponse(URL)
    case httpStatus(Int, URL)
    case notFound(DocumentID)
    /// What was being read, and why it could not be: the parser's own error, kept
    /// rather than turned into words.
    case decoding(context: String, underlying: any Error)

    /// What went wrong, in words: the app shows `localizedDescription`, which for an
    /// error that says nothing is its type's name and a number (#320).
    public var errorDescription: String? {
      switch self {
      case .invalidResponse(let url):
        "The response from \(url.host() ?? "the server") could not be read."
      case .httpStatus(let status, let url):
        "\(url.host() ?? "The server") answered with HTTP \(status)."
      case .notFound(let id): "\(id.displayName) is not published at the RFC Editor."
      case .decoding(let context, let underlying): "\(context): \(underlying.localizedDescription)"
      }
    }
  }

  private let transport: any HTTPTransport

  public init(transport: any HTTPTransport = URLSessionTransport()) {
    self.transport = transport
  }

  @concurrent
  public func fetchIndex() async throws -> RFCIndex {
    let data = try await fetch(RFCEditorEndpoints.index, accepting: Self.xmlMediaTypes)
    do {
      return try RFCIndexParser.parse(data)
    } catch {
      throw ClientError.decoding(context: "rfc-index.xml", underlying: error)
    }
  }

  /// Raw bytes of a document in the given format, for caching.
  public func fetchDocumentData(_ id: DocumentID, format: FileFormat) async throws -> Data {
    try await fetch(
      RFCEditorEndpoints.document(id, format: format), accepting: Self.mediaTypes(of: format),
      notFoundAs: id)
  }

  /// A document fetched in the best format it has, with the bytes it came as.
  public struct FetchedDocument: Sendable {
    public let data: Data
    public let format: FileFormat
    public let document: RFCDocument
    /// Why the XML was not used, when it was there but did not parse: a parser bug
    /// worth knowing about, and not the same thing as there being no XML.
    public let xmlParseFailure: (any Error)?

    /// Public for a stand-in fetcher, which returns one of these as the client does.
    public init(
      data: Data, format: FileFormat, document: RFCDocument, xmlParseFailure: (any Error)?
    ) {
      self.data = data
      self.format = format
      self.document = document
      self.xmlParseFailure = xmlParseFailure
    }
  }

  /// Whether the plain text is all there is: formats are given, and XML is not among
  /// them. With none given, or an empty list, the XML is tried first.
  ///
  /// Then Original Text and the document are the same `.txt`, which the app fetches
  /// once for both (#324).
  public static func textIsTheDocument(availableFormats: [FileFormat]?) -> Bool {
    guard let availableFormats, !availableFormats.isEmpty else {
      return false
    }
    return !availableFormats.contains(.xml)
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
    if !Self.textIsTheDocument(availableFormats: availableFormats) {
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

  /// The RFC index as bytes, so the caller can both parse and keep it, unless it
  /// still matches `validators`.
  ///
  /// `onExpensiveNetworks` false is a fetch nobody is waiting for, such as the
  /// daily refresh: it does not run on a cellular, hotspot or Low Data Mode path.
  /// It fails there, unless the transport waits for a path it may use, as
  /// `URLSession.rfcEditorOnCheapNetworks` does. A person's Retry passes true.
  public func fetchIndexData(unlessMatching validators: CacheValidators?, onExpensiveNetworks: Bool)
    async throws -> IndexFetch
  {
    var request = Self.request(RFCEditorEndpoints.index)
    validators?.condition(&request)
    #if !canImport(FoundationNetworking)
      request.allowsExpensiveNetworkAccess = onExpensiveNetworks
      request.allowsConstrainedNetworkAccess = onExpensiveNetworks
    #endif
    let (data, response) = try await transport.response(for: request)
    switch response.statusCode {
    case 304:
      return .unchanged
    case 200..<300:
      try Self.check(response, to: request, accepting: Self.xmlMediaTypes)
      return .changed(data, CacheValidators(response: response))
    default:
      throw ClientError.httpStatus(response.statusCode, RFCEditorEndpoints.index)
    }
  }

  /// `revisions.json`, decoded, and the bytes it came as, which the caller keeps. A
  /// plain GET: every run writes a new `generatedAt`, so a conditional request would
  /// never be answered 304.
  @concurrent
  public func fetchRevisions() async throws -> (revisions: RFCRevisions, data: Data) {
    let data = try await fetch(RFCEditorEndpoints.revisions, accepting: nil)
    return (try RFCRevisions.decode(data), data)
  }

  /// `groups.json` (#363), decoded, and the bytes it came as, which the caller keeps.
  /// A plain GET, for the reason `fetchRevisions()` gives.
  @concurrent
  public func fetchWorkingGroups() async throws -> (groups: WorkingGroups, data: Data) {
    let data = try await fetch(RFCEditorEndpoints.workingGroups, accepting: nil)
    return (try WorkingGroups.decode(data), data)
  }

  @concurrent
  public func fetchRecent() async throws -> [RecentRFC] {
    let data = try await fetch(
      RFCEditorEndpoints.recentFeed, accepting: Self.xmlMediaTypes.union(["application/rss+xml"]))
    return try RecentFeedParser.parse(data)
  }

  /// An IANA registry (#175), read, with the bytes it was read from for the caller
  /// to cache. From iana.org rather than the RFC Editor, through the same transport.
  /// A response that is not a registry is an error, so an error page is never kept.
  ///
  /// `onExpensiveNetworks` false is a refresh of a registry already kept, which
  /// nobody is waiting for, as with `fetchIndexData(unlessMatching:onExpensiveNetworks:)`.
  public func fetchRegistry(_ registry: IANARegistry, onExpensiveNetworks: Bool) async throws -> (
    entries: [RegistryEntry], data: Data
  ) {
    var request = Self.request(registry.url)
    #if !canImport(FoundationNetworking)
      request.allowsExpensiveNetworkAccess = onExpensiveNetworks
      request.allowsConstrainedNetworkAccess = onExpensiveNetworks
    #endif
    let data = try await fetch(request, accepting: Self.xmlMediaTypes)
    do {
      return (try IANARegistry.parse(data, as: registry), data)
    } catch {
      throw ClientError.decoding(context: registry.url.absoluteString, underlying: error)
    }
  }

  // MARK: - Private

  private static func request(_ url: URL) -> URLRequest {
    var request = URLRequest(url: url)
    request.setValue("application/xml, text/plain, application/json", forHTTPHeaderField: "Accept")
    return request
  }

  private static let xmlMediaTypes: Set<String> = ["application/xml", "text/xml"]

  /// The `Content-Type`s the RFC Editor serves a document in `format` as.
  private static func mediaTypes(of format: FileFormat) -> Set<String> {
    switch format {
    case .text: ["text/plain"]
    case .xml: xmlMediaTypes
    case .html: ["text/html"]
    case .pdf: ["application/pdf"]
    case .postScript: ["application/postscript"]
    }
  }

  /// Refuses a successful response that is not what was asked for (#757): one of
  /// another type, such as a proxy's or a captive portal's HTML page served in place
  /// of `rfcNNNN.txt`, or one from another host. A document body is kept for good, so
  /// such a page would otherwise become that RFC until Remove Offline Copy.
  private static func check(
    _ response: HTTPURLResponse, to request: URLRequest, accepting mediaTypes: Set<String>
  ) throws {
    let url = request.url!
    guard let mediaType = response.mimeType?.lowercased(), mediaTypes.contains(mediaType),
      response.url?.host() == url.host()
    else { throw ClientError.invalidResponse(url) }
  }

  /// `mediaTypes` nil accepts any body from any host: the JSON published on the
  /// repository's release, which GitHub serves from its own storage host as
  /// `application/octet-stream`, and which a strict decoder refuses if it is anything
  /// else.
  private func fetch(
    _ url: URL, accepting mediaTypes: Set<String>?, notFoundAs id: DocumentID? = nil
  ) async throws -> Data {
    try await fetch(Self.request(url), accepting: mediaTypes, notFoundAs: id)
  }

  private func fetch(
    _ request: URLRequest, accepting mediaTypes: Set<String>?, notFoundAs id: DocumentID? = nil
  ) async throws -> Data {
    let url = request.url!
    let (data, response) = try await transport.response(for: request)
    switch response.statusCode {
    case 200..<300:
      if let mediaTypes { try Self.check(response, to: request, accepting: mediaTypes) }
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
  public enum ParseError: Error, LocalizedError, Sendable, Equatable {
    /// Well-formed XML that is not RSS, such as a sign-in page served in the feed's
    /// place: an error, not a feed with nothing in it (#757).
    case notAFeed(rootElement: String)
    case malformed(XMLSyntaxError)

    /// The syntax error's own words, which the app shows (#320).
    public var errorDescription: String? {
      switch self {
      case .notAFeed(let root): "Not an RSS feed: the document's root element is <\(root)>."
      case .malformed(let error): error.errorDescription
      }
    }
  }

  private static let titlePattern = Pattern(#/^RFC\s*(?<number>\d+):\s*(?<title>.+)$/#)

  /// An RFC 822 date, `Sat, 19 Sep 2026 00:00:00 GMT`: a `Sendable` value made once,
  /// where a `DateFormatter` was built for every parse (#148). The time zone field is
  /// read, not assumed. Strict, as the `DateFormatter` was: a date that does not
  /// exist, `31 Sep`, is no date rather than the first of the next month.
  static let dateStrategy = Date.ParseStrategy(
    format: """
      \(weekday: .abbreviated), \(day: .twoDigits) \(month: .abbreviated) \(year: .defaultDigits) \
      \(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased)):\(minute: .twoDigits):\
      \(second: .twoDigits) \(timeZone: .specificName(.short))
      """,
    locale: Locale(identifier: "en_US_POSIX"),
    timeZone: .gmt,
    isLenient: false)

  public static func parse(_ data: Data) throws(ParseError) -> [RecentRFC] {
    let root: XMLTree.Element
    do {
      root = try XMLTree.parse(data)
    } catch {
      throw .malformed(error)
    }
    guard root.name == "rss" else { throw .notAFeed(rootElement: root.name) }
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
          link: (item.first("link")?.text.trimmingCharacters(in: .whitespacesAndNewlines))
            .flatMap(URL.init(string:)),
          publishedAt: (item.first("pubDate")?.text.trimmingCharacters(in: .whitespacesAndNewlines))
            .flatMap { try? Date($0, strategy: dateStrategy) }
        ))
    }
    return items
  }
}
