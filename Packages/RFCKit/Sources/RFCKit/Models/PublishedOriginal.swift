import Foundation

public struct PublishedOriginal: Error, Sendable, Hashable {
  public let id: DocumentID
  public let format: FileFormat
  public var url: URL { RFCEditorEndpoints.document(id, format: format) }
  public init?(_ id: DocumentID, formats: [FileFormat]) { return nil }
  public init?(_ id: DocumentID, formats: [FileFormat], text document: RFCDocument) { return nil }
}
