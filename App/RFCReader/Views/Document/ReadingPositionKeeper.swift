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

/// Holds a save of the reading place until the reader has stopped (#155), so a
/// scroll through a document writes once, at its end, rather than on every tick.
final class ReadingPlaceSaver {
  /// Long enough to outlast the pauses inside one scroll.
  private static let delay = Duration.seconds(2)
  private var pending: Task<Void, Never>?
  /// When the save is due. Every scroll tick moves it, which is all a tick costs:
  /// the one task waiting for it sleeps on until it stops moving.
  private var due = ContinuousClock.now
  private var save: () -> Void = {}

  /// Runs `save` once nothing else has been scheduled for `delay`.
  func schedule(_ save: @escaping () -> Void) {
    self.save = save
    due = .now + Self.delay
    guard pending == nil else { return }
    pending = Task(name: "Save reading place") { [weak self] in
      while let self, self.due > .now {
        guard await Debounce.outlasted(self.due - .now) else { return }
      }
      guard let self else { return }
      self.pending = nil
      self.save()
    }
  }

  func cancel() {
    pending?.cancel()
    pending = nil
  }
}
