import CoreSpotlight
import Foundation
import RFCKit
import RFCReaderKit
import os

nonisolated private let spotlightLog = Logger(
  subsystem: Bundle.main.bundleIdentifier ?? "me.mazetti.rfc-reader", category: "spotlight")

/// Keeps every RFC in the index in Spotlight (#178), so system search finds one by
/// number, title or abstract. What an item says is `SpotlightEntry`'s; this only
/// hands it to CoreSpotlight.
enum SpotlightIndexer {
  /// Items per batch: enough that 9,842 RFCs are twenty batches, few enough that
  /// none holds much at once.
  nonisolated private static let batchSize = 500

  /// Indexes `rfcs`, unless the same entries were indexed already this week
  /// (`SpotlightEntry.clientState`). Off the main actor: building ten thousand
  /// attribute sets is work nobody waits for. A failure is logged, not shown (#125):
  /// the app works the same without it.
  @concurrent
  static func update(_ rfcs: [RFCMetadata]) async {
    guard CSSearchableIndex.isIndexingAvailable() else { return }
    let index = CSSearchableIndex(name: SpotlightEntry.domain)
    let entries = rfcs.map(SpotlightEntry.init)
    let state = SpotlightEntry.clientState(for: entries, now: .now)
    do {
      if try await index.fetchLastClientState() == state { return }
      let expiration = Date.now.addingTimeInterval(SpotlightEntry.lifetime)
      for start in stride(from: 0, to: entries.count, by: batchSize) {
        // A newer index has replaced this one: it indexes everything itself, and
        // the client state is left for it to write.
        guard !Task.isCancelled else { return }
        let end = min(start + batchSize, entries.count)
        let items = entries[start..<end].map { item($0, expiring: expiration) }
        index.beginBatch()
        // No completion to wait for inside a batch: `endBatch` reports the outcome.
        index.indexSearchableItems(items, completionHandler: nil)
        // The state only with the last batch: an indexing cut short is done again
        // at the next launch rather than taken for finished.
        try await index.endBatch(withClientState: end == entries.count ? state : Data())
      }
      spotlightLog.debug("indexed \(entries.count) RFCs")
    } catch {
      spotlightLog.error(
        "indexing for Spotlight failed: \(String(describing: error), privacy: .public)")
    }
  }

  nonisolated private static func item(_ entry: SpotlightEntry, expiring expiration: Date)
    -> CSSearchableItem
  {
    let attributes = CSSearchableItemAttributeSet(contentType: .text)
    attributes.title = entry.title
    attributes.contentDescription = entry.description
    attributes.keywords = entry.keywords
    let item = CSSearchableItem(
      uniqueIdentifier: entry.identifier, domainIdentifier: SpotlightEntry.domain,
      attributeSet: attributes)
    item.expirationDate = expiration
    return item
  }
}
