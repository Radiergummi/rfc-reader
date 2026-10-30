import Foundation
import RFCKit
import SwiftData
import Testing

@testable import RFCReaderKit

/// A change whose save fails is not left pending on the context (#1002): it is
/// discarded, so the next save, of anything, cannot commit it behind the reader's back,
/// and a retry starts from what the store holds.
@Suite("Failed saves of the user's data")
@MainActor
struct FailedSaveTests {
  /// A store on disk holding what `seed` saved, opened again refusing every save.
  /// Held by each test: a context does not keep its container alive, and one freed
  /// under it traps.
  private func makeReadOnlyContainer(seed: (ModelContext) throws -> Void = { _ in }) throws
    -> ModelContainer
  {
    let url = FileManager.default.temporaryDirectory
      .appending(path: "failed-save-\(UUID().uuidString).store")
    do {
      let writable = try UserData.container(configurations: ModelConfiguration(url: url))
      try seed(writable.mainContext)
    }
    return try UserData.container(configurations: ModelConfiguration(url: url, allowsSave: false))
  }

  @Test func `a bookmark whose save fails is not left pending`() throws {
    let container = try makeReadOnlyContainer()
    let context = container.mainContext
    #expect(throws: (any Error).self) {
      try BookmarkStore.toggle(.rfc(9110), title: "HTTP Semantics", in: context)
    }
    #expect(!context.hasChanges)
    #expect(try BookmarkStore.bookmarkedDocuments(in: context).isEmpty)
  }

  /// Nor is an undo registered for a removal that was discarded.
  @Test func `a bookmark's removal whose save fails is not left pending`() throws {
    let container = try makeReadOnlyContainer {
      try BookmarkStore.toggle(.rfc(9110), title: "HTTP Semantics", in: $0)
    }
    let context = container.mainContext
    let undoManager = UndoManager()
    #expect(throws: (any Error).self) {
      try BookmarkStore.toggle(
        .rfc(9110), title: "HTTP Semantics", undoManager: undoManager, in: context)
    }
    #expect(!context.hasChanges)
    #expect(try BookmarkStore.bookmarkedDocuments(in: context) == [.rfc(9110)])
    #expect(!undoManager.canUndo)
  }

  @Test func `a Keep Offline mark whose save fails is not left pending`() throws {
    let container = try makeReadOnlyContainer()
    let context = container.mainContext
    #expect(throws: (any Error).self) {
      try OfflineMarkStore.setMarked(.rfc(9110), true, in: context)
    }
    #expect(!context.hasChanges)
    #expect(try OfflineMarkStore.markedDocuments(in: context).isEmpty)
  }

  @Test func `a follow whose save fails is not left pending`() throws {
    let container = try makeReadOnlyContainer()
    let context = container.mainContext
    #expect(throws: (any Error).self) {
      try FollowedGroupStore.setFollowed("httpbis", true, in: context)
    }
    #expect(!context.hasChanges)
    #expect(try FollowedGroupStore.followedGroups(in: context).isEmpty)
  }
}
