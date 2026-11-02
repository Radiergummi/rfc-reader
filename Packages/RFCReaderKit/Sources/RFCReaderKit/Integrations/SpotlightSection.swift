import CryptoKit
import Foundation
import RFCKit

/// What system search knows about a section (#178): one item per section of each
/// document the app holds a body of, from the full-text index's rows, which the app
/// turns into a `CSSearchableItem`.
///
/// Plain data, as `SpotlightEntry` is, so what is indexed is decided here, under test.
/// The abstract is left out: the RFC's own item indexes it already.
public struct SpotlightSection: Sendable, Equatable {
  /// The name of the index sections are kept in, and the root of every document's
  /// domain, so the whole set can be emptied at once.
  public static let domain = "rfc-sections"

  /// `rfc9110#section-10.2.3`: how a chosen result comes back, and its App Intents
  /// entity's identifier.
  public var identifier: SectionIdentifier
  /// `10.2.3`; nil for an unnumbered section.
  public var number: String?
  /// `10.2.3 Retry-After`.
  public var title: String
  /// `RFC 9110: HTTP Semantics`, which document the section is of.
  public var description: String
  /// The section's own text: searched, not shown.
  public var text: String
  /// The document's number as it is written, and the section's with it.
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
    let documentKeywords = ["\(id.number)", id.displayName, id.description]
    return rows.compactMap { row in
      guard row.anchor != FullTextIndex.abstractAnchor else { return nil }
      let title = [row.number, row.heading]
        .compactMap { $0 }
        .filter { !$0.isEmpty }
        .joined(separator: " ")
      guard !title.isEmpty else { return nil }
      let sectionKeywords = row.number.map { ["\(id.displayName) \($0)", "§\($0)"] } ?? []
      return SpotlightSection(
        identifier: SectionIdentifier(document: id, anchor: row.anchor), number: row.number,
        title: title, description: description, text: row.body,
        keywords: documentKeywords + sectionKeywords)
    }
  }

  /// What to change in Spotlight for it to hold the sections of `held`, the documents
  /// the app holds with when each was indexed, given the record of what it holds.
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
    /// The documents whose items go: gone from the app, or indexed again since.
    public var removed: [DocumentID]
    /// The documents whose sections are to be indexed.
    public var indexed: [DocumentID]
    /// What Spotlight holds once `removed` are gone, which each batch adds to.
    public var kept: [DocumentID: Date]

    /// `record` and `clientState` are what the last indexing wrote: the record file's
    /// contents and Spotlight's client state, either nil if there is none.
    public init(held: [DocumentID: Date], record: Data?, clientState: Data?) {
      let donated = Self.documents(fromRecord: record, clientState: clientState)
      removesEverything = donated == nil
      let recorded = donated ?? [:]
      removed = recorded.filter { held[$0.key] != $0.value }.keys.sorted()
      indexed = held.filter { recorded[$0.key] != $0.value }.keys.sorted()
      kept = recorded.filter { held[$0.key] == $0.value }
    }

    public var isEmpty: Bool {
      !removesEverything && removed.isEmpty && indexed.isEmpty
    }

    /// Changed whenever what an item carries changes, so the index is emptied and
    /// made again.
    static let format = "sections-1"

    /// The record of Spotlight holding `documents`' sections.
    public static func record(_ documents: [DocumentID: Date]) -> Data {
      let record = SpotlightSectionRecord(
        format: format,
        documents: Dictionary(
          uniqueKeysWithValues: documents.map {
            ($0.key.fileStem, $0.value.timeIntervalSinceReferenceDate)
          }))
      let encoder = JSONEncoder()
      // The same documents always make the same record, and so the same digest.
      encoder.outputFormatting = .sortedKeys
      // Encoding a string-keyed dictionary of numbers cannot fail.
      return (try? encoder.encode(record)) ?? Data()
    }

    /// The client state written with `record`: its digest.
    public static func clientState(forRecord record: Data) -> Data {
      Data(SHA256.hash(data: record))
    }

    /// The documents `record` names, or nil when there is none, it is in another
    /// format, or `clientState` was not written with it.
    static func documents(fromRecord record: Data?, clientState: Data?) -> [DocumentID: Date]? {
      guard let record, let clientState, clientState == Self.clientState(forRecord: record),
        let decoded = try? JSONDecoder().decode(SpotlightSectionRecord.self, from: record),
        decoded.format == format
      else { return nil }
      var documents: [DocumentID: Date] = [:]
      for (stem, seconds) in decoded.documents {
        guard let id = DocumentID(fileStem: stem) else { continue }
        documents[id] = Date(timeIntervalSinceReferenceDate: seconds)
      }
      return documents
    }
  }
}

/// `SpotlightSection.Plan`'s record, as it is written to its file.
private struct SpotlightSectionRecord: Codable {
  var format: String
  /// File stems, with when each was indexed, in seconds since the reference date.
  var documents: [String: Double]
}
