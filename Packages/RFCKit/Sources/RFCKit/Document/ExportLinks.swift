import Foundation

/// Where a link to a place in the same document goes, in a document written out of
/// the app (#377, #642).
public enum InDocumentLinks: Sendable, Hashable {
  /// To the anchor, `#section-4.2`: the file is read on its own, and its anchors are
  /// the reader's. What an export writes.
  case fragments
  /// To the place on rfc-editor.org, `https://www.rfc-editor.org/rfc/rfc9110#section-4.2`:
  /// for text read apart from the document it came from, such as a section an agent
  /// is given. A document with no number links to the anchor all the same.
  case absolute
}

/// The links the serializers write: one rule for each kind of cross reference, so
/// the Markdown and the HTML of a document link to the same places.
struct ExportLinks {
  let document: RFCDocument
  let inDocument: InDocumentLinks
  /// The files of a document cut into several (an EPUB's content documents, #408);
  /// nil for one file. Every link to an anchor then names the file it is in.
  var chapterFiles: ChapterFiles?

  struct ChapterFiles {
    /// The file each anchor is in.
    var files: [String: String]
    /// Where a link to an anchor in none of them goes: the first file's top, so
    /// that it still opens somewhere.
    var fallback: String
  }

  /// Every anchor the document has: a link to one it lacks, such as one out of a
  /// section exported alone (#386), goes to the document on rfc-editor.org.
  private let anchors: Set<String>

  init(document: RFCDocument, inDocument: InDocumentLinks) {
    self.document = document
    self.inDocument = inDocument
    anchors = document.anchors
  }

  /// Where `reference` goes.
  func href(for reference: CrossReference) -> String {
    switch reference.target {
    case .anchor(let place):
      return href(forAnchor: document.anchor(forPlace: place))
    case .document(let id, let section, _):
      return CitationFormatter.url(for: id, section: section).absoluteString
    case .entrySection(let entry, _, _, let url):
      return url?.absoluteString ?? href(forAnchor: entry)
    }
  }

  /// Where a link to `anchor`, in this document, goes.
  func href(forAnchor anchor: String) -> String {
    if !anchors.contains(anchor), let id = document.header.id {
      return RFCLink(id: id, anchor: anchor).webURL.absoluteString
    }
    if let chapterFiles {
      return chapterFiles.files[anchor].map { "\($0)#\(anchor)" } ?? chapterFiles.fallback
    }
    guard inDocument == .absolute, let id = document.header.id else { return "#" + anchor }
    return RFCLink(id: id, anchor: anchor).webURL.absoluteString
  }

  /// Where a bibliography entry's title links: the address it gives, or the page of
  /// the document it names. Nil for an entry that is neither.
  static func url(of entry: Reference) -> URL? {
    if let url = entry.url { return url }
    guard let id = entry.documentID else { return nil }
    return CitationFormatter.url(for: id)
  }

  /// `Normative` or `Informative`, as a list's title says; nil when it says neither.
  static func kindName(_ kind: ReferenceList.Kind) -> String? {
    switch kind {
    case .normative: "Normative"
    case .informative: "Informative"
    case .unknown: nil
    }
  }

  /// `RFC 9110 · June 2022 · R. Fielding, M. Nottingham`: what a document's title is
  /// followed by.
  static func byline(of header: DocumentHeader) -> String {
    let authors = header.authors.map(\.displayName).joined(separator: ", ")
    return [header.id?.displayName, header.date?.formatted, authors.isEmpty ? nil : authors]
      .compactMap { $0 }.joined(separator: " · ")
  }
}
