import CryptoKit
import Foundation
import RFCKit

/// What system search knows about a section (#178): one item per section of each
/// document the app holds a body of, from the full-text index's rows, which the app
/// turns into a `CSSearchableItem`.
///
/// Plain data, as `SpotlightEntry` is, so what is indexed is decided here, under test.
/// The abstract is left out: the RFC's own item indexes it already. So are the
/// document's number spellings, which would rank every section of it with the RFC's
/// own item for a search by number; the description names the document instead.
public struct SpotlightSection: Sendable, Equatable {
  /// The name of the index sections are kept in, and the root of every document's
  /// domain, so the whole set can be emptied at once.
  public static let domain = "rfc-sections"

  /// `rfc9110#section-10.2.3`: how a chosen result comes back, and its App Intents
  /// entity's identifier.
  public var identifier: SectionIdentifier
  /// `10.2.3` or `A`; nil for an unnumbered section.
  public var number: String?
  /// `10.2.3` or `Appendix A`: the number as the heading names it.
  public var label: String?
  /// `10.2.3 Retry-After`, `Appendix A Collected ABNF`: the item's title.
  public var title: String
  /// `10.2.3. Retry-After`: the section as the reader and its App Intents entity
  /// name it (`Section.displayTitle`), so one identifier has one title.
  public var displayTitle: String
  /// `RFC 9110: HTTP Semantics`, which document the section is of.
  public var description: String
  /// The section's own text: searched, not shown.
  public var text: String
  /// The section's number as it is written: `Appendix A`, `§A`; `10.2.3`, `§10.2.3`.
  public var keywords: [String]

  /// The domain of the document's items, deleted as one when it leaves the app.
  public var domainIdentifier: String { Self.domain(of: identifier.document) }

  public static func domain(of id: DocumentID) -> String {
    "\(domain).\(id.fileStem)"
  }

  /// The entries for document `id`'s indexed `rows`, described by its `title`, or by
  /// its designation where the index has none.
  public static func entries(
    of id: DocumentID, titled title: String?, rows: [FullTextIndex.Row]
  ) -> [SpotlightSection] {
    let description = title.map { "\(id.displayName): \($0)" } ?? id.displayName
    return rows.compactMap { row in
      guard row.anchor != FullTextIndex.abstractAnchor else { return nil }
      let title = [row.label, row.heading]
        .compactMap { $0 }
        .filter { !$0.isEmpty }
        .joined(separator: " ")
      guard !title.isEmpty else { return nil }
      var keywords: [String] = []
      if let label = row.label {
        keywords.append(label)
      }
      if let number = row.number {
        keywords.append("§\(number)")
      }
      return SpotlightSection(
        identifier: SectionIdentifier(document: id, anchor: row.anchor), number: row.number,
        label: row.label,
        title: title, displayTitle: row.title.isEmpty ? title : row.title,
        description: description, text: row.body, keywords: keywords)
    }
  }

  /// What to change in Spotlight for it to hold the sections of `held`: the documents
  /// the app holds, each with when its body was written, as the full-text index
  /// records it. The comparison is with the record of what Spotlight holds.
  ///
  /// The record is the app's, in a file, written before each batch: Spotlight keeps a
  /// client state of no more than about a kilobyte, too little for a cache's worth of
  /// documents. The client state written with the batch is the record's digest, so a
  /// record whose batch failed does not match it, and Spotlight is made again from
  /// nothing rather than trusted to hold what the record says. An indexing cut short
  /// between batches leaves a record that says what was done, and the next one does
  /// the rest.
  public struct Plan: Sendable, Equatable {
    /// Whether the index is to be emptied first: what it holds is not known.
    public var removesEverything: Bool
    /// The documents whose items go: gone from the app, written again since, or
    /// indexed only in part.
    public var removed: [DocumentID]
    /// The documents whose sections are to be indexed.
    public var indexed: [DocumentID]
    /// What Spotlight holds once `removed` are gone, which each batch adds to.
    public var kept: [DocumentID: Date]

    /// `record` and `clientState` are what the last indexing wrote: the record file's
    /// contents and Spotlight's client state, either nil if there is none.
    public init(held: [DocumentID: Date], record: Data?, clientState: Data?) {
      let recorded = Self.recorded(record, clientState: clientState)
      removesEverything = recorded == nil
      let documents = recorded?.documents ?? [:]
      let partial = recorded?.partial ?? []
      removed = Set(documents.filter { held[$0.key] != $0.value }.keys)
        .union(partial)
        .sorted()
      indexed = held.filter { documents[$0.key] != $0.value }.keys.sorted()
      kept = documents.filter { held[$0.key] == $0.value }
    }

    public var isEmpty: Bool {
      !removesEverything && removed.isEmpty && indexed.isEmpty
    }

    /// Whether Spotlight has anything to delete before the new sections go in.
    public var deletes: Bool {
      removesEverything || !removed.isEmpty
    }

    /// Changed whenever what an item carries changes, so the index is emptied and
    /// made again; and with the full-text index's version, whose change empties that
    /// index and indexes its documents again under bodies whose dates are as they were.
    static let format = "sections-2.fts-\(FullTextIndex.version)"

    /// The record of Spotlight holding `documents`' sections, and some of `partial`'s.
    public static func record(
      _ documents: [DocumentID: Date], partial: Set<DocumentID> = []
    ) -> Data {
      record(documents, partial: partial, format: format)
    }

    static func record(
      _ documents: [DocumentID: Date], partial: Set<DocumentID>, format: String
    ) -> Data {
      let record = SpotlightSectionRecord(
        format: format,
        documents: Dictionary(
          uniqueKeysWithValues: documents.map {
            ($0.key.fileStem, $0.value.timeIntervalSinceReferenceDate)
          }),
        partial: partial.map(\.fileStem).sorted())
      let encoder = JSONEncoder()
      // The same documents always make the same record, and so the same digest.
      encoder.outputFormatting = .sortedKeys
      // Encoding strings and numbers cannot fail.
      return (try? encoder.encode(record)) ?? Data()
    }

    /// The client state written with `record`: its digest.
    public static func clientState(forRecord record: Data) -> Data {
      Data(SHA256.hash(data: record))
    }

    /// What `record` says Spotlight holds, or nil when there is no record, it is in
    /// another format, or `clientState` was not written with it.
    private static func recorded(
      _ record: Data?, clientState: Data?
    ) -> (documents: [DocumentID: Date], partial: Set<DocumentID>)? {
      guard let record, let clientState, clientState == Self.clientState(forRecord: record),
        let decoded = try? JSONDecoder().decode(SpotlightSectionRecord.self, from: record),
        decoded.format == format
      else { return nil }
      var documents: [DocumentID: Date] = [:]
      for (stem, seconds) in decoded.documents {
        guard let id = DocumentID(fileStem: stem) else { continue }
        documents[id] = Date(timeIntervalSinceReferenceDate: seconds)
      }
      return (documents, Set(decoded.partial.compactMap(DocumentID.init(fileStem:))))
    }
  }

  /// One batch of `Batches`.
  public struct Batch: Sendable, Equatable {
    public var sections: [SpotlightSection]
    /// To be written to the record's file before the batch is sent.
    public var record: Data
    /// To be written with the batch.
    public var clientState: Data
  }

  /// A plan's sections cut into batches for Spotlight, each with the record to write
  /// before it and the client state to write with it.
  ///
  /// A batch holds at most `size` sections, a large document's cut across batches as
  /// a small one's are put together. A document is recorded as held once its last
  /// section is in a batch; one cut across batches is recorded as partial until then,
  /// so an indexing stopped between them deletes what was indexed of it and starts it
  /// again.
  public struct Batches: Sendable {
    public static let size = 500

    private let size: Int
    private var kept: [DocumentID: Date]
    private var pending: [SpotlightSection] = []
    /// The documents all of whose sections are in `pending` or sent, with their dates.
    private var complete: [DocumentID: Date] = [:]

    /// Batches for documents to be added to `kept`, what Spotlight holds already.
    public init(kept: [DocumentID: Date], size: Int = Batches.size) {
      self.kept = kept
      self.size = size
    }

    /// The record of what Spotlight holds before any batch: what the deletions leave.
    public var initialRecord: Data { Plan.record(kept) }

    /// Adds document `id`'s sections, its body written at `written`; returns the
    /// batches now full.
    public mutating func add(
      _ sections: [SpotlightSection], of id: DocumentID, written: Date
    ) -> [Batch] {
      var batches: [Batch] = []
      var remaining = sections[...]
      while pending.count + remaining.count >= size, !remaining.isEmpty {
        let taken = remaining.prefix(size - pending.count)
        remaining = remaining.dropFirst(taken.count)
        pending += taken
        if remaining.isEmpty {
          complete[id] = written
          batches.append(flush(cutting: nil))
        } else {
          batches.append(flush(cutting: id))
        }
      }
      if !remaining.isEmpty || sections.isEmpty {
        pending += remaining
        complete[id] = written
      }
      return batches
    }

    /// The last batch, of whatever is left; nil when nothing is.
    public mutating func finish() -> Batch? {
      guard !pending.isEmpty || !complete.isEmpty else { return nil }
      return flush(cutting: nil)
    }

    private mutating func flush(cutting id: DocumentID?) -> Batch {
      kept.merge(complete) { _, new in new }
      complete = [:]
      let record = Plan.record(kept, partial: id.map { [$0] } ?? [])
      let batch = Batch(
        sections: pending, record: record, clientState: Plan.clientState(forRecord: record))
      pending = []
      return batch
    }
  }
}

/// `SpotlightSection.Plan`'s record, as it is written to its file.
private struct SpotlightSectionRecord: Codable {
  var format: String
  /// File stems, with when each one's body was written, in seconds since the
  /// reference date.
  var documents: [String: Double]
  /// File stems of documents some of whose sections are indexed.
  var partial: [String]
}
