import Foundation

/// The filter a tab goes on showing when collections change (#349): its own, unless
/// it is a collection that no longer exists — deleted in another tab or on another
/// device — which falls back to every RFC.
public enum KeptFilter {
  public static func filter(
    _ filter: LibraryFilter, keeping snapshot: CollectionSnapshot
  ) -> LibraryFilter {
    if case .collection(let identifier) = filter, snapshot[identifier] == nil { return .all }
    return filter
  }
}
