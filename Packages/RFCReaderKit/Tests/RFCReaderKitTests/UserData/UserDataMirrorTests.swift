import Foundation
import RFCKit
import SwiftData
import Testing

@testable import RFCReaderKit

/// The sets read from the user's data (#595): read at start, read again on a save of
/// what feeds them, and reported only when they changed.
@Suite("User data mirror")
@MainActor
struct UserDataMirrorTests {
  /// How often each `on…Changed` was called, and the snapshots `onCollectionsChanged`
  /// was called with, in order.
  @MainActor
  final class Reports {
    var bookmarks = 0
    var collections: [CollectionSnapshot] = []
    var recentlyReadCount = 0
    var offlineMarks = 0
  }

  /// A mirror of an in-memory store, reporting into `reports`, held with its
  /// container: a context does not keep its container alive.
  private func makeMirror(reporting reports: Reports) throws -> UserDataMirror {
    let container = try UserData.container(
      configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    let mirror = UserDataMirror(container: container)
    mirror.onBookmarksChanged = { reports.bookmarks += 1 }
    mirror.onCollectionsChanged = { reports.collections.append($0) }
    mirror.onRecentlyReadCountChanged = { reports.recentlyReadCount += 1 }
    mirror.onOfflineMarksChanged = { reports.offlineMarks += 1 }
    return mirror
  }

  /// The first read of the bookmarks and of the marks reports them even when there are
  /// none: until it, their emptiness meant nothing.
  @Test func `starting reads every set and reports the bookmarks and the marks`() throws {
    let reports = Reports()
    let mirror = try makeMirror(reporting: reports)
    #expect(!mirror.knowsWantedOffline(keepsBookmarks: false))
    #expect(!mirror.hasReadOfflineMarks)
    #expect(!mirror.hasReadBookmarks)

    mirror.start()

    #expect(mirror.hasReadOfflineMarks)
    #expect(mirror.hasReadBookmarks)
    #expect(reports.offlineMarks == 1)
    #expect(reports.bookmarks == 1)
    #expect(reports.collections.isEmpty)
    #expect(reports.recentlyReadCount == 0)
  }

  @Test func `a bookmark toggled is mirrored and reported`() throws {
    let reports = Reports()
    let mirror = try makeMirror(reporting: reports)
    mirror.start()

    mirror.toggleBookmark(.rfc(9110), title: "HTTP Semantics")

    #expect(mirror.bookmarkedDocuments == [.rfc(9110)])
    #expect(reports.bookmarks == 2)
  }

  /// A reading position is most saves, and reads none of the other sets: a bookmark and
  /// a mark waiting unsaved in the main context, which a read of theirs would find, are
  /// not found. The reading is saved in a context of its own, so its save is only that.
  @Test func `a reading saved changes the count and reads nothing else`() throws {
    let reports = Reports()
    let mirror = try makeMirror(reporting: reports)
    mirror.start()
    mirror.container.mainContext.insert(Bookmark(document: .rfc(9110), title: "HTTP Semantics"))
    mirror.container.mainContext.insert(OfflineMark(document: .rfc(9110)))

    try ReadingPositionStore.save(
      ReadingPlace(anchor: "section-1", offset: 0), for: .rfc(9110),
      in: ModelContext(mirror.container))

    #expect(mirror.bookmarkedDocuments.isEmpty)
    #expect(mirror.offlineMarks.isEmpty)
    #expect(mirror.recentlyReadCount == 1)
    #expect(reports.recentlyReadCount == 1)
    #expect(reports.bookmarks == 1)
    #expect(reports.collections.isEmpty)
    #expect(reports.offlineMarks == 1)
    #expect(mirror.recentlyRead() == [.rfc(9110)])
  }

  @Test func `a collection edited is mirrored and reported with its snapshot`() throws {
    let reports = Reports()
    let mirror = try makeMirror(reporting: reports)
    mirror.start()

    let made = mirror.editCollections { context in
      _ = try CollectionStore.create(named: "HTTP/3", color: .blue, in: context)
    }

    #expect(made)
    #expect(mirror.collections.collections.map(\.name) == ["HTTP/3"])
    #expect(reports.collections == [mirror.collections])
  }

  @Test func `a mark saved is mirrored and reported`() throws {
    let reports = Reports()
    let mirror = try makeMirror(reporting: reports)
    mirror.start()

    try OfflineMarkStore.setMarked(.rfc(9110), true, in: mirror.container.mainContext)

    #expect(mirror.offlineMarks == [.rfc(9110)])
    #expect(reports.offlineMarks == 2)
  }

  /// Remove All Offline Documents also stops keeping the bookmarks offline (#917). The
  /// marks are reported once, and only after that, so the one reconciliation the
  /// report starts no longer wants the bookmarks.
  @Test func `removing every mark reports them once, after what runs first`() throws {
    let mirror = try makeMirror(reporting: Reports())
    mirror.start()
    try OfflineMarkStore.setMarked(.rfc(9110), true, in: mirror.container.mainContext)
    var keepsBookmarks = true
    var keepsBookmarksWhenReported: [Bool] = []
    mirror.onOfflineMarksChanged = { keepsBookmarksWhenReported.append(keepsBookmarks) }

    try mirror.removeAllOfflineMarks(first: { keepsBookmarks = false })

    #expect(mirror.offlineMarks.isEmpty)
    #expect(keepsBookmarksWhenReported == [false])
  }

  /// With no mark to remove the save changes no mark, and the report still comes, once:
  /// what ran first may have changed what is wanted offline.
  @Test func `removing every mark when there are none still reports once`() throws {
    let mirror = try makeMirror(reporting: Reports())
    mirror.start()
    var keepsBookmarks = true
    var keepsBookmarksWhenReported: [Bool] = []
    mirror.onOfflineMarksChanged = { keepsBookmarksWhenReported.append(keepsBookmarks) }

    try mirror.removeAllOfflineMarks(first: { keepsBookmarks = false })

    #expect(keepsBookmarksWhenReported == [false])
  }

  /// An unknown save reads every set again, and only what changed is reported.
  @Test func `a refresh that finds nothing new reports nothing`() throws {
    let reports = Reports()
    let mirror = try makeMirror(reporting: reports)
    mirror.start()
    mirror.toggleBookmark(.rfc(9110), title: "HTTP Semantics")

    mirror.refresh(.all)

    #expect(reports.bookmarks == 2)
    #expect(reports.offlineMarks == 1)
    #expect(reports.collections.isEmpty)
    #expect(reports.recentlyReadCount == 0)
  }

  /// The app's mirror is made once, but a second start would read every save twice.
  /// A bookmark waiting unsaved in the main context is what a second read would find.
  @Test func `starting again reads nothing`() throws {
    let reports = Reports()
    let mirror = try makeMirror(reporting: reports)
    mirror.start()
    mirror.container.mainContext.insert(Bookmark(document: .rfc(9110), title: "HTTP Semantics"))

    mirror.start()

    #expect(mirror.bookmarkedDocuments.isEmpty)
    #expect(reports.bookmarks == 1)
  }

  /// A failed first read of the bookmarks leaves them unknown, not empty: with
  /// bookmarks kept offline, reconciling against none would un-keep every kept body.
  /// The next save reads them again, and that read is reported whatever it found.
  @Test func `a failed first bookmark read leaves what is wanted offline unknown`() throws {
    let reports = Reports()
    let mirror = try makeMirror(reporting: reports)
    struct Unreadable: Error {}
    mirror.readBookmarks = { _ in throw Unreadable() }
    mirror.start()

    #expect(!mirror.knowsWantedOffline(keepsBookmarks: true))
    #expect(mirror.knowsWantedOffline(keepsBookmarks: false))

    mirror.readBookmarks = { try BookmarkStore.bookmarkedDocuments(in: $0) }
    try ReadingPositionStore.save(
      ReadingPlace(anchor: "section-1", offset: 0), for: .rfc(9110),
      in: mirror.container.mainContext)

    #expect(mirror.knowsWantedOffline(keepsBookmarks: true))
    #expect(reports.bookmarks == 1)
  }

  @Test func `a failed change to a collection says so`() throws {
    let mirror = try makeMirror(reporting: Reports())
    mirror.start()

    struct Refused: Error {}
    #expect(!mirror.editCollections { _ in throw Refused() })
  }
}
