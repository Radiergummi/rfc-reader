import Foundation
import RFCKit

/// One document's entry in `report.json`: what its conversion recovered, and what looks
/// wrong with it.
public struct DocumentReport: Codable, Sendable {
  public var id: String
  public var title: String
  public var sections: Int
  public var paragraphs: Int
  public var lists: Int
  public var artwork: Int
  public var references: Int
  public var resolvedDocuments: Int
  /// Lines dropped as page furniture. Compared across runs, this is what shows
  /// a furniture rule deleting the body: the block counts cannot.
  public var furniture: Int?
  /// How the document was corrected by hand, nil when it was not.
  public var override: Override?
  /// Why its patch could not be applied, nil when it has none or it applied. A
  /// document whose patch failed has no output, and the run fails at its end.
  public var failure: String?
  public var warnings: [String]
  /// Why the output is not RFCXML: `[]` when it validates, nil when the run was not
  /// asked to check (`--schema`). See `SchemaCheck.Cause` for what each entry means.
  public var schema: [String]?
  /// Why no XML was written for the document, nil when it was converted. A skipped
  /// document is neither checked nor counted against the schema, and the legacy
  /// pack's manifest lists it (`Manifest.skips(inReport:)`).
  public var skipped: Manifest.SkipReason?

  /// The kinds of hand correction in `corpus/overrides/` (#197).
  public enum Override: String, Codable, Sendable {
    /// An RFC 5261 patch, applied to the converter's output.
    case patch
    /// A whole document published in place of the converter's output.
    case snapshot
  }

  /// Counts the blocks of `document`, and warns about the shapes a failed conversion
  /// leaves: no number, no title, no sections, no prose, more artwork than prose.
  public init(document: RFCDocument, id: String, override: Override? = nil) {
    var paragraphs = 0
    var lists = 0
    var artwork = 0
    var references = 0
    // The sections' blocks, not `document.blocks`: the abstract has never been counted,
    // and counting it now would move every document's numbers against older reports.
    for block in document.allSections.flatMap(\.blocks).flattened {
      switch block {
      case .paragraph: paragraphs += 1
      case .list: lists += 1
      case .preformatted: artwork += 1
      case .references(let list): references += list.entries.count
      case .definitionList, .figure, .blockQuote, .aside, .table: break
      }
    }

    var warnings: [String] = []
    if document.header.id == nil { warnings.append("no RFC number recognized in front matter") }
    if document.header.title.isEmpty { warnings.append("no title") }
    if document.sections.isEmpty { warnings.append("no sections") }
    if paragraphs == 0 { warnings.append("no prose paragraphs") }
    if artwork > paragraphs {
      warnings.append("more artwork than prose (\(artwork) vs \(paragraphs)); check classification")
    }

    self.id = id
    self.title = document.header.title
    self.sections = document.allSections.count
    self.paragraphs = paragraphs
    self.lists = lists
    self.artwork = artwork
    self.references = references
    self.resolvedDocuments = document.referencedDocuments.count
    self.override = override
    self.warnings = warnings
  }

  /// The documents that validated in a `report.json`; nil when it does not decode as
  /// one, or when it comes from a run that did not check, which is no baseline.
  public static func validDocuments(inReport data: Data) -> Set<String>? {
    struct Entry: Decodable {
      var id: String
      var schema: [String]?
    }
    guard let entries = try? JSONDecoder().decode([Entry].self, from: data),
      entries.contains(where: { $0.schema != nil })
    else { return nil }
    return Set(entries.filter { $0.schema == [] }.map(\.id))
  }
}
