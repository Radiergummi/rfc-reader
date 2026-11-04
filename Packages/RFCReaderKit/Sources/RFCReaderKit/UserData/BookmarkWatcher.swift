import Foundation
import RFCKit
import SwiftData
import os

private let bookmarkLog = Logger(
  subsystem: Bundle.main.bundleIdentifier ?? "me.mazetti.rfc-reader", category: "library")

/// The bookmarked RFCs, and the followed groups' RFCs (#731), compared with the last
/// baseline after every change to the index or the revisions, and what changed handed
/// to `post` (#191, #595); and the background refresh that brings those changes.
///
/// The comparison runs whether notifications are on or not, so the baseline is current
/// when they are turned on. Its owner calls `compare()` on each change: the index
/// applied, the revisions changed, a bookmark added or removed, a group followed.
@MainActor
public final class BookmarkWatcher {
  private let store: DocumentStore
  private let container: ModelContainer
  private let indexes: IndexRepository
  private let dataFiles: DataFileRefresher
  /// Whether the user's data fell back to memory (#152), which reads as no bookmarks.
  private let isStoredInMemory: Bool
  /// What launch does, which a background refresh may be the first to ask for.
  private let bootstrap: () async -> Void
  /// Posts the notices, or nothing when notifications are off.
  private let post: ([BookmarkNotice]) async -> Void

  /// The comparison under way. Each waits for the one before, so two never read the
  /// same baseline and both report what changed since.
  private var comparison: Task<Void, Never>?

  public init(
    store: DocumentStore, container: ModelContainer, indexes: IndexRepository,
    dataFiles: DataFileRefresher, isStoredInMemory: Bool,
    bootstrap: @escaping () async -> Void,
    post: @escaping ([BookmarkNotice]) async -> Void
  ) {
    self.store = store
    self.container = container
    self.indexes = indexes
    self.dataFiles = dataFiles
    self.isStoredInMemory = isStoredInMemory
    self.bootstrap = bootstrap
    self.post = post
  }

  /// What a background refresh does (#191): the revisions, then the index when its
  /// daily check is due, each of which compares the bookmarks when it changes; and
  /// waits for each comparison, so the system does not suspend the app before it
  /// has posted.
  ///
  /// It waits for the index to settle, which every outcome of launch's load does,
  /// a `304` that leaves nothing to show included (#758), not for it to be ready.
  ///
  /// The revisions come first because the index check waits for a network that is
  /// neither expensive nor constrained (#314), which on a phone network can outlast
  /// iOS's background task. Due revisions are fetched on any network, for the same
  /// reason (#758). Canceling this, as iOS does when that task expires, cancels the
  /// check, or the person's refresh it joined, but not the revisions' fetch, which
  /// runs on as a launch's does.
  public func refresh() async {
    await bootstrap()
    await indexes.settled()
    await dataFiles.refreshRevisions(onExpensiveNetworks: true)
    await comparison?.value
    guard indexes.indexState.isCheckDue(now: .now) else { return }
    let check = indexes.check()
    await withTaskCancellationHandler {
      await check.value
    } onCancel: {
      check.cancel()
    }
    await comparison?.value
  }

  /// Compares once the comparison before has finished.
  public func compare() {
    let previous = comparison
    comparison = Task(name: "Compare bookmarks") {
      await previous?.value
      await compareNow()
    }
  }

  private func compareNow() async {
    // A store that fell back to memory (#152) reads as no bookmarks, which would
    // start every one afresh at the next launch that opens the real one.
    guard !isStoredInMemory else { return }
    let bookmarks: Set<DocumentID>
    let groups: Set<String>
    do {
      // Read here rather than taken from `UserDataMirror`, whose sets a failed read
      // leaves empty: a baseline of none would start every one afresh.
      bookmarks = try BookmarkStore.bookmarkedDocuments(in: container.mainContext)
      groups = try FollowedGroupStore.followedGroups(in: container.mainContext)
    } catch {
      bookmarkLog.error(
        "reading bookmarks or followed groups to compare failed: \(String(describing: error), privacy: .public)"
      )
      return
    }
    let previous = await store.bookmarkBaseline()
    let baseline = BookmarkBaseline(
      bookmarks: bookmarks, followedGroups: groups, index: indexes.index,
      revisions: dataFiles.revisions, carryingOver: previous)
    guard baseline != previous else { return }
    do {
      // Kept before anything is posted: a baseline that cannot be kept would report
      // the same changes on every refresh.
      try await store.storeBookmarkBaseline(baseline)
    } catch {
      bookmarkLog.error(
        "keeping the bookmark baseline failed: \(String(describing: error), privacy: .public)")
      return
    }
    let events = BookmarkEvents.between(previous, baseline)
    await post(BookmarkNotice.notices(for: events, index: indexes.index))
  }
}
