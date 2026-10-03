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
/// lists it. Only what the reader draws in the body refers, since a backlink has to
/// lead somewhere: not a section that `holdsOnlyReferences`, and not a bibliography's
/// annotations, which are the references panel's. A section with prose beside its
/// bibliography is drawn, and its prose counts like any other.
/// Only references to anchors count; which other documents cite this one is the
/// corpus's to answer (#174).
public enum Backlinks {
  /// Keyed by the anchor of the section referred to. Each list is in document order
  /// of the citing sections, the abstract first.
  public static func within(_ document: RFCDocument) -> [String: [Backlink]] {
    var holder: [String: String] = [:]
    for section in document.allSections {
      holder[section.anchor] = section.anchor
      for block in drawn(section.blocks) {
        for anchor in block.anchors {
          holder[anchor] = section.anchor
        }
      }
    }
    var backlinks: [String: [Backlink]] = [:]
    for place in document.drawnProseBySection {
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

  /// These blocks and every block nested in them, but for a bibliography.
  private static func drawn(_ blocks: [Block]) -> [Block] {
    blocks.flattened.filter { block in
      if case .references = block { return false }
      return true
    }
  }
}
