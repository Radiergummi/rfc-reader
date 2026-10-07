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
  /// run left it, and every fetch since.
  public private(set) var status = OfflineStatus()

  @ObservationIgnored private let store: DocumentStore
  /// For a fetch somebody waits for: Keep Offline tapped, Download Now, Retry.
  @ObservationIgnored private let client: any DocumentFetching
  /// For a fetch nobody waits for, which never takes an expensive or constrained
  /// path, even one the device moves to while it runs.
  @ObservationIgnored private let clientOnCheapNetworks: any DocumentFetching
  /// The formats the index lists for a document, which a fetch chooses from.
  @ObservationIgnored private let formats: (DocumentID) -> [FileFormat]

  /// The fetches this has running, with a token each, so a fetch that ends removes
  /// itself and not one started after it for the same document.
  @ObservationIgnored
  private var fetches: [DocumentID: (token: UUID, task: Task<Void, any Error>)] = [:]

  /// The documents whose last fetch failed, which no run fetches again until Retry
  /// or `forgetFailures()`.
  @ObservationIgnored private var failures: Set<DocumentID> = []

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
  /// to another path, on which they may succeed.
  public func forgetFailures() {
    failures = []
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
    failures.formIntersection(wanted)
    let plan = OfflineReconciler.plan(
      wanted: wanted, kept: state.kept, cached: state.cached, running: state.running,
      own: Set(fetches.keys), failed: failures, policy: policy)
    for id in plan.leave {
      fetches.removeValue(forKey: id)?.task.cancel()
    }
    var kept = state.kept
    for id in plan.keep {
      do {
        try await store.keepCached(id)
        kept.insert(id)
      } catch {
        offlineLog.error(
          "\(id.displayName, privacy: .public): not moved into the kept tier: \(String(describing: error), privacy: .public)"
        )
      }
    }
    for id in plan.release {
      await store.release(id)
      kept.remove(id)
    }
    // Another run may have started one while this one waited on the store.
    for id in plan.fetch where fetches[id] == nil {
      start(id, client: clientOnCheapNetworks)
    }
    // A fetch left above was still running when the state was read.
    let othersRunning = state.running.intersection(wanted).subtracting(plan.leave)
    status = OfflineStatus(
      kept: kept.intersection(wanted),
      downloading: Set(fetches.keys).union(othersRunning),
      failed: failures, waiting: plan.waiting, deferral: plan.deferral)
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
  /// network. The fetch is this keeper's own, joined if one is running, so
  /// unmarking leaves it as it leaves any other, and throws `CancellationError` here.
  public func fetchNow(_ id: DocumentID) async throws {
    let task = fetches[id]?.task ?? start(id, client: client)
    try await task.value
  }

  @discardableResult
  private func start(_ id: DocumentID, client: any DocumentFetching) -> Task<Void, any Error> {
    let token = UUID()
    let formats = formats(id)
    failures.remove(id)
    status.failed.remove(id)
    status.waiting.remove(id)
    status.downloading.insert(id)
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
        // path stopped allowing it.
        if !(error is CancellationError) {
          failures.insert(id)
          status.failed.insert(id)
          offlineLog.error(
            "\(id.displayName, privacy: .public): keeping offline failed: \(String(describing: error), privacy: .public)"
          )
        }
        throw error
      }
    }
    fetches[id] = (token, task)
    return task
  }
}
