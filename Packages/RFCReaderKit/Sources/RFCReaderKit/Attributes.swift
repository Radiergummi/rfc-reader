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

/// Boxes a `Preformatted` so it can live in an `NSAttributedString` attribute.
public final class VerbatimBox: Sendable {
  public let content: Preformatted
  public init(_ content: Preformatted) { self.content = content }
}

/// Boxes a `CrossReference` for the same reason.
public final class ReferenceBox: Sendable {
  public let reference: CrossReference
  public init(_ reference: CrossReference) { self.reference = reference }
}

extension NSAttributedString {
  /// The cross reference at this character offset, and the whole of its extent:
  /// what the hover popover is anchored to, and what both previews look up.
  ///
  /// The extent is the attribute's run, not the storage run. A chip is three
  /// storage runs — the symbol's attachment, the joiner, the label — so
  /// `effectiveRange` names only the piece under the pointer, and the popover
  /// pointed at a third of the chip. `ReferenceBox` compares by identity, one per
  /// reference, so two adjacent references still come back as two.
  ///
  /// This runs on every pointer move, and most of them are over prose, so the
  /// cheap single-run lookup answers "no reference" first; the extent is only
  /// walked out on a hit.
  public func reference(at offset: Int) -> (box: ReferenceBox, range: NSRange)? {
    guard offset >= 0, offset < length,
      attribute(.rfcReference, at: offset, effectiveRange: nil) is ReferenceBox
    else { return nil }
    var range = NSRange(location: 0, length: 0)
    let whole = NSRange(location: 0, length: length)
    guard
      let box = attribute(.rfcReference, at: offset, longestEffectiveRange: &range, in: whole)
        as? ReferenceBox
    else { return nil }
    return (box, range)
  }

  /// The heading's backlink chip at this character offset (#183), the space before
  /// it included: the section it lists the backlinks of, and the chip's own extent,
  /// without that space -- what its list is anchored to. A heading can wrap at the
  /// space, which would anchor the list to the end of the line above.
  public func backlinkChip(at offset: Int) -> (anchor: String, range: NSRange)? {
    guard offset >= 0, offset < length else { return nil }
    var run = NSRange(location: 0, length: 0)
    guard
      let anchor = attribute(
        .rfcBacklinks, at: offset, longestEffectiveRange: &run,
        in: NSRange(location: 0, length: length)) as? String
    else { return nil }
    var chip = run
    _ = attribute(.rfcChip, at: NSMaxRange(run) - 1, longestEffectiveRange: &chip, in: run)
    return (anchor, chip)
  }
}
