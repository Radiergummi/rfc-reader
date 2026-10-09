import Foundation
import RFCKit
import UniformTypeIdentifiers

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
  ///
  /// `unfolding` undoes RFC 8792's folds in a block shown folded. A caller that
  /// passes one line at a time, as a quote does, has no fold whole to undo, and
  /// would lose only the header that explains the folds it keeps.
  public static func plainText(of selection: NSAttributedString, unfolding: Bool = true)
    -> String
  {
    let attributed = withoutReaderText(of: selection)
    var result = ""
    let whole = NSRange(location: 0, length: attributed.length)
    attributed.enumerateAttribute(.rfcReference, in: whole, options: []) { value, range, _ in
      // A rule link in a grammar is the grammar's own text (#185): a block is copied
      // as it is set.
      let isVerbatim =
        attributed.attribute(.rfcVerbatim, at: range.location, effectiveRange: nil) != nil
      guard let box = value as? ReferenceBox, !isVerbatim else {
        // A table cell's line break is set as a line separator, to keep its row
        // one paragraph (#506); on the pasteboard it is the newline it stands for.
        let run = attributed.attributedSubstring(from: range)
        result += (unfolding ? unfolded(run) : run.string)
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

  /// `run`'s text, with the folds undone in any part of it that is a block RFC 8792
  /// folded (#212). A block too wide for the column is shown as published, folds and
  /// header included, and a selection over it would otherwise paste code that works
  /// or not depending on the window's width; Copy Figure always unfolds. A block
  /// already shown unfolded has no fold left, so it copies as it is: unfolded again,
  /// two of the author's own lines could read as a fold (`VerbatimBox.shownFolding`).
  private static func unfolded(_ run: NSAttributedString) -> String {
    var result = ""
    run.enumerateAttribute(.rfcVerbatim, in: NSRange(location: 0, length: run.length)) {
      value, range, _ in
      let text = run.attributedSubstring(from: range).string
      guard let box = value as? VerbatimBox, let strategy = box.shownFolding else {
        result += text
        return
      }
      result += FoldedLines.unfold(selection: text, strategy: strategy)
    }
    return result
  }

  /// What the reader adds to the document's words (`.rfcReaderOnly`) — a heading's
  /// backlink caption (#183, #584), a code block's language and copy button — is
  /// not part of what was copied: a copied heading is the heading alone, with no
  /// line where the caption was, and copied code is the code, in the rich flavors
  /// as in the plain one.
  ///
  /// Nor is how it sets a heading's hung number (#433): the tabs and the number copy
  /// as the heading's own prefix (`.rfcCopiedAs`), so a heading copies the same
  /// whether the window had room to hang it or not.
  public static func withoutReaderText(of selection: NSAttributedString) -> NSAttributedString {
    let whole = NSRange(location: 0, length: selection.length)
    var runs: [(range: NSRange, replacement: String)] = []
    selection.enumerateAttribute(.rfcReaderOnly, in: whole) { value, range, _ in
      if value != nil { runs.append((range, "")) }
    }
    selection.enumerateAttribute(.rfcCopiedAs, in: whole) { value, range, _ in
      if let copied = value as? String { runs.append((range, copied)) }
    }
    guard !runs.isEmpty else { return selection }
    let result = NSMutableAttributedString(attributedString: selection)
    for run in runs.sorted(by: { $0.range.location > $1.range.location }) {
      // In the heading's own attributes, its color and no link: the run's, less what
      // makes the number one, since a selection that ends inside the number has no
      // tab after it to take them from.
      var attributes = result.attributes(at: NSMaxRange(run.range) - 1, effectiveRange: nil)
        .filter { ![.rfcCopiedAs, .rfcSectionNumber, .link].contains($0.key) }
      attributes[.foregroundColor] = RFCColors.label
      result.replaceCharacters(
        in: run.range, with: NSAttributedString(string: run.replacement, attributes: attributes))
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

  /// The rich text a copy of `selection` carries (#778): without the reader's own
  /// text, with what a diagram hides shown again, and with every link one anyone
  /// can open, `publicURL`'s for the reader's links, or none. The chips stay as they
  /// look on screen, their symbols the images a rich target receives.
  ///
  /// `hang` is the build's (`BuiltDocument.sectionNumberHang`, #433), which every
  /// paragraph is set in by on screen and none is in the copy: a paste is indented
  /// the same whether the window had room to hang the numbers or not.
  public static func richCopy(
    of selection: NSAttributedString, publicURL: (URL) -> URL?, hang: CGFloat = 0
  ) -> NSAttributedString {
    let withoutReaderText = withoutReaderText(of: selection)
    let result = NSMutableAttributedString(
      attributedString: richText(of: withoutReaderText) ?? withoutReaderText)
    let whole = NSRange(location: 0, length: result.length)
    if hang > 0 {
      result.enumerateAttribute(.paragraphStyle, in: whole) { value, range, _ in
        guard let style = value as? NSParagraphStyle else { return }
        result.addAttribute(.paragraphStyle, value: unhung(style, by: hang), range: range)
      }
    }
    result.enumerateAttribute(.link, in: whole) { value, range, _ in
      guard let link = linkURL(value) else { return }
      if let url = publicURL(link) {
        result.addAttribute(.link, value: url, range: range)
      } else {
        result.removeAttribute(.link, range: range)
      }
    }
    return result
  }

  /// `style` as it is set where no number hangs: its indents and tab stops measured
  /// from the column's edge rather than the container's, `hang` left of it. A hung
  /// heading's tab to its number, left of the column, has no place there.
  private static func unhung(_ style: NSParagraphStyle, by hang: CGFloat) -> NSParagraphStyle {
    let unhung = NSMutableParagraphStyle()
    unhung.setParagraphStyle(style)
    unhung.firstLineHeadIndent = max(0, style.firstLineHeadIndent - hang)
    unhung.headIndent = max(0, style.headIndent - hang)
    unhung.tabStops = style.tabStops.compactMap { stop in
      stop.location < hang
        ? nil
        : NSTextTab(
          textAlignment: stop.alignment, location: stop.location - hang, options: stop.options)
    }
    return unhung
  }

  /// The HTML a copy of `selection` carries (#778): a `p` per paragraph and a `pre`
  /// per verbatim block, with the text as the plain flavor has it, a reference by
  /// its label, and links as `richCopy` makes them.
  public static func html(of selection: NSAttributedString, publicURL: (URL) -> URL?) -> String {
    let text = withoutReaderText(of: selection)
    let string = text.string as NSString
    var parts: [String] = []
    // The verbatim block being collected: its box, and the range of its lines so
    // far, copied whole so that its folds are undone as the plain flavor's are.
    var block: (box: VerbatimBox, range: NSRange)?
    func endBlock() {
      guard let current = block else { return }
      let lines = plainText(of: text.attributedSubstring(from: current.range))
      parts.append("<pre>\(PasteboardMarkup.escaped(lines))</pre>")
      block = nil
    }
    var paragraphs: [(range: NSRange, enclosingRange: NSRange)] = []
    string.enumerateSubstrings(
      in: NSRange(location: 0, length: string.length), options: .byParagraphs
    ) { _, range, enclosingRange, _ in
      paragraphs.append((range, enclosingRange))
    }
    for (range, enclosingRange) in paragraphs {
      // An empty line has no character of its own; its line break carries the box.
      let box =
        enclosingRange.length > 0
        ? text.attribute(.rfcVerbatim, at: enclosingRange.location, effectiveRange: nil)
          as? VerbatimBox
        : nil
      if let box {
        if let current = block, current.box === box {
          block?.range = NSUnionRange(current.range, range)
        } else {
          endBlock()
          block = (box, range)
        }
        continue
      }
      endBlock()
      guard range.length > 0 else { continue }
      parts.append("<p>\(inlineHTML(of: text.attributedSubstring(from: range), publicURL))</p>")
    }
    endBlock()
    return PasteboardMarkup.html(parts.joined(separator: "\n"))
  }

  /// A paragraph of prose as HTML: a reference as its label, linked where it has a
  /// public URL, and any other link as its text, linked the same way.
  private static func inlineHTML(
    of paragraph: NSAttributedString, _ publicURL: (URL) -> URL?
  ) -> String {
    var result = ""
    func linked(_ text: String, to link: Any?) -> String {
      let escaped = PasteboardMarkup.escaped(text)
      guard let url = linkURL(link).flatMap(publicURL) else { return escaped }
      return "<a href=\"\(PasteboardMarkup.escaped(url.absoluteString))\">\(escaped)</a>"
    }
    let whole = NSRange(location: 0, length: paragraph.length)
    paragraph.enumerateAttribute(.rfcReference, in: whole) { value, range, _ in
      if let box = value as? ReferenceBox {
        let link = paragraph.attribute(.link, at: range.location, effectiveRange: nil)
        result += linked(pasteboardLabel(for: box.reference), to: link)
        return
      }
      paragraph.enumerateAttribute(.link, in: range) { link, run, _ in
        let text = paragraph.attributedSubstring(from: run).string
        result += linked(text, to: link)
          .replacing(DocumentTextBuilder.cellLineSeparator, with: "<br>")
      }
    }
    return result
  }

  /// A link attribute's value as a URL: AppKit may hold it as its string.
  private static func linkURL(_ value: Any?) -> URL? {
    value as? URL ?? (value as? String).flatMap(URL.init(string:))
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
      case html

      /// The type `PasteboardContent` answers this flavor under.
      public var type: UTType {
        switch self {
        case .plain: .utf8PlainText
        case .rtf: .rtf
        case .rtfd: .flatRTFD
        case .html: .html
        }
      }
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
      case NSPasteboard.PasteboardType.html.rawValue, "Apple HTML pasteboard type":
        .html
      default:
        nil
      }
    }
  }
#endif
