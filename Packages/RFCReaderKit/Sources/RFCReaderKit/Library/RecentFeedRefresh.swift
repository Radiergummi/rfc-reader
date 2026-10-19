import Foundation
import RFCKit

/// Just Published at launch (#421): the feed kept is shown at once, then the RFC
/// Editor is asked whether it has a newer one, with the kept feed's validators, so
/// that an unchanged feed is a `304` rather than the whole feed again.
///
/// Nobody is waiting for it, so the caller hands in a client that waits for a network
/// that is neither metered nor in Low Data Mode (`URLSession.rfcEditorOnCheapNetworks`).
/// A fetch that fails leaves the feed kept on screen, as a failed refresh of the index
/// leaves the index.
public enum RecentFeedRefresh {
  /// Shows the feed kept, if there is one that parses, then the feed fetched, if it
  /// changed, and keeps that. Throws when the fetch, its parse or keeping it fails,
  /// after showing what it could.
  public static func run(
    store: DocumentStore, client: RFCEditorClient, show: ([RecentRFC]) -> Void
  ) async throws {
    var kept: [RecentRFC]?
    if let data = await store.cachedRecentFeed() {
      kept = try? await parse(data)
    }
    if let kept { show(kept) }
    // Without a feed shown, a `304` would leave nothing to show.
    let validators = kept == nil ? nil : store.recentFeedCheck()?.validators(at: .now)
    let fetched = try await client.fetchRecentData(
      unlessMatching: validators, onExpensiveNetworks: false)
    guard case .changed(let data, let newValidators) = fetched else { return }
    // Shown before it is kept, so a failed write loses only the copy on disk.
    show(try await parse(data))
    try await store.storeRecentFeed(data, validators: newValidators)
  }

  /// Off the caller's actor, which is the main actor during launch.
  @concurrent
  private static func parse(_ data: Data) async throws -> [RecentRFC] {
    try RecentRFC.parseFeed(data)
  }
}
