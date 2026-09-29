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
/// reference made in a subsection. A section referring to itself is left out. So is a
/// bibliography entry as a target, since a citation names the work, not the row that
/// lists it; and a section that is only a bibliography as a citing place, since the
/// reader leaves it out of the body and a backlink there would lead nowhere. A
/// section with prose beside its bibliography is drawn, and counts like any other.
/// Only references to anchors count; which other documents cite this one is the
/// corpus's to answer (#174).
public enum Backlinks {
  /// Keyed by the anchor of the section referred to. Each list is in document order
  /// of the citing sections, the abstract first.
  public static func within(_ document: RFCDocument) -> [String: [Backlink]] {
    var holder: [String: String] = [:]
    var bibliographies: Set<String> = []
    for section in document.allSections {
      holder[section.anchor] = section.anchor
      for block in section.blocks.flattened {
        if case .references = block { continue }
        for anchor in block.anchors {
          holder[anchor] = section.anchor
        }
      }
      let onlyReferences = section.blocks.allSatisfy { block in
        if case .references = block { return true } else { return false }
      }
      if !section.blocks.isEmpty, onlyReferences {
        bibliographies.insert(section.anchor)
      }
    }
    var backlinks: [String: [Backlink]] = [:]
    for place in document.proseInlinesBySection
    where !(place.sectionAnchor.map(bibliographies.contains) ?? false) {
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
