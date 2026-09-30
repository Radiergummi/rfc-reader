import RFCKit

/// The page the reader shows for an RFC that is its PDF or PostScript original
/// (#207): the header the index gives, why, and the original to open.
public struct PublishedOriginalPage: Hashable, Sendable {
  public let original: PublishedOriginal
  /// Which of the two cases this is, in a sentence.
  public let explanation: String

  /// A scan comes before Original Text, since it has no text to show. A pointer
  /// comes after it, since Original Text shows that pointer as published. Asked of
  /// the index each time, not of the load, which may have run before the index was
  /// here, without its formats.
  public init?(
    _ id: DocumentID, formats: [FileFormat], showsOriginal: Bool, text document: RFCDocument?
  ) {
    if let scan = PublishedOriginal(id, formats: formats) {
      original = scan
      explanation = "The RFC Editor publishes \(id.displayName) only as a scan."
    } else if !showsOriginal, let document,
      let pointer = PublishedOriginal(id, formats: formats, text: document)
    {
      original = pointer
      explanation = "The text of \(id.displayName) only says where its original is."
    } else {
      return nil
    }
  }
}
