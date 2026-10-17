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
  /// What each `on…Changed` was called with, in order.
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

  /// The first read of the marks reports them even when there are none: until it,
  /// their emptiness meant nothing.
  @Test func `starting reads every set and reports the marks`() throws {
    let reports = Reports()
    let mirror = try makeMirror(reporting: reports)
    #expect(!mirror.hasReadOfflineMarks)

    mirror.start()

    #expect(mirror.hasReadOfflineMarks)
    #expect(reports.offlineMarks == 1)
    #expect(reports.bookmarks == 0)
    #expect(reports.collections.isEmpty)
    #expect(reports.recentlyReadCount == 0)
  }

  @Test func `a bookmark toggled is mirrored and reported`() throws {
    let reports = Reports()
    let mirror = try makeMirror(reporting: reports)
    mirror.start()

    mirror.toggleBookmark(.rfc(9110), title: "HTTP Semantics")

    #expect(mirror.bookmarkedDocuments == [.rfc(9110)])
    #expect(reports.bookmarks == 1)
  }

  /// A reading position is most saves, and reads none of the other sets.
  @Test func `a reading saved changes the count and reports nothing else`() throws {
    let reports = Reports()
    let mirror = try makeMirror(reporting: reports)
    mirror.start()

    try ReadingPositionStore.save(
      ReadingPlace(anchor: "section-1", offset: 0), for: .rfc(9110),
      in: mirror.container.mainContext)

    #expect(mirror.recentlyReadCount == 1)
    #expect(reports.recentlyReadCount == 1)
    #expect(reports.bookmarks == 0)
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

  /// An unknown save reads every set again, and only what changed is reported.
  @Test func `a refresh that finds nothing new reports nothing`() throws {
    let reports = Reports()
    let mirror = try makeMirror(reporting: reports)
    mirror.start()
    mirror.toggleBookmark(.rfc(9110), title: "HTTP Semantics")

    mirror.refresh(.all)

    #expect(reports.bookmarks == 1)
    #expect(reports.offlineMarks == 1)
    #expect(reports.collections.isEmpty)
  }

  /// The app's mirror is made once, but a second start would read every save twice.
  @Test func `starting again changes nothing`() throws {
    let reports = Reports()
    let mirror = try makeMirror(reporting: reports)
    mirror.start()
    mirror.start()

    mirror.toggleBookmark(.rfc(9110), title: "HTTP Semantics")

    #expect(reports.offlineMarks == 1)
    #expect(reports.bookmarks == 1)
  }

  @Test func `a failed change to a collection says so`() throws {
    let mirror = try makeMirror(reporting: Reports())
    mirror.start()

    struct Refused: Error {}
    #expect(!mirror.editCollections { _ in throw Refused() })
  }
}
