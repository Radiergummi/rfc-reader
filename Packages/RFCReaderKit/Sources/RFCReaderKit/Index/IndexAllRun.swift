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

  /// Remove Full-Text Index is under way, during which no run starts.
  public private(set) var isRemoving = false

  @ObservationIgnored private var task: Task<Void, Never>?

  public init() {}

  /// Indexes every one of `ids` with `indexer`, downloading with `fetch`, unless a
  /// run is going already. `changed` is `TextIndexer.indexAll`'s.
  public func start(
    _ ids: [DocumentID], indexer: TextIndexer,
    fetch: @escaping @Sendable (DocumentID) async throws -> RFCDocument,
    changed: @escaping @Sendable () async -> Void = {}
  ) {
    guard !isRunning, !isRemoving else { return }
    isRunning = true
    task = Task {
      let ended = await indexer.indexAll(
        ids, fetch: fetch,
        progress: { [weak self] progress in await self?.report(progress) }, changed: changed)
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

  /// Remove Full-Text Index: stops the run, then takes the index back to the bodies
  /// the store holds (`TextIndexer.releaseRetained`). Once at a time.
  public func remove(from indexer: TextIndexer, changed: @escaping @Sendable () async -> Void = {})
    async
  {
    guard !isRemoving else { return }
    isRemoving = true
    defer { isRemoving = false }
    stop()
    await untilEnded()
    progress = nil
    await indexer.releaseRetained(changed: changed)
  }

  /// The RFCs of `rfcs` a run can index: those listed with a text or an XML. One
  /// listed with only a PDF or a PostScript has no text to index.
  public nonisolated static func indexable(_ rfcs: [RFCMetadata]) -> [RFCMetadata] {
    rfcs.filter { $0.formats.contains(.text) || $0.formats.contains(.xml) }
  }

  private func report(_ progress: TextIndexer.CorpusProgress) {
    self.progress = progress
  }
}
