import Foundation

/// A verbatim block's type as a renderer asks for it: RFCXML's `type` attribute,
/// lowercased, with any media-type parameters split off, and spelled one way.
///
/// The vocabulary is free text with preferred values, so authors write the same
/// type several ways (`CDDL`, `cddl`), and some write a media type with parameters
/// (`message/http; msgtype="request"`). A renderer names a type once, here.
public struct ArtworkType: Sendable, Hashable {
  public var name: String
  public var parameters: [String: String]

  public init(name: String, parameters: [String: String] = [:]) {
    self.name = name
    self.parameters = parameters
  }

  /// Types that say nothing about what a block is. `ascii-art` is RFCXML's default
  /// for a drawing of any kind.
  static let generic: Set<String> = ["", "ascii-art", "drawing", "ascii", "text", "plain", "none"]

  /// Spellings authors use for a type the RPC spells otherwise.
  static let aliases: [String: String] = ["cbordiag": "cbor-diag"]

  /// The type `declared` names, or nil when it names none.
  public static func canonical(_ declared: String?) -> ArtworkType? {
    guard let declared else { return nil }
    let parts = declared.split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) }
    let name = (parts.first ?? "").lowercased()
    guard !generic.contains(name) else { return nil }
    var parameters: [String: String] = [:]
    for part in parts.dropFirst() {
      let pair = part.split(separator: "=", maxSplits: 1).map(String.init)
      guard pair.count == 2 else { continue }
      let key = pair[0].trimmingCharacters(in: .whitespaces).lowercased()
      let value = pair[1].trimmingCharacters(in: .whitespaces)
        .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
      parameters[key] = value
    }
    return ArtworkType(name: aliases[name] ?? name, parameters: parameters)
  }
}

/// Reviewed verdicts on the types of authored artwork, keyed by the RFC and the
/// block's `pn`: permanent, because a published RFC never changes. Converted
/// documents take none; the converter writes their types.
public struct ArtworkHints: Sendable {
  public enum Verdict: Sendable, Hashable {
    case type(String)
    /// Set as verbatim, whatever a recognizer would say.
    case none
  }

  public struct Key: Sendable, Hashable {
    public var document: DocumentID
    public var anchor: String

    public init(document: DocumentID, anchor: String) {
      self.document = document
      self.anchor = anchor
    }
  }

  private let entries: [Key: Verdict]

  public init(_ entries: [Key: Verdict]) {
    self.entries = entries
  }

  public static let empty = ArtworkHints([:])

  public func verdict(for document: DocumentID?, anchor: String?) -> Verdict? {
    guard let document, let anchor, !anchor.isEmpty else { return nil }
    return entries[Key(document: document, anchor: anchor)]
  }
}

/// What the classify stage decided about one block. Beside the model, never
/// written into it: the reader prints a source block's `type` as its label, and the
/// converter writes it back out.
public struct ArtworkClassification: Sendable, Hashable {
  public var type: ArtworkType?

  public init(type: ArtworkType?) {
    self.type = type
  }

  public static let unclassified = ArtworkClassification(type: nil)
}

/// Decides which renderer a verbatim block goes to. Renderers never guess; every
/// guess is made here, where it can be measured against the corpus.
public enum ArtworkClassifier {
  /// First that applies: a hint of `none`; the block's own specific type; a hint's
  /// type where the block's is generic; an exact recognizer; otherwise nothing.
  public static func classify(
    _ block: Preformatted, in document: DocumentID?, hints: ArtworkHints
  ) -> ArtworkClassification {
    let verdict = hints.verdict(for: document, anchor: block.anchor)
    if verdict == ArtworkHints.Verdict.none { return .unclassified }
    if let declared = ArtworkType.canonical(block.type) {
      return ArtworkClassification(type: declared)
    }
    if case .type(let name)? = verdict, let hinted = ArtworkType.canonical(name) {
      return ArtworkClassification(type: hinted)
    }
    // Source code is text an author typed as code, never a drawing.
    if block.kind == .artwork, PacketDiagram.recognize(block.text) != nil {
      return ArtworkClassification(type: ArtworkType(name: "packet"))
    }
    return .unclassified
  }
}
