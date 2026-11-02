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
  /// the app holds with when each was indexed, given the index's client state, which
  /// records what it holds the same way.
  ///
  /// The client state is written with each batch, so an indexing cut short leaves a
  /// state that says what was done, and the next one does the rest.
  public struct Plan: Sendable, Equatable {
    /// Whether the index is to be emptied first: it has no state, or one in another
    /// format, so what it holds is not known.
    public var removesEverything: Bool
    /// The documents whose items go: gone from the app, or indexed again since.
    public var removed: [DocumentID]
    /// The documents whose sections are to be indexed.
    public var indexed: [DocumentID]
    /// What Spotlight holds once `removed` are gone, which each batch adds to.
    public var kept: [DocumentID: Date]

    public init(held: [DocumentID: Date], clientState: Data?) {
      let donated = Self.documents(fromClientState: clientState)
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

    private struct State: Codable {
      var format: String
      /// File stems, with when each was indexed, in seconds since the reference date.
      var documents: [String: Double]
    }

    /// The client state recording that Spotlight holds `documents`' sections.
    public static func clientState(_ documents: [DocumentID: Date]) -> Data {
      let state = State(
        format: format,
        documents: Dictionary(
          uniqueKeysWithValues: documents.map {
            ($0.key.fileStem, $0.value.timeIntervalSinceReferenceDate)
          }))
      // Encoding a string-keyed dictionary of numbers cannot fail.
      return (try? JSONEncoder().encode(state)) ?? Data()
    }

    /// The documents `clientState` records, or nil when it records none in this
    /// format.
    static func documents(fromClientState data: Data?) -> [DocumentID: Date]? {
      guard let data, let state = try? JSONDecoder().decode(State.self, from: data),
        state.format == format
      else { return nil }
      var documents: [DocumentID: Date] = [:]
      for (stem, seconds) in state.documents {
        guard let id = DocumentID(fileStem: stem) else { continue }
        documents[id] = Date(timeIntervalSinceReferenceDate: seconds)
      }
      return documents
    }
  }
}
