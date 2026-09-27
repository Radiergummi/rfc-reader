import Foundation
import SwiftData
import os

private let dataLog = Logger(
  subsystem: Bundle.main.bundleIdentifier ?? "me.mazetti.rfc-reader", category: "data")

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
  /// Why the store on disk could not be opened, when it could not (#152).
  ///
  /// The app then runs on a store in memory instead of crashing at launch: reading
  /// works, bookmarks and reading positions made this session are not kept, and
  /// nothing on disk is touched, so a later launch that can open it has everything
  /// back. The window says so once; see `storeWarning`.
  private(set) static var openFailure: (any Error)?

  static let container: ModelContainer = {
    do {
      return try ModelContainer(for: Bookmark.self, ReadingPosition.self)
    } catch {
      dataLog.error(
        "the user data store did not open: \(String(describing: error), privacy: .public)")
      openFailure = error
      do {
        return try ModelContainer(
          for: Bookmark.self, ReadingPosition.self,
          configurations: ModelConfiguration(isStoredInMemoryOnly: true))
      } catch {
        // A store in memory has no file to fail on; if even that will not open,
        // there is nothing left to run on.
        fatalError("Could not open even an in-memory user data store: \(error)")
      }
    }
  }()

  /// Whether the warning has been shown, so a second window or scene does not show
  /// it again.
  static var hasShownStoreWarning = false

  /// What the window tells the reader when the store fell back to memory.
  static let storeWarning = (
    title: "Your bookmarks couldn't be loaded",
    message:
      "Reading works as usual, but bookmarks and reading positions changed in this session won't be saved. Nothing already saved has been touched."
  )
}
