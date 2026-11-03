import Foundation
import Observation
import RFCKit
import SwiftData
import os

private let mirrorLog = Logger(
  subsystem: Bundle.main.bundleIdentifier ?? "me.mazetti.rfc-reader", category: "library")

/// The sets the app keeps read from the user's data (#595): the bookmarked documents,
/// the collections, the Recently Read count, the Keep Offline marks and the followed
/// working groups, each read again on a save of what feeds it (`UserDataMirrors`,
/// #603), and after a failed read on the next save of any kind (#613). Each is
/// published only when it changed, and its `on…Changed` is then called, for what the
/// app does about it; the bookmarks' and the marks' first read is reported whatever it
/// found, as until it their emptiness meant nothing
/// (`knowsWantedOffline(keepsBookmarks:)`).
///
/// Also where the user's data is changed, each change in a context of its own, whose
/// save the mirror then reads. A change whose save fails is thrown away with its
/// context (#1002): left pending on the main context, the next save of anything
/// committed it, and a retry found it there. Rolling the main context back instead did
/// not reliably undo what its fetches answer.
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

  /// The acronym of every followed working group, in lower case (#731), synced, so a
  /// group followed on another device is listed here too.
  public private(set) var followedGroups: Set<String> = []

  /// Every highlight (#522): what the readers draw and the Annotations tab lists.
  public private(set) var annotations = AnnotationSnapshot.empty

  /// Whether `offlineMarks` has been read from the store at least once. Until it
  /// has, its emptiness means nothing, and reconciling against it would move every
  /// kept body back into the cache.
  @ObservationIgnored private(set) var hasReadOfflineMarks = false

  /// Whether `bookmarkedDocuments` has been read from the store at least once, which
  /// is to the bookmarks what `hasReadOfflineMarks` is to the marks.
  @ObservationIgnored private(set) var hasReadBookmarks = false

  /// How the bookmarks are read: `BookmarkStore`, but for a test that makes the read
  /// fail.
  @ObservationIgnored var readBookmarks: (ModelContext) throws -> Set<DocumentID> = {
    try BookmarkStore.bookmarkedDocuments(in: $0)
  }

  /// Called when `bookmarkedDocuments` changed, and after their first read whatever it
  /// found.
  @ObservationIgnored public var onBookmarksChanged: () -> Void = {}
  /// Called when `collections` changed, with the new snapshot.
  @ObservationIgnored public var onCollectionsChanged: (CollectionSnapshot) -> Void = { _ in }
  /// Called when `recentlyReadCount` changed.
  @ObservationIgnored public var onRecentlyReadCountChanged: () -> Void = {}
  /// Called when `offlineMarks` changed, and after their first read whatever it found.
  @ObservationIgnored public var onOfflineMarksChanged: () -> Void = {}
  /// Called when `followedGroups` changed, here or by a sync from another device.
  @ObservationIgnored public var onFollowedGroupsChanged: () -> Void = {}
  /// Called when `annotations` changed.
  @ObservationIgnored public var onAnnotationsChanged: () -> Void = {}

  /// The mirrors whose last fetch failed. The next save reads them again, whatever
  /// it changed, so a failure is mended on the next save, as it was when every save
  /// read every mirror, rather than on the next save of the same entity (#603).
  @ObservationIgnored private var failedMirrors: UserDataMirrors = []
  @ObservationIgnored private var storeSaves: (any NSObjectProtocol)?

  public let container: ModelContainer

  public init(container: ModelContainer) {
    self.container = container
  }

  isolated deinit {
    if let storeSaves {
      NotificationCenter.default.removeObserver(storeSaves)
    }
  }

  /// Reads every mirror, then each again on every save that can have changed it.
  /// Separate from `init`, so the `on…Changed` closures are set before the first read.
  /// Once: a second call does nothing.
  public func start() {
    guard storeSaves == nil else { return }
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
  func refresh(_ changed: UserDataMirrors) {
    let mirrors = changed.union(failedMirrors)
    failedMirrors = []
    if mirrors.contains(.bookmarks) { refreshBookmarks() }
    if mirrors.contains(.collections) { refreshCollections() }
    if mirrors.contains(.recentlyReadCount) { refreshRecentlyReadCount() }
    if mirrors.contains(.offlineMarks) { refreshOfflineMarks() }
    if mirrors.contains(.annotations) { refreshAnnotations() }
    if mirrors.contains(.followedGroups) { refreshFollowedGroups() }
  }

  private func refreshFollowedGroups() {
    let groups: Set<String>
    do {
      groups = try FollowedGroupStore.followedGroups(in: container.mainContext)
    } catch {
      // The last set read stands until a fetch succeeds, which the next save tries.
      failedMirrors.insert(.followedGroups)
      mirrorLog.error(
        "reading followed groups failed: \(String(describing: error), privacy: .public)")
      return
    }
    guard groups != followedGroups else { return }
    followedGroups = groups
    onFollowedGroupsChanged()
  }

  private func refreshAnnotations() {
    let snapshot: AnnotationSnapshot
    do {
      snapshot = try AnnotationSnapshot.fetch(in: container.mainContext)
    } catch {
      // The last snapshot stands until a fetch succeeds, which the next save tries:
      // an empty one would draw no highlight and pin no annotated document.
      failedMirrors.insert(.annotations)
      mirrorLog.error(
        "reading annotations failed: \(String(describing: error), privacy: .public)")
      return
    }
    guard snapshot != annotations else { return }
    annotations = snapshot
    onAnnotationsChanged()
  }

  /// Reads the marks again now. A save of a mark reads them already, synchronously
  /// from a save on the main actor.
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
    // Read now, so the next save need not read them again.
    failedMirrors.remove(.offlineMarks)
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
      documents = try readBookmarks(container.mainContext)
    } catch {
      // The last set read stands until a fetch succeeds, which the next save tries.
      failedMirrors.insert(.bookmarks)
      mirrorLog.error("reading bookmarks failed: \(String(describing: error), privacy: .public)")
      return
    }
    // The first read reports even when it finds what a failed one left: no set.
    let isFirstRead = !hasReadBookmarks
    hasReadBookmarks = true
    // Only a change is news: an unknown save reads every mirror (`UserDataMirrors`).
    guard isFirstRead || documents != bookmarkedDocuments else { return }
    bookmarkedDocuments = documents
    onBookmarksChanged()
  }

  /// Whether what is wanted offline is known: the marks have been read, and the
  /// bookmarks too when they are kept offline. Until then a set is empty because a
  /// read failed, and reconciling or clearing against it would treat every body it
  /// keeps as wanted by nobody.
  public func knowsWantedOffline(keepsBookmarks: Bool) -> Bool {
    hasReadOfflineMarks && (!keepsBookmarks || hasReadBookmarks)
  }

  // MARK: - Changes

  /// A context for one change, thrown away with whatever it holds when its save fails.
  /// An undo registered on it holds it.
  private func changeContext() -> ModelContext {
    ModelContext(container)
  }

  /// Runs a change to collections in a context of its own. A failure is logged rather
  /// than shown (#125): every change the interface offers is one the store accepts,
  /// and an empty name is refused before it gets here. Answers whether it was made,
  /// for a view that says it was.
  @discardableResult
  public func editCollections(_ change: (ModelContext) throws -> Void) -> Bool {
    do {
      try change(changeContext())
      return true
    } catch {
      mirrorLog.error(
        "changing a collection failed: \(String(describing: error), privacy: .public)")
      return false
    }
  }

  /// Runs a change to annotations in a context of its own, logged rather than shown when
  /// it fails, as a collection's is (#125). Answers whether it was made.
  @discardableResult
  public func editAnnotations(_ change: (ModelContext) throws -> Void) -> Bool {
    do {
      try change(changeContext())
      return true
    } catch {
      mirrorLog.error(
        "changing an annotation failed: \(String(describing: error), privacy: .public)")
      return false
    }
  }

  /// Logs a failed undo or redo of a change to annotations.
  public static func logAnnotationUndoFailure(_ error: any Error) {
    mirrorLog.error(
      "undoing or redoing an annotation's change failed: \(String(describing: error), privacy: .public)"
    )
  }

  /// Adds the bookmark or removes it, in a context of its own, titled `title`. A
  /// failure is logged rather than shown, as a collection's is (#125), and changes
  /// nothing. A removal registers its undo with `undoManager` (#769), whose own
  /// failures are logged too.
  public func toggleBookmark(_ id: DocumentID, title: String, undoManager: UndoManager? = nil) {
    do {
      try BookmarkStore.toggle(
        id, title: title, undoManager: undoManager,
        onUndoFailure: { error in
          mirrorLog.error(
            "undoing or redoing a bookmark's removal failed: \(String(describing: error), privacy: .public)"
          )
        }, in: changeContext())
    } catch {
      mirrorLog.error(
        "toggling a bookmark failed: \(String(describing: error), privacy: .public)")
    }
  }

  /// Marks the document Keep Offline, or removes its mark (#358), in a context of its
  /// own. A failure is thrown for the caller to log, and changes nothing.
  public func setMarked(_ id: DocumentID, _ isMarked: Bool) throws {
    try OfflineMarkStore.setMarked(id, isMarked, in: changeContext())
  }

  /// Follows the working group, or stops following it (#731), in a context of its own.
  /// A failure is thrown for the caller to log, and changes nothing.
  public func setFollowed(_ group: String, _ isFollowed: Bool) throws {
    try FollowedGroupStore.setFollowed(group, isFollowed, in: changeContext())
  }

  /// Dates the document's reading position as it opens, listing it as read
  /// (`ReadingPositionStore.markOpened`), in a context of its own. A failure is thrown
  /// for the caller to log, and changes nothing.
  public func markOpened(_ document: ReadableDocument) throws {
    try ReadingPositionStore.markOpened(document, in: changeContext())
  }

  /// Saves the place the reader left (#599), in a context of its own. A failure is
  /// thrown for the caller to log, and changes nothing: the place is dropped, and the
  /// next save, on the next scroll, starts again from what the store holds.
  public func saveReadingPlace(_ place: ReadingPlace, for document: ReadableDocument) throws {
    try ReadingPositionStore.save(place, for: document, in: changeContext())
  }

  /// The document's stored reading position, read on the main context, which every
  /// change's save reaches.
  public func readingPosition(for document: ReadableDocument) throws -> ReadingPosition? {
    try ReadingPositionStore.position(for: document, in: container.mainContext)
  }

  /// Removes every Keep Offline mark, on every device, since marks are synced, as
  /// Settings' Remove All Offline Documents does (#358), and reports the marks once.
  /// `first` runs before the removal, so what it changes is what that one report sees.
  /// The removal is made in a context of its own, as every change is. A failure is
  /// thrown, after `first` ran, and nothing is reported.
  public func removeAllOfflineMarks(first: () -> Void) throws {
    let marks = offlineMarks
    first()
    // The save's notification reads the marks again, and reports them when they changed.
    try OfflineMarkStore.removeAll(in: changeContext())
    refreshOfflineMarks()
    // When none were removed nothing changed, and what `first` changed is reported here.
    if offlineMarks == marks { onOfflineMarksChanged() }
  }

  /// The documents the reader has opened, most recent first, a BCP, STD or FYI
  /// among them as itself (#321).
  ///
  /// Fetched on demand rather than observed, and that is the point: the Recently
  /// read list is history as of the moment the filter is entered, and a live query
  /// re-sorted it under the click that was reading it. `NavigationModel` takes one
  /// of these when its filter changes, exactly as it takes the RFCs wanted offline.
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
