import RFCKit

/// The page the reader shows for an RFC that is its PDF or PostScript original
/// (#207): the header the index gives, why, and the original to open.
public struct PublishedOriginalPage: Hashable, Sendable {
  /// Why the RFC is read as its original.
  public enum Kind: Hashable, Sendable {
    /// The index lists no text: there is nothing to load.
    case scan
    /// The text loaded, and only says where the original is.
    case pointer
  }

  /// An RFC read as its original, whichever mode the reader is in: why, and which
  /// original.
  public struct Status: Hashable, Sendable {
    public let kind: Kind
    public let original: PublishedOriginal

    /// Nil for an RFC read as its text.
    public init?(_ id: DocumentID, formats: [FileFormat], text document: RFCDocument?) {
      if let scan = PublishedOriginal(id, formats: formats) {
        kind = .scan
        original = scan
      } else if let document,
        let pointer = PublishedOriginal(id, formats: formats, text: document)
      {
        kind = .pointer
        original = pointer
      } else {
        return nil
      }
    }

    /// What the panel says in place of its contents, references and requirements:
    /// why there are none, rather than that the RFC failed to load.
    public var panelExplanation: String {
      let id = original.id.displayName
      let format = original.format.displayName
      return switch kind {
      case .scan: "\(id) is published only as \(format)."
      case .pointer: "The text of \(id) only says where its \(format) original is."
      }
    }
  }

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

  /// Whether the reader fetches the RFC's text: not a scan's, which the index says
  /// has none. An index without the document yet (`nil`) leaves it to the fetch.
  public static func loadsText(_ id: DocumentID, formats: [FileFormat]?) -> Bool {
    formats.flatMap { PublishedOriginal(id, formats: $0) } == nil
  }

  /// Whether Print and Export offer the document: one on screen and read as its
  /// text. A pointer's text is not the RFC, so printing it would print a line
  /// saying where the RFC is.
  public static func offersPrintAndExport(hasDocument: Bool, kind: Kind?) -> Bool {
    hasDocument && kind == nil
  }
}
