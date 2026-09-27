import Foundation
import RFCKit

/// The downloads the document store has running, and the removals made while they
/// ran (#116).
///
/// A fetch suspends, and while it does the store's actor runs other calls. Without
/// this, a Remove Download made during a fetch finished first, and then the fetch
/// resumed and wrote the document back: the removal was silently undone.
///
/// A removal during a download does not cancel it. A fetch is only ever started by
/// opening the document, so the reader is waiting for it, and cancelling would turn
/// "don't keep this offline" into an error in front of them. Instead each document
/// has a removal generation: a fetch notes it before it suspends and writes its
/// result only if no removal has come since. The reader still gets the document;
/// the disk does not.
///
/// While one fetch for a document is running, a second open joins it rather than
/// fetching again.
///
/// A fetch outlives the reader that started it: leaving the document while it loads
/// does not cancel it, and it is kept. Cancelling on the first reader's way out
/// would fail any other reader joined to it, and opening a document already means
/// keeping it offline — one that finished loading a moment before the reader left
/// was always kept. Eviction (#39) is what bounds what that adds up to.
///
/// A value, held by the store's actor, which is what serialises it. Here rather
/// than in the App target for its tests.
public struct InFlightDownloads<Value: Sendable> {
  private var running: [DocumentID: Task<Value, any Error>] = [:]
  private var generations: [DocumentID: Int] = [:]

  public init() {}

  /// The fetch for `id` already running, or the one `start` makes, and the removal
  /// generation to check its result against.
  public mutating func join(
    _ id: DocumentID, start: () -> Task<Value, any Error>
  ) -> (task: Task<Value, any Error>, generation: Int) {
    let task = running[id] ?? start()
    running[id] = task
    return (task, generations[id, default: 0])
  }

  /// Called by everyone who awaited `task`, once it has. Forgets it only if it is
  /// still the one running for `id`: a later open may have started another.
  public mutating func finish(_ id: DocumentID, _ task: Task<Value, any Error>) {
    if running[id] == task {
      running[id] = nil
    }
  }

  /// A removal: whatever is running for `id` now finishes without being written.
  public mutating func removed(_ id: DocumentID) {
    generations[id, default: 0] += 1
  }

  /// Whether a fetch that noted `generation` may write its result: no removal has
  /// come since.
  public func isCurrent(_ id: DocumentID, since generation: Int) -> Bool {
    generations[id, default: 0] == generation
  }

  public func isRunning(_ id: DocumentID) -> Bool {
    running[id] != nil
  }
}
