import Foundation
import RFCKit

#if canImport(UIKit)
  import UIKit
#elseif canImport(AppKit)
  import AppKit
#endif

/// What a copied selection puts on the pasteboard.
///
/// A selection is rebuilt rather than transcribed, because the reader's text and the
/// reader's drawing do not carry the same information. A reference is drawn as a
/// chip: a leading symbol, then the label with its brackets taken off, because the
/// chip's tint is what separates it from the words either side. Transcribing those
/// characters gives two things nobody wants on a pasteboard:
///
///   - `U+FFFC`, the object-replacement character carrying the chip's symbol, which
///     is meaningless outside the text view, plus the `U+2060` word joiner behind it;
///   - no delimiters, so two adjacent references run together — `see RFC 9110 RFC
///     9111` — which is the exact ambiguity the brackets were there to prevent.
///
/// Every reference run is therefore replaced by `CrossReference.label`: the plain
/// form the model already composes for precisely this, brackets included, and the
/// same string `RFCXMLSerializer` writes out. The screen shows `display.text`; the
/// pasteboard gets `label`. One model, two renderings, neither guessing at the other.
public enum SelectionText {
  /// The plain text for `attributed`, which is expected to be a selection taken out
  /// of the reader's storage.
  public static func plainText(of attributed: NSAttributedString) -> String {
    var result = ""
    let whole = NSRange(location: 0, length: attributed.length)
    attributed.enumerateAttribute(.rfcReference, in: whole, options: []) { value, range, _ in
      guard let box = value as? ReferenceBox else {
        result += attributed.attributedSubstring(from: range).string
        return
      }
      // The whole reference, even when only part of it was selected: a chip is
      // one thing on screen and there is no half of it that means anything. It
      // is also the only way a run that begins after the symbol still yields a
      // label rather than a fragment of one.
      result += pasteboardLabel(for: box.reference)
    }
    return result
  }

  /// The rich text for `attributed`, a selection taken out of the reader's storage:
  /// the same runs, with every character a decorated block hides behind its strokes
  /// in the text color again. The strokes are the reader's drawing and do not travel,
  /// so a rich paste without its borders would be a grid of field names in space.
  public static func richText(of attributed: NSAttributedString) -> NSAttributedString {
    let result = NSMutableAttributedString(attributedString: attributed)
    let whole = NSRange(location: 0, length: result.length)
    attributed.enumerateAttribute(.foregroundColor, in: whole) { value, range, _ in
      guard let color = value as? PlatformColor, color == DocumentTextBuilder.hiddenColor else {
        return
      }
      result.addAttribute(.foregroundColor, value: RFCColors.label, range: range)
    }
    return result
  }

  /// Whether a selection holds characters a decorated block hides.
  public static func hidesCharacters(_ attributed: NSAttributedString) -> Bool {
    var found = false
    attributed.enumerateAttribute(
      .foregroundColor, in: NSRange(location: 0, length: attributed.length)
    ) { value, _, stop in
      if let color = value as? PlatformColor, color == DocumentTextBuilder.hiddenColor {
        found = true
        stop.pointee = true
      }
    }
    return found
  }

  /// A label with its typesetting taken back out.
  ///
  /// The non-breaking spaces are there to stop a reference wrapping mid-label in a
  /// narrow column, which is a fact about a text view and about nowhere else. What
  /// gets pasted into a mail or a terminal should be the ordinary spaces the RFC
  /// Editor's own text uses.
  private static func pasteboardLabel(for reference: CrossReference) -> String {
    reference.label.replacingOccurrences(of: "\u{00A0}", with: " ")
  }
}
