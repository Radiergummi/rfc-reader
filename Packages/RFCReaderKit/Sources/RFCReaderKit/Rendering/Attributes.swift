import Foundation
import RFCKit

extension NSAttributedString.Key {
  /// The cross reference a run stands for: hit testing, preview, chip drawing.
  public static let rfcReference = NSAttributedString.Key("rfcReference")
  /// Set on heading runs, so the VoiceOver headings rotor can find them.
  public static let rfcAnchor = NSAttributedString.Key("rfcAnchor")
  /// What the layout fragment should draw behind or beside this run.
  public static let rfcDecoration = NSAttributedString.Key("rfcDecoration")
  /// The verbatim block a run came from: the accessibility element and "Copy
  /// Figure" (`FigureCopy`) both need the original text, not the laid-out lines.
  public static let rfcVerbatim = NSAttributedString.Key("rfcVerbatim")
  /// Marks the run that should be drawn as a chip: the span the brackets enclosed.
  /// The value is a serial number unique to that chip, because `NSAttributedString`
  /// merges contiguous runs whose values compare equal and two adjacent chips must
  /// stay two runs. Only its distinctness is meaningful; nothing reads the number.
  public static let rfcChip = NSAttributedString.Key("rfcChip")
  /// Set on the chip of a citation that only an informative list holds, which is
  /// drawn with a lighter tint than a normative one (#184). A `String`, so adjacent
  /// runs compare equal; only its presence is meaningful.
  public static let rfcInformative = NSAttributedString.Key("rfcInformative")
  /// Set on a heading's backlink chip and the space before it (#183): the anchor of
  /// the section the chip lists the backlinks of. A `String`, so the runs merge. A
  /// copied selection leaves these runs out (`SelectionText`): they are the reader's,
  /// not the document's words.
  public static let rfcBacklinks = NSAttributedString.Key("rfcBacklinks")
  /// What VoiceOver says in place of a run's characters, where the text view lets it
  /// (`AccessibleReading`): a heading's backlink chip (#183), which would otherwise
  /// read as its arrow and a bare number. A `String`, carried by every character of
  /// the chip and nothing else.
  public static let rfcSpoken = NSAttributedString.Key("rfcSpoken")
  /// The enclosing figure's caption, set on a `.rfcVerbatim` run when the artwork
  /// sits inside a captioned figure: the Diagrams rotor's label for it
  /// (`AccessibleReading.rotorLabel`). Never read aloud with the diagram, because
  /// the caption follows it as text.
  public static let rfcCaption = NSAttributedString.Key("rfcCaption")
  /// Where a link goes, in a build whose style emits no live links
  /// (`ReadingStyle.emitsLinks`): a key TextKit does not know, so it neither
  /// underlines nor recolours the run, which an exported PDF still turns into a
  /// link annotation (#376). The value is the URL the reader's `.link` would carry.
  public static let rfcLinkTarget = NSAttributedString.Key("rfcLinkTarget")
  /// The strokes a decorated block draws over its text (`DecoratedText`), set on
  /// every character of the block so each line's fragment finds them, and which of
  /// the block's lines it holds, through the box's extent (`StrokeGeometry`).
  public static let rfcStrokes = NSAttributedString.Key("rfcStrokes")
  /// How wide a verbatim block's widest line is set, in points, on every character
  /// of the block: where its card ends (`FragmentGeometry.Placement`). A number,
  /// which compares by value, so the runs of one block coalesce.
  public static let rfcContentWidth = NSAttributedString.Key("rfcContentWidth")
  /// Which segment of a rendered block's Figure | Source control is on
  /// (`FigureControl.Segment`'s raw value), on every character of the block, in a
  /// build with live links only: paper has nothing to press.
  public static let rfcFigureControl = NSAttributedString.Key("rfcFigureControl")
}

public enum RFCDecoration: String, Sendable {
  case blockQuote
  case aside
  case artwork
  case table
}

extension RFCDecoration {
  /// How a decoration travels in an attributed string: as its raw `String`, never
  /// as the enum itself.
  ///
  /// `NSAttributedString` merges contiguous runs whose values compare equal, and a
  /// Swift enum boxed into an attribute does not compare equal across separate
  /// insertions. A block whose decoration is applied once — artwork, appended in a
  /// single call — merged fine; one applied per piece — a stacked table's cells,
  /// an authors' block — did not, so every paragraph reported itself as a complete
  /// decoration run. The renderer reads that run's `effectiveRange` to cap the
  /// band's rounded corners and to place its left edge, so unmerged runs drew one
  /// fully rounded card per line at its own indent: the staircase. `NSString`
  /// compares by value, so runs merge.
  public init?(attributeValue: Any?) {
    guard let raw = attributeValue as? String, let decoration = RFCDecoration(rawValue: raw) else {
      return nil
    }
    self = decoration
  }
}

/// Boxes a `Preformatted` so it can live in an `NSAttributedString` attribute, with
/// what the build decided about it.
public final class VerbatimBox: Sendable {
  /// Whether the block is set as its source or rendered, and whether a rendering
  /// exists to switch to: the context menu offers "Show Source" on a rendered
  /// block and "Show Rendering" on one shown as source.
  public enum Shown: Sendable, Equatable {
    /// No presentation accepts the block.
    case plain
    case rendered
    /// A presentation accepts it, and the reader asked for the source.
    case source
  }

  public let content: Preformatted
  /// Its place among the document's verbatim blocks, in the order the build sets
  /// them: what a presentation choice is keyed by.
  public let ordinal: Int
  public let classification: ArtworkClassification
  public let shown: Shown
  /// What VoiceOver says in place of a rendered block's drawing, from its
  /// rendition (`DecoratedText.spokenLabel`); nil unless it is shown rendered.
  public let spokenLabel: String?

  public init(
    _ content: Preformatted, ordinal: Int = 0,
    classification: ArtworkClassification = .unclassified, shown: Shown = .plain,
    spokenLabel: String? = nil
  ) {
    self.content = content
    self.ordinal = ordinal
    self.classification = classification
    self.shown = shown
    self.spokenLabel = spokenLabel
  }
}

extension VerbatimBox {
  /// Which segment of its Figure | Source control is on, or nil for a block with no
  /// rendering to switch to.
  public var segment: FigureControl.Segment? {
    switch shown {
    case .plain: nil
    case .rendered: .figure
    case .source: .source
    }
  }
}

/// Boxes a decorated block's strokes, for the reason `VerbatimBox` boxes its block:
/// one instance per block, so the attribute's extent is the block.
public final class StrokeBox: Sendable {
  public let strokes: [Stroke]
  public init(_ strokes: [Stroke]) { self.strokes = strokes }
}

/// Boxes a `CrossReference` for the same reason.
public final class ReferenceBox: Sendable {
  public let reference: CrossReference
  public init(_ reference: CrossReference) { self.reference = reference }
}

extension NSAttributedString {
  /// The whole extent of the boxed value — a `VerbatimBox` or `ReferenceBox` — at
  /// `location`: every character around it carrying that same instance. Nil where
  /// there is no value, or no character.
  ///
  /// The extent is the attribute's run, not the storage run: a chip is three
  /// storage runs, and `effectiveRange` names only one. The boxes are Swift classes
  /// with no `Equatable` conformance, which bridge to `isEqual:` by identity, so
  /// `longestEffectiveRange` joins one box's runs and keeps two boxes apart even
  /// when their contents are equal (`BoxExtentTests`).
  ///
  /// The cheap single-run lookup answers "no box" first, which is most characters;
  /// the extent is only walked out on a hit.
  func extent(ofBox key: NSAttributedString.Key, at location: Int) -> NSRange? {
    guard location >= 0, location < length,
      attribute(key, at: location, effectiveRange: nil) != nil
    else { return nil }
    var range = NSRange(location: 0, length: 0)
    _ = attribute(
      key, at: location, longestEffectiveRange: &range, in: NSRange(location: 0, length: length))
    return range
  }

  /// The cross reference at this character offset, and the whole of its extent:
  /// what the hover popover is anchored to, and what both previews look up. Two
  /// adjacent references come back as two. This runs on every pointer move.
  public func reference(at offset: Int) -> (box: ReferenceBox, range: NSRange)? {
    guard offset >= 0, offset < length,
      let box = attribute(.rfcReference, at: offset, effectiveRange: nil) as? ReferenceBox,
      let range = extent(ofBox: .rfcReference, at: offset)
    else { return nil }
    return (box, range)
  }

  /// The heading's backlink chip at this character offset (#183), the space before
  /// it included: the section it lists the backlinks of, and the chip's own extent,
  /// without that space -- what its list is anchored to. A heading can wrap at the
  /// space, which would anchor the list to the end of the line above.
  public func backlinkChip(at offset: Int) -> (anchor: String, range: NSRange)? {
    // Looked at before the extent is asked for: a longest range of nothing reaches
    // out to the next chip or the end of the document, and this is asked of every
    // click on a link and every context menu.
    guard offset >= 0, offset < length,
      let anchor = attribute(.rfcBacklinks, at: offset, effectiveRange: nil) as? String
    else { return nil }
    var run = NSRange(location: 0, length: 0)
    _ = attribute(
      .rfcBacklinks, at: offset, longestEffectiveRange: &run,
      in: NSRange(location: 0, length: length))
    var chip = run
    _ = attribute(.rfcChip, at: NSMaxRange(run) - 1, longestEffectiveRange: &chip, in: run)
    return (anchor, chip)
  }
}
