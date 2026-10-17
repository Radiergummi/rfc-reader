import Foundation
import Observation
import RFCKit
import SwiftData
import os

private let mirrorLog = Logger(
  subsystem: Bundle.main.bundleIdentifier ?? "me.mazetti.rfc-reader", category: "library")

/// The sets the app keeps read from the user's data (#595): the bookmarked documents,
/// the collections, the Recently Read count and the Keep Offline marks, each read
/// again on a save of what feeds it (`UserDataMirrors`, #603), and after a failed read
/// on the next save of any kind (#613). Each is published only when it changed, and
/// its `on…Changed` is then called, for what the app does about it.
///
/// Also where a bookmark or a collection is changed, on the container's main context,
/// whose save the mirror then reads.
@MainActor @Observable
public final class UserDataMirror {
  /// Every bookmarked document: one set for the toolbars, scripts and lists alike, so
  /// BCP 14 is not answered for by RFC 14 (#152), and is listed as itself (#321).
  public private(set) var bookmarkedDocuments: Set<DocumentID> = []

  /// Every collection and its members. The sidebar, a collection's list, the Add to
  /// Collection menus, the Mac's menu bar and scripts all read it.
  public private(set) var collections = CollectionSnapshot.empty

  /// How many documents Recently Read lists, for the sidebar's count (#344): the
  /// length of `recentlyRead()`, kept current on every save of a reading position
  /// rather than by a live query of every reading position in the view.
  public private(set) var recentlyReadCount = 0

  /// Every document marked Keep Offline (#358), synced, so a mark made on another
  /// device arrives here too.
  public private(set) var offlineMarks: Set<DocumentID> = []

  /// Whether `offlineMarks` has been read from the store at least once. Until it
  /// has, its emptiness means nothing, and reconciling against it would move every
  /// kept body back into the cache.
  @ObservationIgnored public private(set) var hasReadOfflineMarks = false

  /// Called when `bookmarkedDocuments` changed.
  @ObservationIgnored public var onBookmarksChanged: () -> Void = {}
  /// Called when `collections` changed, with the new snapshot.
  @ObservationIgnored public var onCollectionsChanged: (CollectionSnapshot) -> Void = { _ in }
  /// Called when `recentlyReadCount` changed.
  @ObservationIgnored public var onRecentlyReadCountChanged: () -> Void = {}
  /// Called when `offlineMarks` changed, and after their first read whatever it found.
  @ObservationIgnored public var onOfflineMarksChanged: () -> Void = {}

  /// The mirrors whose last fetch failed. The next save reads them again, whatever
  /// it changed, so a failure is mended on the next save, as it was when every save
  /// read every mirror, rather than on the next save of the same entity (#603).
  @ObservationIgnored private var failedMirrors: UserDataMirrors = []
  @ObservationIgnored private var storeSaves: (any NSObjectProtocol)?

  public let container: ModelContainer

  public init(container: ModelContainer) {
    self.container = container
  }

  /// Reads every mirror, then each again on every save that can have changed it.
  /// Separate from `init`, so the `on…Changed` closures are set before the first read.
  public func start() {
    refresh(.all)
    storeSaves = NotificationCenter.default.addObserver(
      forName: ModelContext.didSave, object: nil, queue: .main
    ) { [weak self] notification in
      // Only the mirrors fed by what the save changed: most saves record a reading
      // position, and the collections are every row of two entities (#603). Read
      // before the hop, as the notification is not `Sendable` and the names are.
      let changed = UserDataMirrors.changedEntityNames(in: notification.userInfo)
      MainActor.assumeIsolated {
        self?.refresh(UserDataMirrors.changed(byEntities: changed))
      }
    }
  }

  /// Reads `changed` again, and every mirror whose last read failed.
  public func refresh(_ changed: UserDataMirrors) {
    let mirrors = changed.union(failedMirrors)
    failedMirrors = []
    if mirrors.contains(.bookmarks) { refreshBookmarks() }
    if mirrors.contains(.collections) { refreshCollections() }
    if mirrors.contains(.recentlyReadCount) { refreshRecentlyReadCount() }
    if mirrors.contains(.offlineMarks) { refreshOfflineMarks() }
  }

  public func refreshOfflineMarks() {
    let marks: Set<DocumentID>
    do {
      marks = try OfflineMarkStore.markedDocuments(in: container.mainContext)
    } catch {
      // The last set read stands until a fetch succeeds, which the next save tries.
      failedMirrors.insert(.offlineMarks)
      mirrorLog.error(
        "reading Keep Offline marks failed: \(String(describing: error), privacy: .public)")
      return
    }
    // The first read reports even when it finds what a failed one left: no set.
    let isFirstRead = !hasReadOfflineMarks
    hasReadOfflineMarks = true
    guard isFirstRead || marks != offlineMarks else { return }
    offlineMarks = marks
    onOfflineMarksChanged()
  }

  private func refreshRecentlyReadCount() {
    let count: Int
    do {
      count = try ReadingPositionStore.recentlyReadCount(in: container.mainContext)
    } catch {
      // The last count read stands until a fetch succeeds, which the next save tries.
      failedMirrors.insert(.recentlyReadCount)
      mirrorLog.error(
        "counting the recently read failed: \(String(describing: error), privacy: .public)")
      return
    }
    guard count != recentlyReadCount else { return }
    recentlyReadCount = count
    onRecentlyReadCountChanged()
  }

  private func refreshCollections() {
    let snapshot: CollectionSnapshot
    do {
      snapshot = try CollectionSnapshot.fetch(in: container.mainContext)
    } catch {
      // The last snapshot stands until a fetch succeeds, which the next save tries:
      // an empty one would close every filter on a collection (#613).
      failedMirrors.insert(.collections)
      mirrorLog.error(
        "reading collections failed: \(String(describing: error), privacy: .public)")
      return
    }
    // Only a change is news: an unknown save reads every mirror (`UserDataMirrors`).
    guard snapshot != collections else { return }
    collections = snapshot
    onCollectionsChanged(snapshot)
  }

  private func refreshBookmarks() {
    let documents: Set<DocumentID>
    do {
      documents = try BookmarkStore.bookmarkedDocuments(in: container.mainContext)
    } catch {
      // The last set read stands until a fetch succeeds, which the next save tries.
      failedMirrors.insert(.bookmarks)
      mirrorLog.error("reading bookmarks failed: \(String(describing: error), privacy: .public)")
      return
    }
    // Only a change is news: an unknown save reads every mirror (`UserDataMirrors`).
    guard documents != bookmarkedDocuments else { return }
    bookmarkedDocuments = documents
    onBookmarksChanged()
  }

  // MARK: - Changes

  /// Runs a change to collections on the main context. A failure is logged rather
  /// than shown (#125): every change the interface offers is one the store accepts,
  /// and an empty name is refused before it gets here. Answers whether it was made,
  /// for a view that says it was.
  @discardableResult
  public func editCollections(_ change: (ModelContext) throws -> Void) -> Bool {
    do {
      try change(container.mainContext)
      return true
    } catch {
      mirrorLog.error(
        "changing a collection failed: \(String(describing: error), privacy: .public)")
      return false
    }
  }

  /// Adds the bookmark or removes it, on the main context, titled `title`. A failure
  /// is logged rather than shown, as a collection's is (#125). A failed lookup
  /// changes nothing; a failed save leaves the change pending in the context, saved
  /// with the next save that succeeds.
  public func toggleBookmark(_ id: DocumentID, title: String) {
    do {
      try BookmarkStore.toggle(id, title: title, in: container.mainContext)
    } catch {
      mirrorLog.error(
        "toggling a bookmark failed: \(String(describing: error), privacy: .public)")
    }
  }

  /// The documents the reader has opened, most recent first, a BCP, STD or FYI
  /// among them as itself (#321).
  ///
  /// Fetched on demand rather than observed, and that is the point: the Recently
  /// read list is history as of the moment the filter is entered, and a live query
  /// re-sorted it under the click that was reading it.
  ///
  /// Empty when the fetch fails, which is logged: the list is only shown, and
  /// nothing is decided by its being empty.
  public func recentlyRead() -> [DocumentID] {
    do {
      return try ReadingPositionStore.recentlyRead(in: container.mainContext)
    } catch {
      mirrorLog.error(
        "reading the recently read list failed: \(String(describing: error), privacy: .public)")
      return []
    }
  }
}
