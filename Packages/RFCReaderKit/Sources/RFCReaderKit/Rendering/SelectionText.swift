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
  public static func plainText(of selection: NSAttributedString) -> String {
    let attributed = withoutReaderText(of: selection)
    var result = ""
    let whole = NSRange(location: 0, length: attributed.length)
    attributed.enumerateAttribute(.rfcReference, in: whole, options: []) { value, range, _ in
      guard let box = value as? ReferenceBox else {
        // A table cell's line break is set as a line separator, to keep its row
        // one paragraph (#506); on the pasteboard it is the newline it stands for.
        result += attributed.attributedSubstring(from: range).string
          .replacing(DocumentTextBuilder.cellLineSeparator, with: "\n")
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

  /// What the reader adds to the document's words (`.rfcReaderOnly`) — a heading's
  /// backlink caption (#183, #584), a code block's language and copy button — is
  /// not part of what was copied: a copied heading is the heading alone, with no
  /// line where the caption was, and copied code is the code, in the rich flavors
  /// as in the plain one.
  public static func withoutReaderText(of selection: NSAttributedString) -> NSAttributedString {
    var runs: [NSRange] = []
    selection.enumerateAttribute(
      .rfcReaderOnly, in: NSRange(location: 0, length: selection.length)
    ) { value, range, _ in
      if value != nil { runs.append(range) }
    }
    guard !runs.isEmpty else { return selection }
    let result = NSMutableAttributedString(attributedString: selection)
    for run in runs.reversed() {
      result.deleteCharacters(in: run)
    }
    return result
  }

  /// The rich text for `attributed`, a selection taken out of the reader's storage:
  /// the same runs, with every character a decorated block hides behind its strokes
  /// in the text color again. The strokes are the reader's drawing and do not travel,
  /// so a rich paste without its borders would be a grid of field names in space.
  /// Nil when nothing in the selection is hidden, and the rich flavors can stay
  /// AppKit's.
  public static func richText(of attributed: NSAttributedString) -> NSAttributedString? {
    var result: NSMutableAttributedString?
    attributed.enumerateAttribute(
      .foregroundColor, in: NSRange(location: 0, length: attributed.length)
    ) { value, range, _ in
      guard let color = value as? PlatformColor, color == DocumentTextBuilder.hiddenColor else {
        return
      }
      if result == nil { result = NSMutableAttributedString(attributedString: attributed) }
      result?.addAttribute(.foregroundColor, value: RFCColors.label, range: range)
    }
    return result
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

#if !canImport(UIKit) && canImport(AppKit)
  extension SelectionText {
    /// The flavors of a copy the reader writes itself rather than leaving to AppKit.
    public enum Flavor: Sendable, Equatable {
      case plain
      case rtf
      case rtfd
    }

    /// The flavor a pasteboard type asks for, or nil for one the reader leaves to
    /// AppKit. `NSTextView` asks `writeSelection(to:type:)` for the legacy names --
    /// `NSStringPboardType` and the two `NeXT` ones -- which never equal `.string`,
    /// `.rtf` or `.rtfd`, measured on macOS 27. A pasteboard written under the
    /// legacy name reads back under the modern one.
    public static func flavor(of type: NSPasteboard.PasteboardType) -> Flavor? {
      switch type.rawValue {
      case NSPasteboard.PasteboardType.string.rawValue, "NSStringPboardType":
        .plain
      case NSPasteboard.PasteboardType.rtf.rawValue, "NeXT Rich Text Format v1.0 pasteboard type":
        .rtf
      case NSPasteboard.PasteboardType.rtfd.rawValue, "NeXT RTFD pasteboard type":
        .rtfd
      default:
        nil
      }
    }
  }
#endif
