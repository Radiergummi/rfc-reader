import Foundation
import RFCKit

/// What the collection sheet is for (#349).
enum CollectionEditorMode: Identifiable, Hashable {
  /// A new collection, and the document to add to it once made, when it was asked
  /// for from an Add to Collection menu.
  case create(adding: DocumentID?)
  /// Renaming and recolouring the collection with this identifier.
  case edit(UUID)

  var id: Self { self }
}
