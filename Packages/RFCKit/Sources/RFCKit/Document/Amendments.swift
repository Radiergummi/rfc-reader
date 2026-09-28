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
  /// Its section, as the citation names it: `4.2`, or `B` for an appendix. What
  /// `RFCLink` takes, not an anchor.
  public var section: String
  /// The amending document, when it states its own number.
  public var amending: DocumentID?
  /// The anchor of the amending document's section the citation sits in, or nil for
  /// its abstract.
  public var amendingSection: String?

  public init(
    amended: DocumentID, section: String, amending: DocumentID?, amendingSection: String?
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
/// already covers.
public enum Amendments {
  public static func links(in document: RFCDocument) -> [Amendment] {
    let updated = Set(document.header.updates)
    guard !updated.isEmpty else { return [] }
    var seen: Set<Amendment> = []
    var links: [Amendment] = []
    func collect(_ inlines: [Inline], from anchor: String?) {
      for inline in inlines.flattened {
        guard case .crossReference(let xref) = inline,
          case .document(let id, let section?) = xref.target, updated.contains(id)
        else { continue }
        let link = Amendment(
          amended: id, section: section, amending: document.header.id, amendingSection: anchor)
        if seen.insert(link).inserted { links.append(link) }
      }
    }
    for block in document.header.abstract.flattened {
      for run in block.proseRuns { collect(run, from: nil) }
    }
    // Each section's own heading and blocks, not its subsections': a citation
    // belongs to the section it is read in.
    for section in document.allSections {
      collect(section.title, from: section.anchor)
      for block in section.blocks.flattened {
        for run in block.proseRuns { collect(run, from: section.anchor) }
      }
    }
    return links
  }
}
