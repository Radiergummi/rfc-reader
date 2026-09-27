import RFCReaderKit
import SwiftData

/// The one SwiftData container.
///
/// `.modelContainer(for:)` on the scene makes a container SwiftUI owns and hands down
/// through the environment. On macOS the window's content is hosted outside that
/// environment — see `ReaderWindowLayer` — so each hosted root would otherwise be
/// handed a container of its own, and two writers on one store is a bookmark that
/// appears in one column and not the next. Made here instead, and given to both the
/// scene and every hosted root.
@MainActor
enum AppData {
  /// Versioned, and migrated from whatever version is on disk; see `UserData` (#152).
  /// Rows naming the same document are merged once it opens: the schema has no
  /// unique constraint, which CloudKit refuses.
  static let container: ModelContainer = {
    let container: ModelContainer
    do {
      container = try UserData.container()
    } catch {
      fatalError("Could not open the user data store: \(error)")
    }
    try? UserData.deduplicate(container.mainContext)
    return container
  }()
}
