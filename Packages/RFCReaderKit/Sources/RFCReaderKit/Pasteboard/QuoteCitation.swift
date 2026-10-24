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
/// The citation line is `CitationFormatter`'s, in the style Settings chose (#712),
/// Markdown unless it chose otherwise, so it and the Cite menu cannot disagree; it
/// links the site Settings chose, the public rfc-editor.org page unless it chose
/// otherwise, which works for a reader without the app. A style that needs the
/// index's entry falls back to Markdown for a document the index doesn't list,
/// BibTeX and xml2rfc, which cite the whole document, always do, and Full does for
/// a series, which it cites member by member. The
/// rich flavors and the HTML link the short citation whatever the style: a rich
/// target shows a link, not a BibTeX entry. The text is `SelectionText`'s, so a
/// reference reads as its label, as Copy writes it.
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
    public var rtf: Data? { PasteboardMarkup.rtf(rich) }
  }

  /// The place (`Section.place`) of the section a selection starting at `offset` is
  /// cited from: that of the nearest section anchor at or before it. Only a section
  /// counts, not a figure or a paragraph anchor, so the citation names what a reader
  /// looks up; nil before the first section and in an unnumbered one, where the
  /// document alone is cited. A selection spanning sections cites the first.
  public static func section(at offset: Int, anchors: AnchorIndex) -> String? {
    let sections = anchors.sections
    return sections.index(at: offset).flatMap { sections.entries[$0].place }
  }

  /// The place `range` of a built document's text is cited from: the section of its
  /// first character, as `section(at:anchors:)` says. A selection dragged from the
  /// end of one section's last line opens on its line break, but quotes only the
  /// next section.
  public static func section(of range: NSRange, in built: BuiltDocument) -> String? {
    let first = (built.text.string as NSString).rangeOfCharacter(
      from: CharacterSet.whitespacesAndNewlines.inverted, options: [], range: range
    ).location
    return section(at: first == NSNotFound ? range.location : first, anchors: built.anchors)
  }

  /// The quote for `range` of a built document's text, cited from the section it
  /// starts in, or nil when the range selects nothing of it. `document` is what is
  /// cited, a series as itself (#656), and `cited` its entry in the index, where it
  /// has one; `settings` say how (#712).
  public static func quote(
    of range: NSRange, in built: BuiltDocument, document: DocumentID,
    cited: CitedDocument? = nil, settings: ReaderSettings = ReaderSettings()
  ) -> Quote? {
    // A translation's words are a machine's, not the RFC's (#749).
    guard !built.isTranslation, range.length > 0, NSMaxRange(range) <= built.text.length
    else { return nil }
    return quote(
      of: built.text.attributedSubstring(from: range), document: document,
      section: section(of: range, in: built), cited: cited, settings: settings)
  }

  public static func quote(
    of selection: NSAttributedString, document: DocumentID, section: String?,
    cited: CitedDocument? = nil, settings: ReaderSettings = ReaderSettings()
  ) -> Quote {
    let blocks = blocks(of: selection, keepingSectionNumbers: settings.copiesSectionNumbers)
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

    // Only the styles that need the index's entry need `cited`; without it, the
    // line is Markdown's, which reads the designation alone. So it is for a style
    // that describes the whole document in lines of its own, BibTeX's or xml2rfc's,
    // which would lose the section and end the quote in an entry, and for a series
    // in the Full style, which lists its members' citations line by line.
    let chosen = settings.citationStyle
    let citesInLines: Bool
    switch cited {
    case .series?: citesInLines = chosen == .full
    case .rfc?, nil: citesInLines = false
    }
    let style =
      !chosen.citesSections || citesInLines || (cited == nil && chosen.needsIndexEntry)
      ? .markdown : chosen
    let citation = DocumentActions.citation(
      cited ?? CitedDocument(bare: document), section: section, style: style,
      site: settings.linkSite)
    let label = CitationFormatter.shortCitation(document, section: section)
    let url = CitationFormatter.url(for: document, section: section, site: settings.linkSite)

    // A figure in a fixed-pitch font, or a rich target lays it out in a proportional
    // one and its columns fall apart. Menlo rather than the system's monospaced font,
    // which RTF can only name by a private name no other platform resolves.
    let fixedPitch =
      PlatformFont(name: "Menlo-Regular", size: 12)
      ?? .monospacedFont(ofSize: 12, weight: .regular)
    let rich = NSMutableAttributedString()
    for block in blocks {
      rich.append(
        NSAttributedString(
          string: block.lines.joined(separator: "\n") + "\n\n",
          attributes: block.isVerbatim ? [.font: fixedPitch] : [:]))
    }
    rich.append(NSAttributedString(string: "— "))
    rich.append(NSAttributedString(string: label, attributes: [.link: url]))

    let escaped = PasteboardMarkup.escaped
    let html = PasteboardMarkup.html(
      (["<blockquote>"]
        + blocks.map { block in
          let content = escaped(block.lines.joined(separator: "\n"))
          return block.isVerbatim ? "<pre>\(content)</pre>" : "<p>\(content)</p>"
        }
        + [
          "</blockquote>",
          "<p>— <cite><a href=\"\(escaped(url.absoluteString))\">\(escaped(label))</a></cite></p>",
        ]).joined(separator: "\n"))

    return Quote(
      markdown: quoted.joined(separator: "\n>\n") + "\n\n— " + citation,
      html: html,
      rich: rich)
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
  private static func blocks(of selection: NSAttributedString, keepingSectionNumbers: Bool)
    -> [Block]
  {
    var blocks: [Block] = []
    let string = selection.string as NSString
    string.enumerateSubstrings(
      in: NSRange(location: 0, length: string.length), options: .byParagraphs
    ) { _, range, enclosingRange, _ in
      let line = SelectionText.plainText(
        of: selection.attributedSubstring(from: range), unfolding: false,
        keepingSectionNumbers: keepingSectionNumbers
      )
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
        // The label is the first line of its block, and the reader's own.
        let isLabel =
          range.length > 0
          && selection.attribute(.rfcReaderOnly, at: range.location, effectiveRange: nil) != nil
        blocks.append(Block(lines: isLabel ? [] : [line], box: box))
      } else {
        // A table row whose cell has a line break is one paragraph (#506), and its
        // lines are quoted as the lines they are, each trimmed as a paragraph is.
        for part in line.split(separator: "\n") {
          let part = String(part).trimmingTrailingSpaces()
          if !part.isEmpty { blocks.append(Block(lines: [part], box: nil)) }
        }
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
