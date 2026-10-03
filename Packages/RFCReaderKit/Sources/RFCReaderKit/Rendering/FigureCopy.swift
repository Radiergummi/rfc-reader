import Foundation
import RFCKit

/// What "Copy Figure" copies, and which figure a menu means (issue #15).
///
/// A selection dragged across a diagram gets the laid-out lines, which is not the
/// figure: the selection rarely starts and ends on its edges, and the lines are the
/// ones the plain-text page needed. RFC 8792 folded any line longer than 69 columns
/// to fit that page, so a folded block copied as it reads is invalid XML, a broken
/// JSON string, an HTTP header split mid-token (issue #64). "Copy Figure" reaches
/// past the layout to the `Preformatted` each verbatim run carries in its
/// `VerbatimBox`, and copies it unfolded.
///
/// The App target decides only where the menu is and puts the string on the
/// pasteboard; which figure and what text are answered here, where they are tested.
public enum FigureCopy {
  /// The box of the figure whose run holds `location`: a context menu opened on
  /// it. Its block, and what the build decided about it: its menu's "Show as Text"
  /// needs its ordinal and how it is shown.
  public static func box(at location: Int, in text: NSAttributedString) -> VerbatimBox? {
    guard location >= 0, location < text.length else { return nil }
    return text.attribute(.rfcVerbatim, at: location, effectiveRange: nil) as? VerbatimBox
  }

  /// The box of the one figure a selection touches, or nil when it touches none or
  /// more than one: a menu offering to copy "the figure" has to know which. An
  /// empty selection is a location.
  ///
  /// Figures are told apart by their box's identity, one per block, so two
  /// adjacent blocks with the same text are still two.
  public static func box(in range: NSRange, of text: NSAttributedString) -> VerbatimBox? {
    guard range.length > 0 else { return box(at: range.location, in: text) }
    let clamped = NSIntersectionRange(range, NSRange(location: 0, length: text.length))
    var found: VerbatimBox?
    var ambiguous = false
    text.enumerateAttribute(.rfcVerbatim, in: clamped, options: []) { value, _, stop in
      guard let box = value as? VerbatimBox else { return }
      if let found, found !== box {
        ambiguous = true
        stop.pointee = true
        return
      }
      found = box
    }
    return ambiguous ? nil : found
  }

  /// What goes on the pasteboard, from Copy Figure and from a code block's copy
  /// button alike: the block as its author wrote it, not as the page folded it, and
  /// as the reader sets it in a column wide enough -- tabs expanded, and source code
  /// without the indent its lines share -- so a selection over the whole block
  /// pastes the same (`DocumentTextBuilder.copiedText(of:)`).
  public static func pasteboardText(for figure: Preformatted) -> String {
    DocumentTextBuilder.copiedText(of: figure)
  }
}
