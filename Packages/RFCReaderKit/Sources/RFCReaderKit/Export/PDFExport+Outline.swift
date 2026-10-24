import CoreGraphics
import Foundation
import PDFKit

extension PDFExport {
  /// Gives `document` `outline`, each entry going to its anchor's place in
  /// `destinations`. An entry whose anchor has no place is left out, its
  /// subsections with it.
  public static func setOutline(
    _ outline: [OutlineEntry], destinations: [String: Place], in document: PDFDocument
  ) {
    func add(_ entries: [OutlineEntry], to parent: PDFOutline) {
      for entry in entries {
        guard let place = destinations[entry.anchor], let page = document.page(at: place.page)
        else { continue }
        let item = PDFOutline()
        item.label = entry.title
        item.destination = PDFDestination(page: page, at: place.point)
        parent.insertChild(item, at: parent.numberOfChildren)
        add(entry.children, to: item)
      }
    }
    let root = PDFOutline()
    add(outline, to: root)
    document.outlineRoot = root
  }
}
