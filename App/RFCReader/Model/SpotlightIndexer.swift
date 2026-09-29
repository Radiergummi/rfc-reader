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

  /// Indexes `rfcs`, unless this index was indexed already this week
  /// (`SpotlightEntry.clientState`). Off the main actor: building ten thousand
  /// attribute sets is work nobody waits for. A failure is logged, not shown (#125):
  /// the app works the same without it.
  @concurrent
  static func update(_ rfcs: [RFCMetadata], indexUpdatedAt: Date) async {
    guard CSSearchableIndex.isIndexingAvailable() else { return }
    let index = CSSearchableIndex(name: SpotlightEntry.domain)
    let state = SpotlightEntry.clientState(indexUpdatedAt: indexUpdatedAt, now: .now)
    do {
      if try await index.fetchLastClientState() == state { return }
      let expiration = Date.now.addingTimeInterval(SpotlightEntry.lifetime)
      for start in stride(from: 0, to: rfcs.count, by: batchSize) {
        let end = min(start + batchSize, rfcs.count)
        let items = rfcs[start..<end].map { item(SpotlightEntry($0), expiring: expiration) }
        index.beginBatch()
        // No completion to wait for inside a batch: `endBatch` reports the outcome.
        index.indexSearchableItems(items, completionHandler: nil)
        // The state only with the last batch: an indexing cut short is done again
        // at the next launch rather than taken for finished.
        try await index.endBatch(withClientState: end == rfcs.count ? state : Data())
      }
      spotlightLog.debug("indexed \(rfcs.count) RFCs")
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

  /// The RFC a chosen Spotlight result names, if the activity is one.
  static func link(from activity: NSUserActivity) -> RFCLink? {
    guard activity.activityType == CSSearchableItemActionType,
      let identifier = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String,
      let id = SpotlightEntry.documentID(fromIdentifier: identifier)
    else { return nil }
    return RFCLink(id: id)
  }
}
