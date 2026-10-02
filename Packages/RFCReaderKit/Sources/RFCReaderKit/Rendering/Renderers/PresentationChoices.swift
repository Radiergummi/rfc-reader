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

/// How a document's blocks that have a rendering are shown: as a figure or as
/// their text, by the reader's preference for every document, unless the reader
/// chose otherwise for a block from its menu (`PresentationKey`). Every type has one
/// rendering for now, so a choice is binary; a type with several makes this a
/// presentation per block.
public struct PresentationChoices: Sendable, Hashable {
  public enum Presentation: Sendable, Hashable {
    case figure
    case text
  }

  /// The reader's preference (`ReaderPreferences.drawDiagramsKey`).
  public var preferred: Presentation
  /// The blocks the reader chose a presentation for, which overrides `preferred`.
  public var chosen: [PresentationKey: Presentation]

  public init(preferred: Presentation = .figure, chosen: [PresentationKey: Presentation] = [:]) {
    self.preferred = preferred
    self.chosen = chosen
  }

  /// The reader's preference as user defaults hold it.
  public init(drawsDiagrams: Bool, chosen: [PresentationKey: Presentation] = [:]) {
    self.init(preferred: drawsDiagrams ? .figure : .text, chosen: chosen)
  }

  /// How the block `key` names is shown, where it has a rendering.
  public func presentation(of key: PresentationKey) -> Presentation {
    chosen[key] ?? preferred
  }

  public static let defaults = PresentationChoices()
}

extension ArtworkHints {
  /// The reviewed verdicts that ship with the app. Empty until the first is
  /// reviewed; entries carry no RFC text, only an RFC, a `pn` and a type.
  public static let bundled = ArtworkHints.empty
}
