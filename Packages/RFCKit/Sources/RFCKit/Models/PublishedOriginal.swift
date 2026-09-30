import Foundation

/// An RFC that is its PDF or PostScript original rather than a text (#207), thrown
/// in place of the document so the reader can offer the original instead.
///
/// Seven early RFCs exist only as scans, and the index lists no text for them. Six
/// more have a text that only says where the original is: RFC 570, 1119, 1124, 1128,
/// 1129 and 1131, every text in the corpus that parses to one block or none beside
/// an original, where the next shortest real documents have three.
public struct PublishedOriginal: Error, Sendable, Hashable {
  public let id: DocumentID
  /// The PDF where there is one, else the PostScript.
  public let format: FileFormat

  /// Where the RFC Editor hosts the original.
  public var url: URL { RFCEditorEndpoints.document(id, format: format) }

  /// Before anything is fetched: the index lists an original, and no text or XML.
  /// No formats is an index that does not know the document, and nil.
  public init?(_ id: DocumentID, formats: [FileFormat]) {
    guard !formats.contains(.text), !formats.contains(.xml) else { return nil }
    self.init(id, original: formats)
  }

  /// Once the text is read: it is one block or none, beside an original, and so only
  /// says where the original is.
  public init?(_ id: DocumentID, formats: [FileFormat], text document: RFCDocument) {
    guard document.blocks.count <= 1 else { return nil }
    self.init(id, original: formats)
  }

  private init?(_ id: DocumentID, original formats: [FileFormat]) {
    guard let format = [FileFormat.pdf, .postScript].first(where: formats.contains) else {
      return nil
    }
    self.id = id
    self.format = format
  }
}
