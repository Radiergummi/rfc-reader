import Foundation
import Observation
import RFCKit

/// Index All RFCs (#37), as Settings and the search show it: one run at a time,
/// started by the person and stopped by them, its progress reported as it goes.
///
/// The run itself is `TextIndexer.indexAll`; this holds the task and what it last
/// reported, which stays once the run ends, for its failures to be told.
@MainActor @Observable
public final class IndexAllRun {
  /// What the run in progress, or the last one, reported last; nil before the first.
  public private(set) var progress: TextIndexer.CorpusProgress?

  public private(set) var isRunning = false

  @ObservationIgnored private var task: Task<Void, Never>?

  public init() {}

  /// Indexes every one of `ids` with `indexer`, downloading with `fetch`, unless a
  /// run is going already. `changed` is `TextIndexer.indexAll`'s.
  public func start(
    _ ids: [DocumentID], indexer: TextIndexer,
    fetch: @escaping @Sendable (DocumentID) async throws -> RFCDocument,
    changed: @escaping @Sendable () async -> Void = {}
  ) {
    guard !isRunning else { return }
    isRunning = true
    task = Task {
      let ended = await indexer.indexAll(ids, fetch: fetch) { [weak self] progress in
        await self?.report(progress)
      } changed: {
        await changed()
      }
      progress = ended
      isRunning = false
      task = nil
    }
  }

  /// Stops the run; what it has indexed stays, and the next run goes on from there.
  public func stop() {
    task?.cancel()
  }

  /// Until the run in progress, if any, has ended.
  public func untilEnded() async {
    await task?.value
  }

  private func report(_ progress: TextIndexer.CorpusProgress) {
    // A report from a run already ended would overwrite what it ended with.
    guard isRunning else { return }
    self.progress = progress
  }
}
