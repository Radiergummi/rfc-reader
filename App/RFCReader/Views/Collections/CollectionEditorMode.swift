import Foundation
import RFCKit

/// What the collection sheet is for (#349).
enum CollectionEditorMode: Identifiable, Hashable {
  /// A new collection, and the document to add to it once made, when it was asked
  /// for from an Add to Collection menu.
  case create(adding: DocumentID?)
  /// A new collection made from a query (#355): Save as Collection….
  case save(query: String)
  /// Renaming and recoloring the collection with this identifier, and changing its
  /// query when it is made from one.
  case edit(UUID)

  var id: Self { self }
}
