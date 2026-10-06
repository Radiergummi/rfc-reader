import Foundation
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
/// store's own sequences. The App target runs it whenever what is wanted changes.
@MainActor
public final class OfflineKeeper {
  private let store: DocumentStore
  private let client: any DocumentFetching
  /// The formats the index lists for a document, which a fetch chooses from.
  private let formats: (DocumentID) -> [FileFormat]

  /// The fetches this has running, with a token each, so a fetch that ends removes
  /// itself and not one started after it for the same document.
  private var fetches: [DocumentID: (token: UUID, task: Task<Void, any Error>)] = [:]

  public init(
    store: DocumentStore, client: any DocumentFetching,
    formats: @escaping (DocumentID) -> [FileFormat]
  ) {
    self.store = store
    self.client = client
    self.formats = formats
  }

  /// Carries out the plan for `wanted`. Returns once the moves are made and the
  /// fetches started, not finished.
  public func reconcile(wanted: Set<DocumentID>) async {
    await store.setWanted(wanted)
    let state = await store.offlineState()
    let plan = OfflineReconciler.plan(
      wanted: wanted, kept: state.kept, cached: state.cached, running: state.running,
      own: Set(fetches.keys))
    for id in plan.leave {
      fetches.removeValue(forKey: id)?.task.cancel()
    }
    for id in plan.keep {
      do {
        try await store.keepCached(id)
      } catch {
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
      start(id)
    }
  }

  /// Keeps `id` now, for a reader who tapped Keep Offline and waits to hear how it
  /// went: a move when it is cached, a fetch otherwise, on any network. The fetch
  /// is this keeper's own, joined if one is running, so unmarking leaves it as it
  /// leaves any other, and throws `CancellationError` here.
  public func fetchNow(_ id: DocumentID) async throws {
    let task = fetches[id]?.task ?? start(id)
    try await task.value
  }

  @discardableResult
  private func start(_ id: DocumentID) -> Task<Void, any Error> {
    let token = UUID()
    let formats = formats(id)
    let task = Task {
      defer {
        if fetches[id]?.token == token { fetches[id] = nil }
      }
      do {
        try await store.keep(id, formats: formats, client: client)
      } catch {
        // A cancellation is a fetch left: the document is no longer wanted.
        if !(error is CancellationError) {
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

  /// Until every fetch this has running has ended: each removes itself as it ends.
  func settle() async {
    while let fetch = fetches.values.first {
      _ = await fetch.task.result
    }
  }
}
