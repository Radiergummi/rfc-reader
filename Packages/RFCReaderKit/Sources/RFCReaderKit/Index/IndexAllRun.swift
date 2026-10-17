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
  /// What the run in progress, or the last one, reported last; nil before a run's
  /// first report.
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
    progress = nil
    // Below what the person does meanwhile, as the indexing of stored bodies is; and,
    // on the Mac, not napped while its windows are hidden.
    let activity = ProcessInfo.processInfo.beginActivity(
      options: .userInitiatedAllowingIdleSystemSleep, reason: "Index All RFCs")
    task = Task(priority: .utility) {
      let ended = await indexer.indexAll(
        ids, fetch: fetch,
        progress: { [weak self] progress in await self?.report(progress) }, changed: changed)
      ProcessInfo.processInfo.endActivity(activity)
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

  /// The RFCs of `rfcs` a run can index, as a narrowed search counts them
  /// (`hasOnlyPrintFormats`): one listed with only a PDF or a PostScript has no text
  /// to index.
  public nonisolated static func indexable(_ rfcs: [RFCMetadata]) -> [RFCMetadata] {
    rfcs.filter { !$0.hasOnlyPrintFormats }
  }

  private func report(_ progress: TextIndexer.CorpusProgress) {
    self.progress = progress
  }
}

extension RFCMetadata {
  /// Whether the index lists only a PDF or a PostScript of it, which have no text to
  /// index. One whose formats are not listed may have a text.
  var hasOnlyPrintFormats: Bool {
    !formats.isEmpty && formats.allSatisfy { $0 == .pdf || $0 == .postScript }
  }
}
