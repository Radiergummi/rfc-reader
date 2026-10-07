import Foundation
import Observation
import RFCKit
import os

private let offlineLog = Logger(
  subsystem: Bundle.main.bundleIdentifier ?? "me.mazetti.rfc-reader", category: "offline")

/// Brings the disk in line with what is wanted offline (#358): tells the store
/// what is wanted, reads what it holds, and carries out `OfflineReconciler`'s plan.
///
/// The reconciler decides; this only does what it says. Its fetches are its own
/// waiters on the store's downloads (see `OfflineReconciler`), held here so it can
/// leave them: one for a document no longer wanted is canceled, which cancels the
/// download only when nobody else waits for it (#116).
///
/// Here rather than in the App target for its tests, which run it against the
/// store's own sequences. The App target runs it whenever what is wanted changes,
/// and whenever the network path or Low Power Mode does.
@MainActor @Observable
public final class OfflineKeeper {
  /// Where each wanted document stands, for Available Offline's rows: as the last
  /// run planned it, and every fetch since. Its `failed` are the documents no run
  /// fetches again until Retry or `forgetFailures()`.
  public private(set) var status = OfflineStatus()

  @ObservationIgnored private let store: DocumentStore
  /// For a fetch somebody waits for: Keep Offline tapped, Download Now, Retry.
  @ObservationIgnored private let client: any DocumentFetching
  /// For a fetch nobody waits for, which never takes an expensive or constrained
  /// path, and fails when the device moves to one while it runs.
  @ObservationIgnored private let clientOnCheapNetworks: any DocumentFetching
  /// The formats the index lists for a document, which a fetch chooses from.
  @ObservationIgnored private let formats: (DocumentID) -> [FileFormat]

  private struct Fetch {
    /// Tells this fetch from a later one for the same document, so the one that
    /// ends removes itself and not its successor.
    let token: UUID
    let task: Task<Void, any Error>
    /// Somebody waits for it, so it runs on any path, and a path that stops
    /// allowing the others leaves it running.
    let isAwaited: Bool
  }

  /// The fetches this has running.
  @ObservationIgnored private var fetches: [DocumentID: Fetch] = [:]

  /// What was last asked for, which a run started to finish an earlier one's work
  /// carries out instead of what that one was asked.
  @ObservationIgnored private var wanted: Set<DocumentID> = []
  @ObservationIgnored private var policy = FetchPolicy.Decision.fetch

  /// The run in progress, or the last, which the next waits for, so two never
  /// interleave their moves.
  @ObservationIgnored private var run: Task<Void, Never>?

  /// Waits for the downloads the last run had to leave a body to, then runs again.
  @ObservationIgnored private var rerun: Task<Void, Never>?

  /// - Parameter clientOnCheapNetworks: the client for the fetches nobody waits for;
  ///   `client` when nil.
  public init(
    store: DocumentStore, client: any DocumentFetching,
    clientOnCheapNetworks: (any DocumentFetching)? = nil,
    formats: @escaping (DocumentID) -> [FileFormat]
  ) {
    self.store = store
    self.client = client
    self.clientOnCheapNetworks = clientOnCheapNetworks ?? client
    self.formats = formats
  }

  /// Carries out the plan for `wanted`, after any run already asked for, starting
  /// the fetches it owes only if `policy` allows a fetch nobody waits for. The task
  /// ends once the moves are made and the fetches started, not finished.
  @discardableResult
  public func reconcile(wanted: Set<DocumentID>, policy: FetchPolicy.Decision = .fetch)
    -> Task<Void, Never>
  {
    self.wanted = wanted
    self.policy = policy
    let previous = run
    let current = Task {
      await previous?.value
      await carryOut(wanted, policy: policy)
    }
    run = current
    return current
  }

  /// Lets the next run fetch the documents whose fetch failed: the device has moved
  /// to another network, on which they may succeed.
  public func forgetFailures() {
    status.failed = []
  }

  /// Until what has been asked for `id` is done: every run asked for so far, and a
  /// fetch of it that one of them or a reader started.
  public func untilSettled(_ id: DocumentID) async {
    await run?.value
    _ = await fetches[id]?.task.result
  }

  private func carryOut(_ wanted: Set<DocumentID>, policy: FetchPolicy.Decision) async {
    await store.setWanted(wanted)
    let state = await store.offlineState()
    let failed = status.failed.intersection(wanted)
    let discretionary = Set(fetches.filter { !$0.value.isAwaited }.keys)
    let plan = OfflineReconciler.plan(
      wanted: wanted, kept: state.kept, cached: state.cached, running: state.running,
      own: discretionary, failed: failed, policy: policy)
    // A fetch somebody waits for is left only when its document is no longer wanted.
    let awaited = Set(fetches.keys).subtracting(discretionary)
    let leave = plan.leave.union(awaited.subtracting(wanted))
    for id in leave {
      fetches.removeValue(forKey: id)?.task.cancel()
    }
    // Set before the moves rather than after, which suspend: what a fetch records
    // meanwhile stands. A fetch left above was still running when the state was read.
    status = OfflineStatus(
      kept: state.kept.union(plan.keep).subtracting(plan.release).intersection(wanted),
      downloading: Set(fetches.keys).union(state.running.intersection(wanted).subtracting(leave)),
      failed: failed, waiting: plan.waiting, deferral: plan.deferral)
    for id in plan.keep {
      do {
        try await store.keepCached(id)
      } catch {
        status.kept.remove(id)
        offlineLog.error(
          "\(id.displayName, privacy: .public): not moved into the kept tier: \(String(describing: error), privacy: .public)"
        )
      }
    }
    for id in plan.release {
      await store.release(id)
    }
    // Another run may have started one while this one waited on the store.
    for id in plan.fetch where fetches[id] == nil {
      start(id, isAwaited: false)
    }
    // The plan leaves a body alone while a download may still write it, and nothing
    // else would run again once the download ends; nor would the status learn that
    // a reader's download of a wanted document has written it.
    let left = state.running.intersection(wanted.union(state.kept))
      .subtracting(fetches.keys)
    rerun?.cancel()
    rerun = nil
    guard !left.isEmpty else { return }
    rerun = Task {
      await store.untilDownloadsEnd(of: left)
      guard !Task.isCancelled else { return }
      reconcile(wanted: self.wanted, policy: self.policy)
    }
  }

  /// Keeps `id` now, for a reader who tapped Keep Offline, Download Now or Retry and
  /// waits to hear how it went: a move when it is cached, a fetch otherwise, on any
  /// network. The fetch is this keeper's own, joined if one somebody waits for is
  /// running, so unmarking leaves it as it leaves any other, and throws
  /// `CancellationError` here. One nobody waits for is left first, and its download
  /// with it unless a reader shares it, since it would not take every path.
  public func fetchNow(_ id: DocumentID) async throws {
    if let running = fetches[id], running.isAwaited {
      try await running.task.value
      return
    }
    if let running = fetches.removeValue(forKey: id) {
      running.task.cancel()
      _ = await running.task.result
    }
    try await start(id, isAwaited: true).value
  }

  @discardableResult
  private func start(_ id: DocumentID, isAwaited: Bool) -> Task<Void, any Error> {
    let formats = formats(id)
    let client = isAwaited ? client : clientOnCheapNetworks
    status.failed.remove(id)
    status.waiting.remove(id)
    status.downloading.insert(id)
    let token = UUID()
    let task = Task {
      defer {
        if fetches[id]?.token == token {
          fetches[id] = nil
          status.downloading.remove(id)
        }
      }
      do {
        try await store.keep(id, formats: formats, client: client)
        status.kept.insert(id)
      } catch {
        // A cancellation is a fetch left: the document is no longer wanted, or the
        // path stopped allowing it. So is a path that stopped allowing it before
        // the keeper heard: the run the path change starts says it waits.
        let isPathRefused = (error as? URLError)?.networkUnavailableReason != nil
        if !(error is CancellationError), !isPathRefused {
          status.failed.insert(id)
          offlineLog.error(
            "\(id.displayName, privacy: .public): keeping offline failed: \(String(describing: error), privacy: .public)"
          )
        }
        throw error
      }
    }
    fetches[id] = Fetch(token: token, task: task, isAwaited: isAwaited)
    return task
  }
}
