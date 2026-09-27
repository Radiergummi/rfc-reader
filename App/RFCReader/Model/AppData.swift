import Foundation
import RFCReaderKit
import SwiftData
import os

private let userDataLog = Logger(
  subsystem: Bundle.main.bundleIdentifier ?? "me.mazetti.rfc-reader", category: "user data")

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
  /// Versioned and migrated, then merged to one row per document; see `UserData`.
  static let container: ModelContainer = {
    let container: ModelContainer
    do {
      container = try UserData.container()
    } catch {
      fatalError("Could not open the user data store: \(error)")
    }
    do {
      try UserData.deduplicate(container.mainContext)
    } catch {
      userDataLog.error(
        "merging duplicate rows failed: \(String(describing: error), privacy: .public)")
    }
    return container
  }()
}
