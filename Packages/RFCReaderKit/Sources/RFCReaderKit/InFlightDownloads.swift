import Foundation
import RFCKit

/// The downloads the document store has running, the readers waiting for each, and
/// the removals made while they ran (#116).
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
/// A fetch lasts as long as someone waits for it. Each open that joins it is
/// counted, and one that is cancelled — its reader left the document — leaves; when
/// the last one has, the fetch is cancelled and forgotten, so it stops spending the
/// bandwidth of someone on a metered or poor connection, writes nothing, and the
/// next open starts afresh. While any reader still waits, it goes on: closing one
/// of two tabs on a document does not fail the other.
///
/// A value, held by the store's actor, which is what serialises it. Here rather
/// than in the App target for its tests.
public struct InFlightDownloads<Value: Sendable> {
  private struct Running {
    let task: Task<Value, any Error>
    var waiters: Int
  }

  private var running: [DocumentID: Running] = [:]
  private var generations: [DocumentID: Int] = [:]

  public init() {}

  /// The fetch for `id` already running, or the one `start` makes, and the removal
  /// generation to check its result against. The caller is now one of its waiters,
  /// and awaits it with `value(of:leave:)`.
  public mutating func join(
    _ id: DocumentID, start: () -> Task<Value, any Error>
  ) -> (task: Task<Value, any Error>, generation: Int) {
    var entry = running[id] ?? Running(task: start(), waiters: 0)
    entry.waiters += 1
    running[id] = entry
    return (entry.task, generations[id, default: 0])
  }

  /// Called by everyone who awaited `task`, once it has. Forgets it only if it is
  /// still the one running for `id`: a later open may have started another.
  public mutating func finish(_ id: DocumentID, _ task: Task<Value, any Error>) {
    if running[id]?.task == task {
      running[id] = nil
    }
  }

  /// A waiter for `task` was cancelled. The last one to leave cancels the fetch
  /// and forgets it, so a later open starts another.
  public mutating func leave(_ id: DocumentID, _ task: Task<Value, any Error>) {
    guard var entry = running[id], entry.task == task else { return }
    entry.waiters -= 1
    if entry.waiters > 0 {
      running[id] = entry
    } else {
      running[id] = nil
      task.cancel()
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

  /// How many readers are waiting for the fetch for `id`.
  public func waiters(_ id: DocumentID) -> Int {
    running[id]?.waiters ?? 0
  }

  /// One waiter's wait for `task`, joined with `join`. Awaiting a task does not
  /// pass the waiter's cancellation on to it, so this does: `leave` is called once
  /// the waiter is cancelled, and is expected to hop to the store's actor and call
  /// `leave(_:_:)` there.
  ///
  /// A fetch that was cancelled throws `CancellationError` even when it finished
  /// anyway, as a parse that does not look at cancellation does, so its result is
  /// never written.
  public static func value(
    of task: Task<Value, any Error>, leave: @escaping @Sendable () async -> Void
  ) async throws -> Value {
    let value = try await withTaskCancellationHandler {
      try await task.value
    } onCancel: {
      Task { await leave() }
    }
    if task.isCancelled {
      throw CancellationError()
    }
    return value
  }
}
