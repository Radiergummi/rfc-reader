import CoreGraphics
import Foundation

extension PDFExport {
  /// Gives the PDF `context` is drawing `outline`, each entry going to its
  /// anchor's place in `destinations`. An entry whose anchor has no place is left
  /// out, its subsections with it. Call it before the context closes the file.
  ///
  /// Through Core Graphics while the pages are drawn, not through PDFKit
  /// afterwards: PDFKit drops an outline it is given when it writes the file,
  /// while one the drawing wrote survives PDFKit reading the file, adding the
  /// links and writing it again (#990).
  public static func setOutline(
    _ outline: [OutlineEntry], destinations: [String: Place], in context: CGContext
  ) {
    let root = [kCGPDFOutlineChildren: items(outline, destinations: destinations)]
    CGPDFContextSetOutline(context, root as CFDictionary)
  }

  /// `entries` in the dictionaries `CGPDFContextSetOutline` takes: a title, a
  /// one-based page number and the point on that page, as a rect of no size.
  private static func items(_ entries: [OutlineEntry], destinations: [String: Place])
    -> [[CFString: Any]]
  {
    entries.compactMap { entry in
      guard let place = destinations[entry.anchor] else { return nil }
      var item: [CFString: Any] = [
        kCGPDFOutlineTitle: entry.title,
        kCGPDFOutlineDestination: place.page + 1,
        kCGPDFOutlineDestinationRect: CGRect(origin: place.point, size: .zero)
          .dictionaryRepresentation,
      ]
      let children = items(entry.children, destinations: destinations)
      if !children.isEmpty {
        item[kCGPDFOutlineChildren] = children
      }
      return item
    }
  }
}
