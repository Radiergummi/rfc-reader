import Foundation

/// What one tab keeps across launches (#155): where it has been, which filter its
/// list shows, and which tab its inspector shows. Written as the tab changes, by
/// `@SceneStorage` on iOS and by the window's restorable state on macOS, and read
/// back when the tab is made again.
///
/// Not the search text: a tab comes back where it was, not to what was being typed,
/// as Mail and Finder do. Not the reading place either, which is the document's and
/// is kept with it (`ReadingPositionStore`).
public struct SceneSnapshot: Codable, Equatable, Sendable {
  /// Raised whenever what is kept changes shape, so a snapshot an older build wrote
  /// starts the tab afresh rather than failing to make it.
  public static let version = 1
  /// How many places of its history a tab keeps: the current one and those nearest it.
  public static let historyLimit = 50

  private var version = Self.version
  public var history: NavigationHistory.Snapshot
  public var filter: LibraryFilter
  /// The inspector's tab, by name: the tabs are the app's, and a name it no longer
  /// knows leaves the inspector on its first.
  public var inspectorTab: String?

  public init(
    history: NavigationHistory.Snapshot, filter: LibraryFilter, inspectorTab: String? = nil
  ) {
    self.history = history
    self.filter = filter
    self.inspectorTab = inspectorTab
  }

  public func encoded() -> Data? {
    try? JSONEncoder().encode(self)
  }

  /// The snapshot `data` holds, or nil when it holds none this build can read: one of
  /// another version, or anything else.
  public static func decoded(from data: Data) -> SceneSnapshot? {
    guard let snapshot = try? JSONDecoder().decode(SceneSnapshot.self, from: data),
      snapshot.version == version
    else { return nil }
    return snapshot
  }
}
