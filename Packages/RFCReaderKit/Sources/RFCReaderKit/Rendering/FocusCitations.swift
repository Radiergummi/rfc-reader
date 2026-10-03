import Foundation
import RFCKit

/// What the focused section cites (#699): the bibliography entries its references
/// name, which Focus pins beside it by filtering the panel's References tab to them.
public enum FocusCitations {
  /// The anchors of the entries cited in the section `anchor` names and its
  /// subsections, from the references the build set there.
  public static func entries(citedIn anchor: String, in built: BuiltDocument, index: FoldingIndex)
    -> Set<String>
  {
    guard let subtree = index.subtree(of: anchor) else { return [] }
    var cited: Set<String> = []
    built.text.enumerateAttribute(
      .rfcReference,
      in: NSRange(location: subtree.lowerBound, length: subtree.count)
    ) { value, _, _ in
      guard let box = value as? ReferenceBox else { return }
      switch box.reference.target {
      case .anchor(let entry), .entrySection(let entry, _, _, _):
        cited.insert(entry)
      case .document(_, _, let entry?):
        cited.insert(entry)
      case .document:
        break
      }
    }
    return cited
  }

  /// `groups` with only the entries `cited` names, and without a group left empty:
  /// what the References tab lists in Focus.
  public static func groups(_ groups: [ReferenceGroup], citing cited: Set<String>)
    -> [ReferenceGroup]
  {
    groups.compactMap { group in
      let entries = group.entries.filter { cited.contains($0.anchor) }
      return entries.isEmpty ? nil : ReferenceGroup(title: group.title, entries: entries)
    }
  }
}
