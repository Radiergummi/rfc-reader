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
  static let container: ModelContainer = {
    do {
      return try ModelContainer(for: Bookmark.self, ReadingPosition.self)
    } catch {
      fatalError("Could not open the user data store: \(error)")
    }
  }()
}
