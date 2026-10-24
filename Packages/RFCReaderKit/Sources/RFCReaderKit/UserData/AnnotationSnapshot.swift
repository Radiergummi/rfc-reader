import Foundation
import RFCKit
import SwiftData

/// Every highlight, as values (#522): what the reader draws, the Annotations tab
/// lists and eviction keeps. Built from one fetch, and `Equatable` so the app
/// publishes a new one only when it differs.
public struct AnnotationSnapshot: Equatable, Sendable {
  /// One highlight.
  public struct HighlightEntry: Equatable, Sendable, Identifiable {
    public let id: UUID
    public let document: DocumentID
    /// Where it was made.
    public let target: Target
    /// Where relocation found it since, when it moved or a finer anchor holds it.
    public let relocated: Target?
    public let color: HighlightColor
    public let createdAt: Date
    public let modifiedAt: Date

    public init(
      id: UUID, document: DocumentID, target: Target, relocated: Target? = nil,
      color: HighlightColor, createdAt: Date, modifiedAt: Date
    ) {
      self.id = id
      self.document = document
      self.target = target
      self.relocated = relocated
      self.color = color
      self.createdAt = createdAt
      self.modifiedAt = modifiedAt
    }

    /// What reads go by: the relocated position once there is one, the original
    /// before.
    public var current: Target { relocated ?? target }

    /// The quote it covered when it was made.
    public var quote: Quote {
      guard case .range(_, _, let quote) = target else {
        return Quote(exact: "", prefix: "", suffix: "")
      }
      return quote
    }
  }

  /// By document, oldest first.
  public let highlights: [DocumentID: [HighlightEntry]]

  public static let empty = AnnotationSnapshot(highlights: [])

  public init(highlights: [HighlightEntry]) {
    var byDocument: [DocumentID: [HighlightEntry]] = [:]
    for entry in highlights.sorted(by: Self.order) {
      byDocument[entry.document, default: []].append(entry)
    }
    self.highlights = byDocument
  }

  /// The documents with anything annotated, which eviction keeps (`CacheEviction`).
  public var annotatedDocuments: Set<DocumentID> { Set(highlights.keys) }

  public func highlights(of document: DocumentID) -> [HighlightEntry] {
    highlights[document] ?? []
  }

  private static func order(_ lhs: HighlightEntry, _ rhs: HighlightEntry) -> Bool {
    (lhs.createdAt, lhs.id.uuidString) < (rhs.createdAt, rhs.id.uuidString)
  }

  /// From the store's rows. A row whose key names no document is left out.
  public init(rows: [Highlight]) {
    self.init(highlights: rows.compactMap(HighlightEntry.init(row:)))
  }

  /// The store's highlights, now. A failed fetch throws rather than reading as none.
  @MainActor
  public static func fetch(in context: ModelContext) throws -> AnnotationSnapshot {
    AnnotationSnapshot(rows: try context.fetch(FetchDescriptor<Highlight>()))
  }
}

extension AnnotationSnapshot.HighlightEntry {
  init?(row: Highlight) {
    guard let document = row.document else { return nil }
    let quote = Quote(
      exact: row.quoteExact, prefix: row.quotePrefix, suffix: row.quoteSuffix,
      length: row.quoteLength, digest: row.quoteDigest)
    let target = Target.range(
      start: Position(anchor: row.startAnchor, offset: row.startOffset),
      end: Position(anchor: row.endAnchor, offset: row.endOffset), quote: quote)
    var relocated: Target?
    if let startAnchor = row.relocatedStartAnchor, let startOffset = row.relocatedStartOffset,
      let endAnchor = row.relocatedEndAnchor, let endOffset = row.relocatedEndOffset
    {
      relocated = .range(
        start: Position(anchor: startAnchor, offset: startOffset),
        end: Position(anchor: endAnchor, offset: endOffset), quote: quote)
    }
    self.init(
      id: row.identifier, document: document, target: target, relocated: relocated,
      color: HighlightColor(name: row.colorName), createdAt: row.createdAt,
      modifiedAt: row.modifiedAt)
  }
}
