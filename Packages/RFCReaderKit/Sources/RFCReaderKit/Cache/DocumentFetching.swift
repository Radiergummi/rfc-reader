import Foundation
import RFCKit

/// What `DocumentStore` asks of the network: exactly the two fetches of
/// `RFCEditorClient` it makes, so its tests can hold one in flight while they act.
public protocol DocumentFetching: Sendable {
  /// A document in the best format it has, with the bytes it came as; see
  /// `RFCEditorClient.fetchPreferredDocument(_:availableFormats:)`.
  @concurrent
  func fetchPreferredDocument(_ id: DocumentID, availableFormats: [FileFormat]?) async throws
    -> RFCEditorClient.FetchedDocument

  /// Raw bytes of a document in the given format, for caching.
  func fetchDocumentData(_ id: DocumentID, format: FileFormat) async throws -> Data
}

extension RFCEditorClient: DocumentFetching {}
