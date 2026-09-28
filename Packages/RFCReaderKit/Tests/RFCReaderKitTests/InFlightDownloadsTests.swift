import Foundation
import RFCKit
import Testing

@testable import RFCReaderKit

/// Downloads the store has running (#116): a second open joins the first, a
/// removal made while one is in flight keeps its result off the disk, and one that
/// no reader waits for any more is cancelled.
@Suite("In-flight downloads")
struct InFlightDownloadsTests {
  /// Holds a fetch in flight until the test lets it finish.
  private actor Gate {
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var isOpen = false

    func wait() async {
      guard !isOpen else { return }
      await withCheckedContinuation { waiters.append($0) }
    }

    func open() {
      isOpen = true
      for waiter in waiters {
        waiter.resume()
      }
      waiters = []
    }
  }

  /// The store's use of `InFlightDownloads`, with a fetch that waits on a gate and a
  /// disk that is a list of what was written.
  private actor Store {
    let downloads = InFlightDownloads<Data>()
    private(set) var written: [DocumentID] = []
    private(set) var fetches = 0
    /// Every fetch started, in order, so a test can ask whether one was cancelled.
    private(set) var started: [Task<Data, any Error>] = []

    /// The fetch does not look at cancellation, as a parse does not: a cancelled
    /// one still finishes once the gate opens, and must still not be written.
    func open(_ id: DocumentID, gate: Gate) async throws -> Data {
      let (data, isKept) = try await downloads.value(for: id) {
        fetches += 1
        let task = Task<Data, any Error> {
          await gate.wait()
          return Data("\(id)".utf8)
        }
        started.append(task)
        return task
      }
      if isKept {
        written.append(id)
      }
      return data
    }

    func remove(_ id: DocumentID) {
      downloads.removed(id)
    }

    func isRunning(_ id: DocumentID) -> Bool {
      downloads.isRunning(id)
    }

    func waiters(_ id: DocumentID) -> Int {
      downloads.waiters(id)
    }
  }

  /// Until the store's fetch for `id` is in flight: a task started is not yet a task
  /// that has reached the gate.
  private func untilRunning(_ id: DocumentID, in store: Store) async {
    while await !store.isRunning(id) {
      await Task.yield()
    }
  }

  /// Until as many readers wait for the fetch for `id` as `count`: a reader
  /// cancelled has not left until the store has heard about it.
  private func untilWaiting(_ count: Int, for id: DocumentID, in store: Store) async {
    while await store.waiters(id) != count {
      await Task.yield()
    }
  }

  @Test func `a finished download is written`() async throws {
    let store = Store()
    let gate = Gate()
    await gate.open()
    _ = try await store.open(.rfc(9110), gate: gate)
    #expect(await store.written == [.rfc(9110)])
  }

  /// The removal wins over the fetch it overlapped, but the reader that started the
  /// fetch still gets the document it is waiting for.
  @Test func `a removal during a download keeps it off the disk`() async throws {
    let store = Store()
    let gate = Gate()
    let opening = Task { try await store.open(.rfc(9110), gate: gate) }
    await untilRunning(.rfc(9110), in: store)
    await store.remove(.rfc(9110))
    await gate.open()

    #expect(try await opening.value == Data("\(DocumentID.rfc(9110))".utf8))
    #expect(await store.written.isEmpty)
  }

  /// The fetch overlapped the removal, whoever waits for it: a reader who joins it
  /// afterwards does not bring it back.
  @Test func `a removal during a shared download keeps it off the disk`() async throws {
    let store = Store()
    let gate = Gate()
    let first = Task { try await store.open(.rfc(9110), gate: gate) }
    await untilRunning(.rfc(9110), in: store)
    await store.remove(.rfc(9110))
    let second = Task { try await store.open(.rfc(9110), gate: gate) }
    await untilWaiting(2, for: .rfc(9110), in: store)
    await gate.open()

    #expect(try await first.value == second.value)
    #expect(await store.written.isEmpty)
  }

  /// Every reader of one fetch gets its result, and it is written once.
  @Test func `a shared download is written once`() async throws {
    let store = Store()
    let gate = Gate()
    let first = Task { try await store.open(.rfc(9110), gate: gate) }
    await untilRunning(.rfc(9110), in: store)
    let second = Task { try await store.open(.rfc(9110), gate: gate) }
    await untilWaiting(2, for: .rfc(9110), in: store)
    await gate.open()

    #expect(try await first.value == second.value)
    #expect(await store.written == [.rfc(9110)])
  }

  @Test func `a second open joins the download already running`() async throws {
    let store = Store()
    let gate = Gate()
    let first = Task { try await store.open(.rfc(9110), gate: gate) }
    await untilRunning(.rfc(9110), in: store)
    let second = Task { try await store.open(.rfc(9110), gate: gate) }
    await untilWaiting(2, for: .rfc(9110), in: store)
    await gate.open()

    #expect(try await first.value == second.value)
    #expect(await store.fetches == 1)
  }

  /// A removal is about the download it overlapped, not every one after it.
  @Test func `a download started after a removal is written`() async throws {
    let store = Store()
    let gate = Gate()
    await store.remove(.rfc(9110))
    await gate.open()
    _ = try await store.open(.rfc(9110), gate: gate)
    #expect(await store.written == [.rfc(9110)])
  }

  @Test func `a removal of one document leaves another's download alone`() async throws {
    let store = Store()
    let gate = Gate()
    let other = Task { try await store.open(.rfc(2119), gate: gate) }
    await untilRunning(.rfc(2119), in: store)
    await store.remove(.rfc(9110))
    await gate.open()
    _ = try await other.value
    #expect(await store.written == [.rfc(2119)])
  }

  @Test func `a finished download is no longer running`() async throws {
    let store = Store()
    let gate = Gate()
    await gate.open()
    _ = try await store.open(.rfc(9110), gate: gate)
    #expect(await !store.isRunning(.rfc(9110)))
  }

  /// Nobody is waiting for it, so it no longer spends the reader's bandwidth (#116).
  @Test func `a download nobody waits for is cancelled`() async throws {
    let store = Store()
    let gate = Gate()
    let opening = Task { try await store.open(.rfc(9110), gate: gate) }
    await untilRunning(.rfc(9110), in: store)
    opening.cancel()
    await untilWaiting(0, for: .rfc(9110), in: store)
    await gate.open()

    await #expect(throws: CancellationError.self) { try await opening.value }
    #expect(await store.started.first?.isCancelled == true)
    #expect(await store.written.isEmpty)
    #expect(await !store.isRunning(.rfc(9110)))
  }

  /// Two tabs on the same document: closing one keeps the other's download going.
  @Test func `a download another reader still waits for goes on`() async throws {
    let store = Store()
    let gate = Gate()
    let first = Task { try await store.open(.rfc(9110), gate: gate) }
    await untilRunning(.rfc(9110), in: store)
    let second = Task { try await store.open(.rfc(9110), gate: gate) }
    await untilWaiting(2, for: .rfc(9110), in: store)
    first.cancel()
    await untilWaiting(1, for: .rfc(9110), in: store)
    await gate.open()

    #expect(try await second.value == Data("\(DocumentID.rfc(9110))".utf8))
    #expect(await store.started.first?.isCancelled == false)
    #expect(await store.written == [.rfc(9110)])
  }

  @Test func `an open after a cancelled download starts a new one`() async throws {
    let store = Store()
    let gate = Gate()
    let cancelled = Task { try await store.open(.rfc(9110), gate: gate) }
    await untilRunning(.rfc(9110), in: store)
    cancelled.cancel()
    await untilWaiting(0, for: .rfc(9110), in: store)
    await gate.open()
    _ = try? await cancelled.value

    _ = try await store.open(.rfc(9110), gate: gate)
    #expect(await store.fetches == 2)
    #expect(await store.written == [.rfc(9110)])
  }

  /// A fetch that notices its cancellation fails with its own error, as URLSession
  /// does with `URLError.cancelled`; the reader still sees a cancellation, not a
  /// failure to show.
  @Test func `a cancelled download throws a cancellation whatever it failed with`() async throws {
    let downloads = InFlightDownloads<Data>()
    let gate = Gate()
    let opening = Task {
      try await downloads.value(for: .rfc(9110)) {
        Task<Data, any Error> {
          await gate.wait()
          throw URLError(Task.isCancelled ? .cancelled : .badServerResponse)
        }
      }
    }
    while !downloads.isRunning(.rfc(9110)) {
      await Task.yield()
    }
    opening.cancel()
    while downloads.isRunning(.rfc(9110)) {
      await Task.yield()
    }
    await gate.open()

    await #expect(throws: CancellationError.self) { try await opening.value }
  }
}
