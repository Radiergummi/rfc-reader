import Foundation

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

/// Fetches `revisions.json`, which the revisions workflow publishes daily on the
/// repository's `revisions` release. A plain GET: every run writes a new
/// `generatedAt`, so a conditional request would never be answered 304.
public struct RevisionsClient: Sendable {
  public static let url = URL(
    string: "https://github.com/Radiergummi/rfc-reader/releases/download/revisions/revisions.json")!

  private let transport: any HTTPTransport

  public init(transport: any HTTPTransport = URLSession.shared) {
    self.transport = transport
  }

  /// The decoded file and the bytes it came as, which the caller keeps.
  public func fetch() async throws -> (revisions: RFCRevisions, data: Data) {
    let (data, response) = try await transport.data(for: Self.url)
    guard (200..<300).contains(response.statusCode) else {
      throw RFCEditorClient.ClientError.httpStatus(response.statusCode, Self.url)
    }
    return (try RFCRevisions.decode(data), data)
  }
}
