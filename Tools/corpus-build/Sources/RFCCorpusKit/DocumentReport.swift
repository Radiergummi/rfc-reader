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
  public var overridden: Bool
  public var warnings: [String]
  /// Why the output is not RFCXML: `[]` when it validates, nil when the run was not
  /// asked to check (`--schema`). See `SchemaCheck.Cause` for what each entry means.
  public var schema: [String]?

  /// Counts the blocks of `document`, and warns about the shapes a failed conversion
  /// leaves: no number, no title, no sections, no prose, more artwork than prose.
  public init(document: RFCDocument, id: String, overridden: Bool) {
    var paragraphs = 0
    var lists = 0
    var artwork = 0
    var references = 0
    func count(_ blocks: [Block]) {
      for block in blocks {
        switch block {
        case .paragraph: paragraphs += 1
        case .list(let list):
          lists += 1
          for item in list.items {
            count(item.blocks)
          }
        case .definitionList(let items):
          for item in items {
            count(item.definition)
          }
        case .preformatted: artwork += 1
        case .figure(let figure): count(figure.blocks)
        case .blockQuote(let inner), .aside(let inner): count(inner)
        case .references(let list): references += list.entries.count
        case .table: break
        }
      }
    }
    for section in document.allSections {
      count(section.blocks)
    }

    var warnings: [String] = []
    if document.header.id == nil { warnings.append("no RFC number recognised in front matter") }
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
    self.overridden = overridden
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
