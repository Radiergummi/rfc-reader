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
  private var fetches: [DocumentID: (token: UUID, task: Task<Void, Never>)] = [:]

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
        // A cached body, so this moves it and fetches nothing.
        try await store.keep(id, formats: formats(id), client: client)
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

  private func start(_ id: DocumentID) {
    let token = UUID()
    let formats = formats(id)
    let task = Task {
      do {
        try await store.keep(id, formats: formats, client: client)
      } catch is CancellationError {
        // Left: no longer wanted.
      } catch {
        offlineLog.error(
          "\(id.displayName, privacy: .public): keeping offline failed: \(String(describing: error), privacy: .public)"
        )
      }
      if fetches[id]?.token == token { fetches[id] = nil }
    }
    fetches[id] = (token, task)
  }

  /// Until every fetch this has running has ended: each removes itself as it ends.
  func settle() async {
    while let fetch = fetches.values.first {
      await fetch.task.value
    }
  }
}
