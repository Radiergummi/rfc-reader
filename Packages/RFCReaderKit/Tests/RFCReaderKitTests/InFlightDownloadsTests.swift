import Foundation
import RFCKit
import Testing

@testable import RFCReaderKit

/// Downloads the store has running (#116): a second open joins the first, and a
/// removal made while one is in flight keeps its result off the disk.
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
      waiters.forEach { $0.resume() }
      waiters = []
    }
  }

  /// The store's use of `InFlightDownloads`, with a fetch that waits on a gate and a
  /// disk that is a list of what was written.
  private actor Store {
    var downloads = InFlightDownloads<Data>()
    private(set) var written: [DocumentID] = []
    private(set) var fetches = 0

    func open(_ id: DocumentID, gate: Gate) async throws -> Data {
      let (task, generation) = downloads.join(id) {
        fetches += 1
        return Task {
          await gate.wait()
          return Data("\(id)".utf8)
        }
      }
      let data = try await task.value
      downloads.finish(id, task)
      if downloads.isCurrent(id, since: generation) {
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
  }

  /// Until the store's fetch for `id` is in flight: a task started is not yet a task
  /// that has reached the gate.
  private func untilRunning(_ id: DocumentID, in store: Store) async {
    while await !store.isRunning(id) {
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

    #expect(try await opening.value == Data("RFC 9110".utf8))
    #expect(await store.written.isEmpty)
  }

  @Test func `a second open joins the download already running`() async throws {
    let store = Store()
    let gate = Gate()
    let first = Task { try await store.open(.rfc(9110), gate: gate) }
    await untilRunning(.rfc(9110), in: store)
    let second = Task { try await store.open(.rfc(9110), gate: gate) }
    await Task.yield()
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
}
