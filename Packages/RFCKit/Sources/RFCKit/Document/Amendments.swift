import Foundation

/// A section of another RFC that a document amends: where it cites a section of a
/// document it says it updates (#179).
///
/// A row in the shape the corpus extractors take (#174): a value that stands alone,
/// so a pack can hold every document's and a reader can ask which sections of the
/// open document later ones amend.
public struct Amendment: Sendable, Hashable, Codable {
  /// The document amended.
  public var amended: DocumentID
  /// Its section, as the citation names it, in the form `RFCLink.section` takes: a
  /// number, `4.2`, or `B` for an appendix, or an anchor, `appendix-1`, for an
  /// appendix numbered like a section.
  public var section: String
  /// The amending document.
  public var amending: DocumentID
  /// The anchor of the amending document's section the citation sits in, or nil for
  /// the abstract in its front matter. A converted legacy abstract that holds more
  /// than `<abstract>` can is the body section `abstract`, and has that anchor.
  public var amendingSection: String?

  public init(
    amended: DocumentID, section: String, amending: DocumentID, amendingSection: String?
  ) {
    self.amended = amended
    self.section = section
    self.amending = amending
    self.amendingSection = amendingSection
  }
}

/// Which sections of other RFCs a document amends.
///
/// The rule is the broad one agreed on #179: every citation of a *section* of a
/// document the amending one updates, wherever it sits. A narrower rule, only inside
/// a section titled after the amended document (`Updates to RFC 2119`), would be more
/// precise, and would miss every document that states its amendments in its
/// introduction. Only documents the header says it updates count, so an ordinary
/// citation of another document's section is never read as an amendment; and a
/// citation of a whole document names no section, which the document-level status
/// already covers. A section that holds a bibliography amends nothing either: a
/// citation in a reference's annotation describes that entry. A document that does
/// not state its own number amends nothing, since a row that cannot say which
/// document amends answers nothing.
public enum Amendments {
  public static func links(in document: RFCDocument) -> [Amendment] {
    let updated = Set(document.header.updates)
    guard let amending = document.header.id, !updated.isEmpty else { return [] }
    let bibliographies: Set<String?> = Set(
      document.allSections.filter(RFCXMLSerializer.isReferences).map(\.anchor))
    var seen: Set<Amendment> = []
    var links: [Amendment] = []
    for place in document.proseInlinesBySection
    where !bibliographies.contains(place.sectionAnchor) {
      for inline in place.inlines {
        guard case .crossReference(let xref) = inline,
          case .document(let id, let section?, _) = xref.target,
          updated.contains(id)
        else { continue }
        let link = Amendment(
          amended: id,
          section: section,
          amending: amending,
          amendingSection: place.sectionAnchor
        )
        if seen.insert(link).inserted {
          links.append(link)
        }
      }
    }
    return links
  }
}
