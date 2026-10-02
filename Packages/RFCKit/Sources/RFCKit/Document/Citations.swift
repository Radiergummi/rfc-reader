import Foundation

/// One document's citations of another, from one place in it (#174): what the corpus
/// index records, so that which documents cite a document -- which no one document
/// can say -- is a lookup.
public struct Citation: Sendable, Hashable, Codable {
  /// Where in the citing document the citations are.
  public enum Place: Sendable, Hashable, Codable {
    case abstract
    /// A section, by anchor: its heading and its own blocks, not its subsections'.
    case section(String)
    /// A bibliography entry the prose never cites.
    case bibliography
  }

  public var cited: DocumentID
  public var place: Place
  /// How many times the place cites the document; 1 for `.bibliography`.
  public var count: Int
  /// The kind of the reference list whose entry the citation names, or nil when no
  /// entry names the document: a bare "RFC 3986" in prose that the bibliography
  /// leaves out.
  public var kind: ReferenceList.Kind?

  public init(cited: DocumentID, place: Place, count: Int, kind: ReferenceList.Kind?) {
    self.cited = cited
    self.place = place
    self.count = count
    self.kind = kind
  }
}

/// Which documents a document cites, from where, and how (#174).
///
/// A citation is a cross reference to another document in what the reader draws as
/// prose, `RFCDocument.drawnProseBySection`, where `Backlinks` counts too: the
/// abstract, the headings and the body, but not a bibliography's annotations. A
/// document the bibliography lists and the prose never cites is still cited, from
/// `.bibliography`. Never the document itself, which its abstract and headings are
/// the likeliest to name.
public enum Citations {
  /// In document order: the places as the reader meets them, and within one place the
  /// documents in the order it first cites them; the bibliography last, in its order.
  ///
  /// `citing` is the document's own ID, which it never cites: its header's unless
  /// given, as the index gives the one its file names.
  public static func of(_ document: RFCDocument, citing: DocumentID? = nil) -> [Citation] {
    let own = citing ?? document.header.id
    var kindByEntry: [String: ReferenceList.Kind] = [:]
    var kindByDocument: [DocumentID: ReferenceList.Kind] = [:]
    var listed: [(id: DocumentID, kind: ReferenceList.Kind)] = []
    for case .references(let list) in document.blocks {
      for entry in list.entries {
        kindByEntry[entry.anchor] = list.kind
        guard let id = entry.documentID else { continue }
        if kindByDocument[id] == nil { kindByDocument[id] = list.kind }
        listed.append((id, list.kind))
      }
    }

    var citations: [Citation] = []
    var cited: Set<DocumentID> = []
    for (anchor, inlines) in document.drawnProseBySection {
      let place = anchor.map(Citation.Place.section) ?? .abstract
      var found: [Citation] = []
      for inline in inlines {
        guard case .crossReference(let xref) = inline,
          case .document(let id, _, let entry) = xref.target, id != own
        else { continue }
        if let index = found.firstIndex(where: { $0.cited == id }) {
          found[index].count += 1
        } else {
          let kind = entry.flatMap { kindByEntry[$0] } ?? kindByDocument[id]
          found.append(Citation(cited: id, place: place, count: 1, kind: kind))
        }
      }
      citations += found
      cited.formUnion(found.map(\.cited))
    }

    var seen: Set<DocumentID> = []
    for (id, kind) in listed where id != own && !cited.contains(id) {
      guard seen.insert(id).inserted else { continue }
      citations.append(Citation(cited: id, place: .bibliography, count: 1, kind: kind))
    }
    return citations
  }
}
