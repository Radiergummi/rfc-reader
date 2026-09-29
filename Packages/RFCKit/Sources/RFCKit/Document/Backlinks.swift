import Foundation

/// A section that refers to another place in the same document (#183).
public struct Backlink: Sendable, Hashable {
  /// The anchor of the citing section, or nil for the abstract in the front matter.
  public var section: String?
  /// How many times that section refers there.
  public var count: Int

  public init(section: String?, count: Int) {
    self.section = section
    self.count = count
  }
}

/// Which sections of a document refer to which others, like a wiki's backlinks.
///
/// The rule agreed on #183: a reference to a section, or to anything its own blocks
/// carry an anchor for -- a figure, a table, a paragraph -- is a backlink of that
/// section, and a reference to a subsection is the subsection's alone. So is a
/// reference made in a subsection. A section referring to itself is left out, and so
/// is a bibliography, as a target and as a citing place: a citation names the work,
/// not the row that lists it, and the reader leaves the bibliography out of the body.
/// Only references to anchors count; which other documents cite this one is the
/// corpus's to answer (#174).
public enum Backlinks {
  /// Keyed by the anchor of the section referred to. Each list is in document order
  /// of the citing sections, the abstract first.
  public static func within(_ document: RFCDocument) -> [String: [Backlink]] {
    let sections = document.allSections.filter { !RFCXMLSerializer.isReferences($0) }
    var holder: [String: String] = [:]
    for section in sections {
      holder[section.anchor] = section.anchor
      for anchor in section.blocks.flattened.flatMap(\.anchors) {
        holder[anchor] = section.anchor
      }
    }
    let citing = Set(sections.map(\.anchor))
    var backlinks: [String: [Backlink]] = [:]
    for place in document.proseInlinesBySection
    where place.sectionAnchor.map(citing.contains) ?? true {
      var counts: [String: Int] = [:]
      var order: [String] = []
      for inline in place.inlines {
        guard case .crossReference(let xref) = inline, case .anchor(let anchor) = xref.target,
          let section = holder[anchor], section != place.sectionAnchor
        else { continue }
        if counts[section] == nil { order.append(section) }
        counts[section, default: 0] += 1
      }
      for section in order {
        backlinks[section, default: []].append(
          Backlink(section: place.sectionAnchor, count: counts[section] ?? 0))
      }
    }
    return backlinks
  }
}
