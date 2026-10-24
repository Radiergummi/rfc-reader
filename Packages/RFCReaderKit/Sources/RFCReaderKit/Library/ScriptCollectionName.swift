import Foundation

/// What a script's `collection "…"` names among the application's collections
/// (#987), which are only the ones the reader made. A built-in list's name is told
/// apart from a name that means nothing, so that deleting or renaming Bookmarks is
/// refused in words rather than as a collection that isn't there.
public enum ScriptCollectionName: Equatable, Sendable {
  /// A collection the reader made: the first in the sidebar's order of that name.
  case collection(UUID)
  /// A list the app keeps, a stream, a series or a working group, which a window's
  /// `collection` can show but no command can change.
  case builtIn(LibraryFilter)

  /// Without regard to case, as `LibraryFilter(scriptName:)` names them. A
  /// collection the reader made wins a clash with a built-in name here, the other
  /// way round from a window's `collection`: only the reader's collections are
  /// elements, so `collection "Bookmarks"` can only be one of them.
  public init?(_ name: String, collections: CollectionSnapshot, workingGroups: Set<String>) {
    if let entry = collections.collection(named: name) {
      self = .collection(entry.id)
    } else if let filter = LibraryFilter(scriptName: name, workingGroups: workingGroups) {
      self = .builtIn(filter)
    } else {
      return nil
    }
  }
}
