import RFCKit
import RFCReaderKit
import SwiftData
import os

/// Where a document was left, kept in the user's data: marked read when it opens,
/// the place saved when the reader leaves, and that place asked for when it comes
/// back (#599). A failure is logged and otherwise dropped: the reader then opens at
/// the top, as it does for a document never read.
struct ReadingPositionKeeper {
  let id: DocumentID
  let context: ModelContext

  func markOpened() {
    do {
      try ReadingPositionStore.markOpened(id, in: context)
    } catch {
      readerLog.error(
        "marking \(id.displayName, privacy: .public) as read failed: \(String(describing: error), privacy: .public)"
      )
    }
  }

  /// Saves where `box` says the reader is. Nothing for a document that never showed
  /// its text — one that failed to load, or was left before it did — since saving
  /// no place would erase the one stored, and list a document that never opened as
  /// read.
  func save(_ box: VisibleAnchorBox) {
    guard let anchor = box.anchor else { return }
    do {
      try ReadingPositionStore.save(
        box.place ?? ReadingPlace(anchor: anchor, offset: 0), for: id, in: context)
    } catch {
      readerLog.error(
        "saving the position failed: \(String(describing: error), privacy: .public)")
    }
  }

  func stored() -> ReadingPosition? {
    do {
      return try ReadingPositionStore.position(for: id, in: context)
    } catch {
      readerLog.error(
        "reading the position failed: \(String(describing: error), privacy: .public)")
      return nil
    }
  }
}
