import Foundation
import RFCKit

/// The page the reader shows for an RFC that is its PDF or PostScript original
/// (#207): the header the index gives, why, and the original to open.
public struct PublishedOriginalPage: Hashable, Sendable {
  /// Why the RFC is read as its original.
  public enum Kind: Hashable, Sendable {
    /// The index lists no text: there is nothing to load.
    case scan
    /// The text only says where the original is: it loaded, or the installed pack
    /// lists it so (#316).
    case pointer
  }

  /// An RFC read as its original, whichever mode the reader is in: why, and which
  /// original.
  public struct Status: Hashable, Sendable {
    public let kind: Kind
    public let original: PublishedOriginal

    /// Nil for an RFC read as its text. `pointerInPack`: the installed pack lists
    /// the RFC as a pointer, so its text need not load to say so.
    public init?(
      _ id: DocumentID, formats: [FileFormat], text document: RFCDocument?,
      pointerInPack: Bool = false
    ) {
      if let scan = PublishedOriginal(id, formats: formats) {
        kind = .scan
        original = scan
      } else if let pointer = PublishedOriginalPage.pointer(
        id, formats: formats, text: document, inPack: pointerInPack)
      {
        kind = .pointer
        original = pointer
      } else {
        return nil
      }
    }

    /// What the panel says in place of its contents, references and requirements:
    /// why there are none, rather than that the RFC failed to load.
    public func panelExplanation(in locale: Locale = .interface) -> String {
      let id = original.id.displayName
      let format = original.format.displayName(in: locale)
      return switch kind {
      case .scan: String(kit: "\(id) is published only as \(format).", locale: locale)
      case .pointer:
        String(kit: "The text of \(id) only says where its \(format) original is.", locale: locale)
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
    _ id: DocumentID, formats: [FileFormat], showsOriginal: Bool, text document: RFCDocument?,
    pointerInPack: Bool = false, locale: Locale = .interface
  ) {
    if let scan = PublishedOriginal(id, formats: formats) {
      original = scan
      explanation = String(
        kit: "The RFC Editor publishes \(id.displayName) only as a scan.", locale: locale)
    } else if !showsOriginal,
      let pointer = Self.pointer(id, formats: formats, text: document, inPack: pointerInPack)
    {
      original = pointer
      explanation = String(
        kit: "The text of \(id.displayName) only says where its original is.", locale: locale)
    } else {
      return nil
    }
  }

  /// Whether the reader fetches the RFC's text: not a scan's, which the index says
  /// has none, nor a pointer's the installed pack lists, which it has no XML of
  /// (#316). An index without the document yet (`nil`) leaves it to the fetch, as
  /// does one listing no original for a pointer: there would be no page to show.
  public static func loadsText(
    _ id: DocumentID, formats: [FileFormat]?, pointerInPack: Bool = false
  ) -> Bool {
    guard let formats else { return true }
    return PublishedOriginal(id, formats: formats) == nil
      && (!pointerInPack || PublishedOriginal(pointer: id, formats: formats) == nil)
  }

  /// The original a text that only points to it stands for: known from the
  /// installed pack, or else from the text once it is here.
  private static func pointer(
    _ id: DocumentID, formats: [FileFormat], text document: RFCDocument?, inPack: Bool
  ) -> PublishedOriginal? {
    if inPack { return PublishedOriginal(pointer: id, formats: formats) }
    return document.flatMap { PublishedOriginal(id, formats: formats, text: $0) }
  }

  /// Whether Print and Export offer the document: one on screen and read as its
  /// text. A pointer's text is not the RFC, so printing it would print a line
  /// saying where the RFC is.
  public static func offersPrintAndExport(hasDocument: Bool, kind: Kind?) -> Bool {
    hasDocument && kind == nil
  }
}
