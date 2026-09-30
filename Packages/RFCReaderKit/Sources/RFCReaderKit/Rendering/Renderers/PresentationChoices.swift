import RFCKit

/// What a presentation choice names a block by: its anchor, a stable string that
/// names the same block in every build of the document, or, for a block without
/// one, its ordinal (`VerbatimBox.ordinal`).
public enum PresentationKey: Sendable, Hashable {
  case anchor(String)
  case ordinal(Int)

  public init(anchor: String?, ordinal: Int) {
    if let anchor, !anchor.isEmpty {
      self = .anchor(anchor)
    } else {
      self = .ordinal(ordinal)
    }
  }
}

/// Which blocks of a document the reader asked to see as their source
/// (`PresentationKey`). Every type has one presentation for now, so a choice is
/// binary; a type with several makes this a presentation per block.
public struct PresentationChoices: Sendable, Hashable {
  public var shownAsSource: Set<PresentationKey>

  public init(shownAsSource: Set<PresentationKey> = []) {
    self.shownAsSource = shownAsSource
  }

  public static let defaults = PresentationChoices()
}

extension ArtworkHints {
  /// The reviewed verdicts that ship with the app. Empty until the first is
  /// reviewed; entries carry no RFC text, only an RFC, a `pn` and a type.
  public static let bundled = ArtworkHints.empty
}
