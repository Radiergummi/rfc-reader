import RFCKit

/// What the reader's toolbars *say* when they act on the document on screen.
///
/// Both platforms offer the same three actions — bookmark it, cite it, link to the
/// section being read — and until now each wrote its own answer to what they mean.
/// The two had already drifted: a new bookmark stored a different title depending on
/// which toolbar made it, because one of them knew a fallback the other did not.
///
/// So the wording lives here, once, where it can be tested. The App target keeps the
/// half that is genuinely platform work — reading and writing SwiftData, reaching the
/// pasteboard — and asks these for the string to use.
public enum DocumentActions {
  /// The title to file a new bookmark under.
  ///
  /// The index is the first source because it is the library's own name for the
  /// document and the same one the list shows. It does not cover everything,
  /// though — an RFC opened by number before the index has loaded, or one missing
  /// from it — and in that case the document has just been parsed and its header
  /// says so. `displayName` is the last resort and always works: `RFC 9110`.
  public static func bookmarkTitle(
    metadata: RFCMetadata?,
    documentTitle: String?,
    id: DocumentID
  ) -> String {
    metadata?.title ?? documentTitle ?? id.displayName
  }

  /// The citation to put on the pasteboard.
  ///
  /// A section is part of the citation for every style but BibTeX, whose entry
  /// describes the document as a whole: there is no field in it that says "and I
  /// mean §4.2", so a section silently becomes part of the title or is dropped by
  /// whoever renders the entry. Better to cite the document, which is what a
  /// BibTeX key is for.
  public static func citation(
    _ metadata: RFCMetadata,
    section: String?,
    style: CitationStyle
  ) -> String {
    CitationFormatter().cite(metadata, section: style == .bibtex ? nil : section, style: style)
  }

  /// The shareable link to the place being read, as a string for the pasteboard.
  ///
  /// The web URL rather than the app's own `rfc://`: this is copied to be pasted
  /// somewhere else, and the reader opens an rfc-editor.org link anyway.
  public static func sectionLink(id: DocumentID, section: String?) -> String {
    RFCLink(id: id, section: section).webURL.absoluteString
  }
}
