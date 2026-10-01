import Foundation
import RFCKit
import Synchronization

/// The downloads the document store has running, the readers waiting for each, and
/// the removals made while they ran (#116).
///
/// A fetch suspends, and while it does the store's actor runs other calls. Without
/// this, a Remove Download made during a fetch finished first, and then the fetch
/// resumed and wrote the document back: the removal was silently undone.
///
/// A removal during a download does not cancel it. A fetch is only ever started by
/// opening the document, so the reader is waiting for it, and canceling would turn
/// "don't keep this offline" into an error in front of them. Instead the removal
/// marks the running fetch, and a marked fetch is not kept, whoever waits for it: a
/// reader who joins it after the removal does not bring it back either. The readers
/// still get the document; the disk does not.
///
/// While one fetch for a document is running, a second open joins it rather than
/// fetching again, and only one of the readers is told to keep the result, so it
/// is written once.
///
/// A fetch lasts as long as someone waits for it. Each open that joins it is
/// counted, and one that is canceled — its reader left the document — leaves at
/// once, without waiting for the fetch to end; when the last one has, the fetch is
/// canceled and forgotten, so it stops spending the bandwidth of someone on a
/// metered or poor connection, writes nothing, and the next open starts afresh. While any reader still waits, it goes on: closing one
/// of two tabs on a document does not fail the other.
///
/// A type of its own rather than part of `DocumentStore` for its tests, which run
/// the store's own sequence.
public final class InFlightDownloads<Value: Sendable>: Sendable {
  private struct Running {
    let task: Task<Value, any Error>
    /// Every reader waiting for it, by the number `value(for:start:)` gave them,
    /// with the continuation they are suspended on once they are.
    var waiting: [Int: CheckedContinuation<Void, Never>?] = [:]
    var nextWaiter = 0
    /// It has ended, and every waiter has been woken to read it.
    var isFinished = false
    /// A removal came while it ran, so its result is not kept.
    var isRemoved = false
  }

  /// Behind a lock rather than on an actor, so a waiter's cancellation handler,
  /// which runs wherever the cancellation came from, can leave without a hop.
  private let running = Mutex<[DocumentID: Running]>([:])

  public init() {}

  /// The result of the fetch for `id`: the one already running, or the one `start`
  /// makes. `isKept` is whether this caller is to write it, which exactly one
  /// reader of a fetch is, unless a removal came while it ran.
  ///
  /// Runs on the caller's actor, so a caller that writes the result right away,
  /// with no suspension between, cannot have a removal slip in before its write.
  ///
  /// Awaiting a task does not pass the waiter's cancellation on to it, nor end the
  /// wait, so a waiter suspends on a continuation of its own instead: one that is
  /// canceled leaves and throws `CancellationError` at once, and the last to leave
  /// cancels the fetch. A canceled fetch throws `CancellationError`, whatever it
  /// failed with or even when it finished anyway, as a parse that does not look at
  /// cancellation does, so its result is never written.
  public nonisolated(nonsending) func value(
    for id: DocumentID, start: () -> Task<Value, any Error>
  ) async throws -> (value: Value, isKept: Bool) {
    let (task, waiter) = running.withLock { running in
      var entry: Running
      if let existing = running[id] {
        entry = existing
      } else {
        entry = Running(task: start())
        watch(id, entry.task)
      }
      let waiter = entry.nextWaiter
      entry.nextWaiter += 1
      entry.waiting[waiter] = .some(nil)
      running[id] = entry
      return (entry.task, waiter)
    }
    // The check is inside the handler's scope: a cancellation that lands after it
    // left would throw without `leave`, and leave the finished fetch behind for the
    // next open to join.
    try await withTaskCancellationHandler {
      await withCheckedContinuation { continuation in
        if !attach(continuation, as: waiter, to: id, task) {
          continuation.resume()
        }
      }
      try Task.checkCancellation()
    } onCancel: {
      leave(id, task, waiter)
    }

    let value: Value
    do {
      value = try await task.value
    } catch {
      finish(id, task)
      throw task.isCancelled ? CancellationError() : error
    }
    let isKept = finish(id, task)
    guard !task.isCancelled else { throw CancellationError() }
    return (value, isKept)
  }

  /// A removal: whatever is running for `id` now finishes without being kept.
  public func removed(_ id: DocumentID) {
    running.withLock { running in
      running[id]?.isRemoved = true
    }
  }

  /// Wakes everyone waiting for `task` once it has ended.
  private func watch(_ id: DocumentID, _ task: Task<Value, any Error>) {
    Task {
      _ = await task.result
      let woken = running.withLock { running in
        guard var entry = running[id], entry.task == task else {
          return [CheckedContinuation<Void, Never>]()
        }
        entry.isFinished = true
        let woken = entry.waiting.values.compactMap { $0 }
        for waiter in entry.waiting.keys {
          entry.waiting[waiter] = .some(nil)
        }
        running[id] = entry
        return woken
      }
      for continuation in woken {
        continuation.resume()
      }
    }
  }

  /// Parks `continuation` until `task` ends or its waiter leaves. False when there
  /// is nothing to wait for: the fetch has ended, or the waiter has already left.
  private func attach(
    _ continuation: CheckedContinuation<Void, Never>, as waiter: Int, to id: DocumentID,
    _ task: Task<Value, any Error>
  ) -> Bool {
    running.withLock { running in
      guard var entry = running[id], entry.task == task, !entry.isFinished,
        entry.waiting[waiter] != nil
      else { return false }
      entry.waiting[waiter] = continuation
      running[id] = entry
      return true
    }
  }

  /// Called by everyone who read `task` once it ended. The first forgets it, and
  /// is the one to keep it unless it was removed; a later open starts afresh. Only
  /// if it is still the one running for `id`: a later open may have started another.
  @discardableResult
  private func finish(_ id: DocumentID, _ task: Task<Value, any Error>) -> Bool {
    running.withLock { running in
      guard let entry = running[id], entry.task == task else { return false }
      running[id] = nil
      return !entry.isRemoved
    }
  }

  /// A waiter for `task` was canceled: it stops waiting now. The last one to leave
  /// cancels the fetch and forgets it, so a later open starts another.
  private func leave(_ id: DocumentID, _ task: Task<Value, any Error>, _ waiter: Int) {
    let continuation = running.withLock { running -> CheckedContinuation<Void, Never>? in
      guard var entry = running[id], entry.task == task,
        let continuation = entry.waiting.removeValue(forKey: waiter)
      else { return nil }
      if entry.waiting.isEmpty {
        running[id] = nil
        task.cancel()
      } else {
        running[id] = entry
      }
      return continuation
    }
    continuation?.resume()
  }

  func isRunning(_ id: DocumentID) -> Bool {
    running.withLock { running in running[id] != nil }
  }

  /// How many readers are waiting for the fetch for `id`.
  func waiters(_ id: DocumentID) -> Int {
    running.withLock { running in running[id]?.waiting.count ?? 0 }
  }
}
