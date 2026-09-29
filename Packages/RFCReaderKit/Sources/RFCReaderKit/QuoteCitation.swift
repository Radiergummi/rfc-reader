import Foundation
import RFCKit

#if canImport(UIKit)
  import UIKit
#else
  import AppKit
#endif

/// Copy as Quote: the selected text, and a citation of where it was taken from (#186).
///
/// What reviewers and writers do with a spec most: quote it in a review, an issue or a
/// design document, with the section it came from.
///
/// ```
/// > The selected text, as it reads in the document.
///
/// — [RFC 9110, Section 8.3](https://www.rfc-editor.org/rfc/rfc9110#section-8.3)
/// ```
///
/// The citation line is `CitationFormatter`'s Markdown style, the Cite menu's, so the
/// two cannot disagree, and it links the public rfc-editor.org page, which works for a
/// reader without the app. The text is `SelectionText`'s, so a reference reads as its
/// label, as Copy writes it.
public enum QuoteCitation {
  /// The flavours for the pasteboard. The Markdown also goes in the plain-text flavour:
  /// GitHub, Slack and most editors paste plain text, and `> quote` and a Markdown link
  /// read well as text anyway.
  public struct Quote {
    /// The uniform type the Markdown is also written under.
    public static let markdownType = "net.daringfireball.markdown"

    public var markdown: String
    /// The quote as text and the citation as a real link, for rich targets such as Mail
    /// and Notes.
    public var rich: NSAttributedString

    /// `rich` as RTF, the flavour rich targets read.
    public var rtf: Data? {
      try? rich.data(
        from: NSRange(location: 0, length: rich.length),
        documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
    }
  }

  /// The number of the section a selection starting at `offset` is cited from: the
  /// nearest section anchor at or before it. Only a section counts, not a figure or a
  /// paragraph anchor, so the citation names what a reader looks up; nil before the
  /// first section, where the document alone is cited. A selection spanning sections
  /// cites the first.
  public static func section(at offset: Int, anchors: AnchorIndex, numbers: [String: String])
    -> String?
  {
    anchors.sections.anchor(at: offset).flatMap { numbers[$0] }
  }

  /// The quote for `range` of a built document's text, cited from the section it
  /// starts in, or nil when the range selects nothing of it.
  public static func quote(
    of range: NSRange, in built: BuiltDocument, document: DocumentID,
    sectionNumbers: [String: String]
  ) -> Quote? {
    guard range.length > 0, NSMaxRange(range) <= built.text.length else { return nil }
    return quote(
      of: built.text.attributedSubstring(from: range), document: document,
      section: section(at: range.location, anchors: built.anchors, numbers: sectionNumbers))
  }

  public static func quote(
    of selection: NSAttributedString, document: DocumentID, section: String?
  ) -> Quote {
    let blocks = blocks(of: selection)
    let quoted = blocks.map { block in
      let lines = block.isVerbatim ? ["```"] + block.lines + ["```"] : block.lines
      return lines.map { $0.isEmpty ? ">" : "> \($0)" }.joined(separator: "\n")
    }

    // `short` and `markdown` read only the number; the rest of the metadata is not
    // needed, and not having it -- a document the index does not list -- costs nothing.
    let metadata = RFCMetadata(id: document, title: "", date: PublicationDate(year: 0))
    let formatter = CitationFormatter()
    let citation = formatter.cite(metadata, section: section, style: .markdown)
    let label = formatter.cite(metadata, section: section, style: .short)
    let url = CitationFormatter.url(for: document, section: section)

    let text = blocks.map { $0.lines.joined(separator: "\n") }.joined(separator: "\n\n")
    let rich = NSMutableAttributedString(string: text + "\n\n— ")
    rich.append(NSAttributedString(string: label, attributes: [.link: url]))
    return Quote(
      markdown: quoted.joined(separator: "\n>\n") + "\n\n— " + citation, rich: rich)
  }

  /// A run of the selection that is quoted as one Markdown block: a paragraph, or the
  /// consecutive lines of a verbatim block, which are fenced so Markdown neither
  /// reflows them nor collapses their spaces.
  private struct Block {
    var lines: [String]
    var isVerbatim: Bool
  }

  /// The selection's blocks. The reader ends every paragraph, heading and list item
  /// with a single line break and draws the gap between them as paragraph spacing,
  /// so each line of prose is a paragraph of its own; only a verbatim block's lines
  /// belong together. A reference reads as its label, through `SelectionText`.
  private static func blocks(of selection: NSAttributedString) -> [Block] {
    var blocks: [Block] = []
    let string = selection.string as NSString
    string.enumerateSubstrings(
      in: NSRange(location: 0, length: string.length), options: .byParagraphs
    ) { _, range, enclosingRange, _ in
      let line = SelectionText.plainText(of: selection.attributedSubstring(from: range))
        .trimmingTrailingSpaces()
      // An empty line has no character of its own; its line break carries the attribute.
      let isVerbatim =
        enclosingRange.length > 0
        && selection.attribute(.rfcVerbatim, at: enclosingRange.location, effectiveRange: nil)
          != nil
      if isVerbatim, blocks.last?.isVerbatim == true {
        blocks[blocks.count - 1].lines.append(line)
      } else if isVerbatim || !line.isEmpty {
        blocks.append(Block(lines: [line], isVerbatim: isVerbatim))
      }
    }
    return blocks
  }
}

extension String {
  fileprivate func trimmingTrailingSpaces() -> String {
    var result = self
    while result.last == " " || result.last == "\t" { result.removeLast() }
    return result
  }
}
