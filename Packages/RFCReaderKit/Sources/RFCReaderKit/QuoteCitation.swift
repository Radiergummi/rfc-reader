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
  /// The flavors for the pasteboard, each target taking the richest it reads.
  public struct Quote {
    /// The uniform type the Markdown is written under.
    public static let markdownType = "net.daringfireball.markdown"

    public var markdown: String
    /// The plain-text flavor is the Markdown too. A web page reads only plain text and
    /// HTML, never the Markdown flavor, so GitHub keeps the `>` quote only if the plain
    /// text has it; Slack and chat apps paste plain text as well.
    public var plainText: String { markdown }
    /// A `blockquote` of one `p` per paragraph and one `pre` per figure, and the
    /// citation a link after it. No styles, so the target's own apply.
    public var html: String
    /// The quote as text and the citation as a real link, for rich targets such as Mail
    /// and Notes.
    public var rich: NSAttributedString

    /// `rich` as RTF, the flavor rich targets read.
    public var rtf: Data? {
      try? rich.data(
        from: NSRange(location: 0, length: rich.length),
        documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
    }
  }

  /// The number of the section a selection starting at `offset` is cited from: that of
  /// the nearest section anchor at or before it. Only a section counts, not a figure or
  /// a paragraph anchor, so the citation names what a reader looks up; nil before the
  /// first section and in an unnumbered one, where the document alone is cited. A
  /// selection spanning sections cites the first.
  public static func section(at offset: Int, anchors: AnchorIndex) -> String? {
    let sections = anchors.sections
    return sections.index(at: offset).flatMap { sections.entries[$0].number }
  }

  /// The quote for `range` of a built document's text, cited from the section it
  /// starts in, or nil when the range selects nothing of it.
  public static func quote(of range: NSRange, in built: BuiltDocument, document: DocumentID)
    -> Quote?
  {
    guard range.length > 0, NSMaxRange(range) <= built.text.length else { return nil }
    // Cited from the first character quoted: a selection dragged from the end of one
    // section's last line opens on its line break, but quotes only the next section.
    let first = (built.text.string as NSString).rangeOfCharacter(
      from: CharacterSet.whitespacesAndNewlines.inverted, options: [], range: range
    ).location
    return quote(
      of: built.text.attributedSubstring(from: range), document: document,
      section: section(at: first == NSNotFound ? range.location : first, anchors: built.anchors))
  }

  public static func quote(
    of selection: NSAttributedString, document: DocumentID, section: String?
  ) -> Quote {
    let blocks = blocks(of: selection)
    let quoted = blocks.map { block in
      // A `<` in prose is an entity, or GitHub takes `<field-name>` for a tag and
      // drops it; `\<` renders only where Markdown is CommonMark, an entity wherever
      // it becomes HTML. A fence is taken literally, so its lines are left as drawn.
      let lines: [String]
      if let box = block.box {
        // Longer than any run of backticks in the block, or its own fence line would
        // close this one. A source-code block's type is the info string.
        let fence = String(repeating: "`", count: max(3, longestBacktickRun(in: block.lines) + 1))
        let info = box.content.kind == .sourceCode ? box.content.type ?? "" : ""
        lines = [fence + info] + block.lines + [fence]
      } else {
        lines = block.lines.map { $0.replacingOccurrences(of: "<", with: "&lt;") }
      }
      return lines.map { $0.isEmpty ? ">" : "> \($0)" }.joined(separator: "\n")
    }

    // `short` and `markdown` read only the number; the rest of the metadata is not
    // needed, and not having it -- a document the index does not list -- costs nothing.
    let metadata = RFCMetadata(id: document, title: "", date: PublicationDate(year: 0))
    let citation = CitationFormatter.cite(metadata, section: section, style: .markdown)
    let label = CitationFormatter.cite(metadata, section: section, style: .short)
    let url = CitationFormatter.url(for: document, section: section)

    // A figure in a fixed-pitch font, or a rich target lays it out in a proportional
    // one and its columns fall apart. Menlo rather than the system's monospaced font,
    // which RTF can only name by a private name no other platform resolves.
    let fixedPitch =
      PlatformFont(name: "Menlo-Regular", size: 12)
      ?? .monospacedSystemFont(ofSize: 12, weight: .regular)
    let rich = NSMutableAttributedString()
    for block in blocks {
      rich.append(
        NSAttributedString(
          string: block.lines.joined(separator: "\n") + "\n\n",
          attributes: block.isVerbatim ? [.font: fixedPitch] : [:]))
    }
    rich.append(NSAttributedString(string: "— "))
    rich.append(NSAttributedString(string: label, attributes: [.link: url]))

    // The charset, or a target reading the flavor as Latin-1 garbles the dash.
    let html =
      (["<meta charset=\"utf-8\">", "<blockquote>"]
      + blocks.map { block in
        let content = escapingHTML(block.lines.joined(separator: "\n"))
        return block.isVerbatim ? "<pre>\(content)</pre>" : "<p>\(content)</p>"
      }
      + [
        "</blockquote>",
        "<p>— <cite><a href=\"\(escapingHTML(url.absoluteString))\">\(escapingHTML(label))</a></cite></p>",
      ]).joined(separator: "\n")

    return Quote(
      markdown: quoted.joined(separator: "\n>\n") + "\n\n— " + citation,
      html: html,
      rich: rich)
  }

  /// `text` as HTML text or an attribute value: the characters markup is made of, as
  /// entities.
  private static func escapingHTML(_ text: String) -> String {
    text
      .replacingOccurrences(of: "&", with: "&amp;")
      .replacingOccurrences(of: "<", with: "&lt;")
      .replacingOccurrences(of: ">", with: "&gt;")
      .replacingOccurrences(of: "\"", with: "&quot;")
      .replacingOccurrences(of: "'", with: "&#39;")
  }

  /// A run of the selection that is quoted as one Markdown block: a paragraph, or the
  /// consecutive lines of a verbatim block, which are fenced so Markdown neither
  /// reflows them nor collapses their spaces.
  private struct Block {
    var lines: [String]
    /// The verbatim block the lines are from; nil for prose.
    var box: VerbatimBox?
    var isVerbatim: Bool { box != nil }
  }

  private static func longestBacktickRun(in lines: [String]) -> Int {
    var longest = 0
    for line in lines {
      var run = 0
      for character in line {
        run = character == "`" ? run + 1 : 0
        longest = max(longest, run)
      }
    }
    return longest
  }

  /// The selection's blocks. The reader ends every paragraph, heading and list item
  /// with a single line break and draws the gap between them as paragraph spacing,
  /// so each line of prose is a paragraph of its own; only a verbatim block's lines
  /// belong together, told apart from the next block's by their box. The label the
  /// reader puts above source code is not the code, and is left out. A reference reads
  /// as its label, through `SelectionText`.
  private static func blocks(of selection: NSAttributedString) -> [Block] {
    var blocks: [Block] = []
    let string = selection.string as NSString
    string.enumerateSubstrings(
      in: NSRange(location: 0, length: string.length), options: .byParagraphs
    ) { _, range, enclosingRange, _ in
      let line = SelectionText.plainText(of: selection.attributedSubstring(from: range))
        .trimmingTrailingSpaces()
      // An empty line has no character of its own; its line break carries the attribute.
      let box =
        enclosingRange.length > 0
        ? selection.attribute(.rfcVerbatim, at: enclosingRange.location, effectiveRange: nil)
          as? VerbatimBox
        : nil
      if let box, let last = blocks.last?.box, last === box {
        blocks[blocks.count - 1].lines.append(line)
      } else if let box {
        // The label is the first line of its block, and reads as the type uppercased.
        let isLabel = box.content.kind == .sourceCode && line == box.content.type?.uppercased()
        blocks.append(Block(lines: isLabel ? [] : [line], box: box))
      } else if !line.isEmpty {
        blocks.append(Block(lines: [line], box: nil))
      }
    }
    return blocks.filter { !$0.lines.isEmpty }
  }
}

extension String {
  fileprivate func trimmingTrailingSpaces() -> String {
    var result = self
    while result.last == " " || result.last == "\t" { result.removeLast() }
    return result
  }
}
