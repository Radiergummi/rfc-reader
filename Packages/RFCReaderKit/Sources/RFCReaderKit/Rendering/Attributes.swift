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
  /// The enclosing figure's caption, set on a `.rfcVerbatim` run when the artwork
  /// sits inside a captioned figure: the Diagrams rotor's label for it
  /// (`AccessibleReading.rotorLabel`). Never read aloud with the diagram, because
  /// the caption follows it as text.
  public static let rfcCaption = NSAttributedString.Key("rfcCaption")
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
}
