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
    public var markdown: String
    /// The quote as text and the citation as a real link, for rich targets such as Mail
    /// and Notes.
    public var rich: NSAttributedString
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

  public static func quote(
    of selection: NSAttributedString, document: DocumentID, section: String?
  ) -> Quote {
    var lines = SelectionText.plainText(of: selection)
      .components(separatedBy: .newlines)
      .map { $0.trimmingTrailingSpaces() }
    // A selection that runs to the end of its paragraph takes the line break with it,
    // and a quoted empty line after the text would say nothing.
    while lines.last?.isEmpty == true { lines.removeLast() }
    let quoted = lines.map { $0.isEmpty ? ">" : "> \($0)" }.joined(separator: "\n")

    // `short` and `url` read only the number; the rest of the metadata is not needed,
    // and not having it -- a document the index does not list -- costs nothing.
    let metadata = RFCMetadata(id: document, title: "", date: PublicationDate(year: 0))
    let label = CitationFormatter().cite(metadata, section: section, style: .short)
    let url = CitationFormatter.url(for: document, section: section)

    let rich = NSMutableAttributedString(string: lines.joined(separator: "\n") + "\n\n— ")
    rich.append(NSAttributedString(string: label, attributes: [.link: url]))
    return Quote(markdown: "\(quoted)\n\n— [\(label)](\(url.absoluteString))", rich: rich)
  }
}

extension String {
  fileprivate func trimmingTrailingSpaces() -> String {
    var result = self
    while result.last == " " || result.last == "\t" { result.removeLast() }
    return result
  }
}
