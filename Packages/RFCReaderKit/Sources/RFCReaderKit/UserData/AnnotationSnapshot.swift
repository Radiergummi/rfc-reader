import Foundation
import RFCKit
import SwiftData

/// Every highlight (#522) and note (#523), as values: what the reader draws, the
/// Annotations tab lists and eviction keeps. Built from one fetch, and `Equatable` so the app
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

  /// One note.
  public struct NoteEntry: Equatable, Sendable, Identifiable {
    public let id: UUID
    public let document: DocumentID
    /// The highlight it is on, or nil for a note on a target of its own.
    public let highlight: UUID?
    /// Its own target, a section or a range; for a note on a highlight, the
    /// highlight's as it was when the note was made, which finds the highlight that
    /// covers it should its own be gone.
    public let target: Target?
    /// Where relocation found its own target since.
    public let relocated: Target?
    /// Restricted CommonMark (`NoteBody`).
    public let body: String
    public let createdAt: Date
    public let modifiedAt: Date

    public init(
      id: UUID, document: DocumentID, highlight: UUID?, target: Target?,
      relocated: Target? = nil, body: String, createdAt: Date, modifiedAt: Date
    ) {
      self.id = id
      self.document = document
      self.highlight = highlight
      self.target = target
      self.relocated = relocated
      self.body = body
      self.createdAt = createdAt
      self.modifiedAt = modifiedAt
    }

    /// What reads go by: the relocated target once there is one.
    public var current: Target? { relocated ?? target }
  }

  /// By document, oldest first.
  public let highlights: [DocumentID: [HighlightEntry]]
  public let notes: [DocumentID: [NoteEntry]]

  public static let empty = AnnotationSnapshot(highlights: [])

  public init(highlights: [HighlightEntry], notes: [NoteEntry] = []) {
    self.highlights = Dictionary(
      grouping: highlights.sorted { Self.order(($0.createdAt, $0.id), ($1.createdAt, $1.id)) },
      by: \.document)
    self.notes = Dictionary(
      grouping: notes.sorted { Self.order(($0.createdAt, $0.id), ($1.createdAt, $1.id)) },
      by: \.document)
  }

  /// The documents with anything annotated, which eviction keeps (`CacheEviction`).
  public var annotatedDocuments: Set<DocumentID> { Set(highlights.keys).union(notes.keys) }

  public func highlights(of document: DocumentID) -> [HighlightEntry] {
    highlights[document] ?? []
  }

  public func notes(of document: DocumentID) -> [NoteEntry] {
    notes[document] ?? []
  }

  private static func order(_ lhs: (Date, UUID), _ rhs: (Date, UUID)) -> Bool {
    (lhs.0, lhs.1.uuidString) < (rhs.0, rhs.1.uuidString)
  }

  /// From the store's rows. A row whose key names no document is left out.
  public init(rows: [Highlight], notes: [Note] = []) {
    self.init(
      highlights: rows.compactMap(HighlightEntry.init(row:)),
      notes: notes.compactMap(NoteEntry.init(row:)))
  }

  /// The store's highlights and notes, now. A failed fetch throws rather than
  /// reading as none.
  @MainActor
  public static func fetch(in context: ModelContext) throws -> AnnotationSnapshot {
    AnnotationSnapshot(
      rows: try context.fetch(FetchDescriptor<Highlight>()),
      notes: try context.fetch(FetchDescriptor<Note>()))
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

extension AnnotationSnapshot.NoteEntry {
  init?(row: Note) {
    guard let document = row.document else { return nil }
    self.init(
      id: row.identifier, document: document, highlight: row.highlightIdentifier,
      target: row.target, relocated: row.relocatedTarget, body: row.body,
      createdAt: row.createdAt, modifiedAt: row.modifiedAt)
  }
}

extension Note {
  /// Its own target: the section, or the range with its quote. Nil when neither is
  /// written, as for a row from a version that wrote neither.
  var target: Target? {
    if let sectionAnchor { return .section(sectionAnchor) }
    guard let startAnchor, let startOffset, let endAnchor, let endOffset else { return nil }
    return .range(
      start: Position(anchor: startAnchor, offset: startOffset),
      end: Position(anchor: endAnchor, offset: endOffset), quote: quote)
  }

  var relocatedTarget: Target? {
    guard let startAnchor = relocatedStartAnchor, let startOffset = relocatedStartOffset,
      let endAnchor = relocatedEndAnchor, let endOffset = relocatedEndOffset
    else { return nil }
    return .range(
      start: Position(anchor: startAnchor, offset: startOffset),
      end: Position(anchor: endAnchor, offset: endOffset), quote: quote)
  }

  var quote: Quote {
    Quote(
      exact: quoteExact ?? "", prefix: quotePrefix ?? "", suffix: quoteSuffix ?? "",
      length: quoteLength, digest: quoteDigest)
  }

  /// Writes `target` as its own, clearing any relocation.
  func setTarget(_ target: Target?) {
    sectionAnchor = nil
    startAnchor = nil
    startOffset = nil
    endAnchor = nil
    endOffset = nil
    quoteExact = nil
    quotePrefix = nil
    quoteSuffix = nil
    quoteLength = nil
    quoteDigest = nil
    clearRelocation()
    switch target {
    case .section(let anchor):
      sectionAnchor = anchor
    case .range(let start, let end, let quote):
      startAnchor = start.anchor
      startOffset = start.offset
      endAnchor = end.anchor
      endOffset = end.offset
      quoteExact = quote.exact
      quotePrefix = quote.prefix
      quoteSuffix = quote.suffix
      quoteLength = quote.length
      quoteDigest = quote.digest
    case nil:
      break
    }
  }

  func clearRelocation() {
    relocatedStartAnchor = nil
    relocatedStartOffset = nil
    relocatedEndAnchor = nil
    relocatedEndOffset = nil
  }
}
