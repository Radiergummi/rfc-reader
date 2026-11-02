import AppIntents
import CoreSpotlight
import Foundation
import RFCKit
import RFCReaderKit
import os

nonisolated private let spotlightLog = Logger(
  subsystem: Bundle.main.bundleIdentifier ?? "me.mazetti.rfc-reader", category: "spotlight")

/// Keeps every RFC in the index in Spotlight (#178), so system search finds one by
/// number, title or abstract, and the sections of the documents the app holds, so it
/// finds a passage. What an item says is `SpotlightEntry`'s; this only
/// hands it to CoreSpotlight, with the RFC's `RFCEntity` (#192), so a result is the
/// RFC Shortcuts and Siri act on.
enum SpotlightIndexer {
  /// RFC items per batch: enough that 9,842 RFCs are twenty batches, few enough that
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
    let locale = Locale.interface
    let entries = rfcs.map { SpotlightEntry($0, locale: locale) }
    let state = SpotlightEntry.clientState(for: entries, now: .now)
    do {
      if try await index.fetchLastClientState() == state { return }
      let expiration = Date.now.addingTimeInterval(SpotlightEntry.lifetime)
      for start in stride(from: 0, to: entries.count, by: batchSize) {
        // A newer index has replaced this one: it indexes everything itself, and
        // the client state is left for it to write.
        guard !Task.isCancelled else { return }
        let end = min(start + batchSize, entries.count)
        // The entities only here, past the check that most launches stop at.
        let items = (start..<end).map {
          item(entries[$0], for: RFCEntity(rfcs[$0], locale: locale), expiring: expiration)
        }
        index.beginBatch()
        add(items, to: index)
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

  /// Brings Spotlight's sections to the documents the full-text index holds from a
  /// stored body (`TextIndexer.spotlightDocuments`), as `SpotlightSection.Plan`
  /// says: the documents gone or written again are deleted, then the new ones are
  /// indexed from the full-text index's rows, in `SpotlightSection.Batches`, each
  /// recording what the index then holds (`sectionRecordURL`, with its digest as the
  /// client state). `rebuilding` empties the index and indexes everything, whatever
  /// the record says.
  ///
  /// Off the main actor but for making each batch's items (`submit`): they carry
  /// `SectionEntity`, which is the main actor's.
  @concurrent
  static func updateSections(
    from indexer: TextIndexer, rfcs: [RFCMetadata], rebuilding: Bool
  ) async {
    guard CSSearchableIndex.isIndexingAvailable(), let recordURL = sectionRecordURL,
      let held = await indexer.spotlightDocuments()
    else { return }
    let index = CSSearchableIndex(name: SpotlightSection.domain)
    do {
      let plan = SpotlightSection.Plan(
        held: held, record: rebuilding ? nil : try? Data(contentsOf: recordURL),
        clientState: try await index.fetchLastClientState())
      guard !plan.isEmpty else { return }
      let interval = signposter.beginInterval(
        "Index sections for Spotlight", id: signposter.makeSignpostID(),
        "\(plan.indexed.count) documents")
      var sections = 0
      defer {
        signposter.endInterval("Index sections for Spotlight", interval, "\(sections) sections")
      }
      var batches = SpotlightSection.Batches(kept: plan.kept)
      if plan.deletes {
        // The record first, here as for every batch: a batch that fails leaves one
        // its state was not written for, which the next indexing does not trust.
        let record = batches.initialRecord
        try record.write(to: recordURL, options: .atomic)
        index.beginBatch()
        delete(
          domains: plan.removesEverything
            ? [SpotlightSection.domain] : plan.removed.map(SpotlightSection.domain(of:)),
          from: index)
        try await index.endBatch(
          withClientState: SpotlightSection.Plan.clientState(forRecord: record))
      }
      let titles = Dictionary(
        rfcs.map { ($0.id, $0.title) }, uniquingKeysWith: { first, _ in first })
      for id in plan.indexed {
        guard let written = held[id] else { continue }
        let rows: [FullTextIndex.Row]
        do {
          rows = try await indexer.indexedRows(of: id)
        } catch {
          // Left out of the record, so the next indexing tries it again.
          spotlightLog.error(
            "\(id.displayName, privacy: .public): sections not read for Spotlight: \(String(describing: error), privacy: .public)"
          )
          continue
        }
        let entries = SpotlightSection.entries(of: id, titled: titles[id], rows: rows)
        for batch in batches.add(entries, of: id, written: written) {
          try batch.record.write(to: recordURL, options: .atomic)
          try await submit(batch)
          sections += batch.sections.count
        }
      }
      if let batch = batches.finish() {
        try batch.record.write(to: recordURL, options: .atomic)
        try await submit(batch)
        sections += batch.sections.count
      }
      spotlightLog.debug("indexed \(sections) sections for Spotlight")
    } catch {
      spotlightLog.error(
        "indexing sections for Spotlight failed: \(String(describing: error), privacy: .public)")
    }
  }

  /// Makes `batch`'s items and sends them, with the client state its record was
  /// written for.
  private static func submit(_ batch: SpotlightSection.Batch) async throws {
    let making = signposter.beginInterval("Make section items")
    let items = batch.sections.map(sectionItem)
    signposter.endInterval("Make section items", making, "\(items.count) items")
    let index = CSSearchableIndex(name: SpotlightSection.domain)
    index.beginBatch()
    add(items, to: index)
    do {
      try await index.endBatch(withClientState: batch.clientState)
    } catch {
      // The next indexing starts over, as the record and the state no longer match:
      // a batch that fails every time would do so at each change to the index.
      spotlightLog.error(
        "a batch of \(items.count) sections was refused: \(String(describing: error), privacy: .public)"
      )
      throw error
    }
  }

  /// What Spotlight holds of sections, beside the full-text index it follows, and
  /// like it excluded from backups: a restored record would name sections Spotlight
  /// does not hold, which its client state catches all the same. Nil when its folder
  /// cannot be made; worked out once.
  nonisolated private static let sectionRecordURL: URL? = try? TextIndexer.defaultURL
    .deletingLastPathComponent()
    .appending(path: "spotlight-sections.json")

  /// Synchronous inside a batch, as `add` is.
  nonisolated private static func delete(domains: [String], from index: CSSearchableIndex) {
    guard !domains.isEmpty else { return }
    index.deleteSearchableItems(withDomainIdentifiers: domains, completionHandler: nil)
  }

  /// Without an expiry: a section stays as long as its document's body, and leaves
  /// Spotlight with it, by the plan, rather than when CoreSpotlight's default runs
  /// out.
  private static func sectionItem(_ entry: SpotlightSection) -> CSSearchableItem {
    let attributes = CSSearchableItemAttributeSet(contentType: .text)
    attributes.title = entry.title
    attributes.contentDescription = entry.description
    attributes.textContent = entry.text
    attributes.keywords = entry.keywords
    let item = CSSearchableItem(
      uniqueIdentifier: entry.identifier.description, domainIdentifier: entry.domainIdentifier,
      attributeSet: attributes)
    item.expirationDate = .distantFuture
    item.associateAppEntity(SectionEntity(entry))
    return item
  }

  /// No completion to wait for inside a batch: `endBatch` reports the outcome. Not
  /// the async variant, which waits for one; synchronous, so the compiler doesn't
  /// suggest it.
  nonisolated private static func add(_ items: [CSSearchableItem], to index: CSSearchableIndex) {
    index.indexSearchableItems(items, completionHandler: nil)
  }

  nonisolated private static func item(
    _ entry: SpotlightEntry, for entity: RFCEntity, expiring expiration: Date
  ) -> CSSearchableItem {
    let attributes = CSSearchableItemAttributeSet(contentType: .text)
    attributes.title = entry.title
    attributes.contentDescription = entry.description
    attributes.keywords = entry.keywords
    let item = CSSearchableItem(
      uniqueIdentifier: entry.identifier, domainIdentifier: SpotlightEntry.domain,
      attributeSet: attributes)
    item.expirationDate = expiration
    item.associateAppEntity(entity)
    return item
  }
}

/// So a section in Spotlight is the section Shortcuts and Siri act on (#178).
extension SectionEntity: IndexedEntity {}
