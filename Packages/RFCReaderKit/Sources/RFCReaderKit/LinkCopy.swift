import Foundation
import RFCKit

#if canImport(UIKit)
  import UIKit
#else
  import AppKit
#endif

/// What Copy and Share hand out for a reference (#431): a link anyone can open.
///
/// A reference's own URL is the reader's (`rfc://9110`, an anchor in this
/// document, a bibliography entry), which nothing outside the app opens. So a
/// document is shared by its rfc-editor.org URL, as `DocumentActions.sectionLink`
/// is, and a bibliography entry by the URL it names, labelled with its title.
public struct LinkCopy: Equatable, Sendable {
  public let url: URL
  /// `RFC 9110: HTTP Semantics`, or the bare designation where the index has no
  /// title; a bibliography entry's own title.
  public let label: String

  /// Nil for a link that is not the reader's, and for a bibliography entry that
  /// names no URL: there is nothing of ours to hand out for either.
  public static func forLink(
    _ link: URL, from currentDocument: DocumentID, in index: RFCIndex?,
    bibliography: [ReferenceGroup]
  ) -> LinkCopy? {
    if let anchor = DocumentTextBuilder.anchor(from: link) {
      // The RFC Editor's HTML carries the document's own anchors as ids, and a
      // section's is the `section-4.2` a number would have made.
      var components = URLComponents(
        url: RFCEditorEndpoints.base.appending(path: "rfc/\(currentDocument.fileStem)"),
        resolvingAgainstBaseURL: false)
      components?.fragment = anchor
      guard let url = components?.url else { return nil }
      return LinkCopy(url: url, label: label(for: currentDocument, in: index))
    }
    if let anchor = DocumentTextBuilder.reference(from: link) {
      guard let entry = bibliography.entry(anchor: anchor), let url = entry.url else {
        return nil
      }
      return LinkCopy(url: url, label: entry.title)
    }
    guard let reference = RFCLink(url: link) else { return nil }
    return LinkCopy(url: reference.webURL, label: label(for: reference.id, in: index))
  }

  private static func label(for id: DocumentID, in index: RFCIndex?) -> String {
    guard let title = index?[id]?.title else { return id.displayName }
    return "\(id.displayName): \(title)"
  }

  /// The label as a link, for a pasteboard's HTML.
  public var html: String {
    let href = PasteboardMarkup.escaped(url.absoluteString)
    return PasteboardMarkup.html("<a href=\"\(href)\">\(PasteboardMarkup.escaped(label))</a>")
  }

  /// The label as a link, for a pasteboard's RTF.
  public var rtf: Data? {
    PasteboardMarkup.rtf(NSAttributedString(string: label, attributes: [.link: url]))
  }
}
