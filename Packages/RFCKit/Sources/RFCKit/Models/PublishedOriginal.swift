import Foundation

/// The PDF or PostScript original an RFC is read as, because it has no text that is
/// the document (#207).
///
/// Seven early RFCs exist only as scans, and the index lists no text for them. Six
/// more have a text that only says where the original is: RFC 570, 1119, 1124, 1128,
/// 1129 and 1131. They are the only texts in the corpus with an original beside them
/// that parse to one block or none, where the next shortest have three, and each
/// lists a PostScript original, as only 55 RFCs do.
public struct PublishedOriginal: Sendable, Hashable {
  public let id: DocumentID
  /// The PDF where there is one, else the PostScript.
  public let format: FileFormat

  /// Where the RFC Editor hosts the original.
  public var url: URL { RFCEditorEndpoints.document(id, format: format) }

  /// The index lists an original, and no text or XML. No formats is an index that
  /// does not know the document, and nil.
  public init?(_ id: DocumentID, formats: [FileFormat]) {
    guard !formats.contains(.text), !formats.contains(.xml) else { return nil }
    self.init(id, original: formats)
  }

  /// The text only says where the original is: a PostScript original is listed, and
  /// the text is one block or none. Checked in that order, so a document with no
  /// PostScript is never walked.
  public init?(_ id: DocumentID, formats: [FileFormat], text document: RFCDocument) {
    guard formats.contains(.postScript), document.blocks.count <= 1 else { return nil }
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
