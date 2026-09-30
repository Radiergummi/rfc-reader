import RFCKit

/// Which blocks of a document the reader asked to see as their source, by ordinal
/// (`VerbatimBox.ordinal`). Every type has one presentation for now, so a choice is
/// binary; a type with several makes this a presentation per block.
public struct PresentationChoices: Sendable, Hashable {
  public var shownAsSource: Set<Int>

  public init(shownAsSource: Set<Int> = []) {
    self.shownAsSource = shownAsSource
  }

  public static let defaults = PresentationChoices()
}

extension ArtworkHints {
  /// The reviewed verdicts that ship with the app. Empty until the first is
  /// reviewed; entries carry no RFC text, only an RFC, a `pn` and a type.
  public static let bundled = ArtworkHints([:])
}
