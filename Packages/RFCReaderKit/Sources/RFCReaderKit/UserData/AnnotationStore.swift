import Foundation
import RFCKit
import SwiftData

/// Every change to highlights, on a context (#522), on `CollectionStore`'s terms:
/// decided here and tested, each change saved before it returns, every failure
/// thrown for the App to decide about. Every change the reader makes can be undone,
/// and undoing puts back every row as it was, merged highlights included.
@MainActor
public enum AnnotationStore {
  public enum Failure: Error, Equatable {
    /// The range covers nothing an anchor holds.
    case nothingToHighlight
  }

  /// Where a change is made, and where its undo goes: the reader's undo manager, and
  /// what to do with a failure of an undo or redo, which runs long after the change
  /// returned, where nothing can catch it (#759).
  public struct Edit {
    public let context: ModelContext
    public let undoManager: UndoManager?
    public let onUndoFailure: @MainActor (any Error) -> Void

    public init(
      _ context: ModelContext, undoManager: UndoManager?,
      onUndoFailure: @escaping @MainActor (any Error) -> Void
    ) {
      self.context = context
      self.undoManager = undoManager
      self.onUndoFailure = onUndoFailure
    }
  }

  /// Highlights `range` of `document`'s model text in `color`, merging it with every
  /// highlight it overlaps (`HighlightMerge`). Answers the highlight's identifier.
  @discardableResult
  public static func highlight(
    _ range: Range<Int>, of document: DocumentID, in model: ModelText, color: HighlightColor,
    edit: Edit
  ) throws -> UUID {
    let context = edit.context
    let rows = try highlights(of: document, in: context)
    let existing = rows.compactMap { row -> HighlightMerge.Existing? in
      guard let entry = AnnotationSnapshot.HighlightEntry(row: row),
        let range = entry.current.range(in: model)
      else { return nil }
      return HighlightMerge.Existing(
        identifier: row.identifier, range: range, createdAt: row.createdAt)
    }
    let plan = HighlightMerge.plan(adding: range, to: existing)
    guard case .range(let start, let end, let quote)? = Target(covering: plan.range, in: model)
    else { throw Failure.nothingToHighlight }
    let touched = Set([plan.survivor].compactMap { $0 } + plan.absorbed)
    let before = rows.filter { touched.contains($0.identifier) }.map(HighlightValues.init)
    let row: Highlight
    if let survivor = plan.survivor, let kept = rows.first(where: { $0.identifier == survivor }) {
      row = kept
      row.startAnchor = start.anchor
      row.startOffset = start.offset
      row.endAnchor = end.anchor
      row.endOffset = end.offset
      row.setQuote(quote)
      row.clearRelocation()
      row.colorName = color.rawValue
      row.modifiedAt = .now
    } else {
      row = Highlight(document: document, start: start, end: end, quote: quote, color: color)
      context.insert(row)
    }
    for absorbed in rows where plan.absorbed.contains(absorbed.identifier) {
      context.delete(absorbed)
    }
    try context.save()
    registerUndo(
      replacing: [row.identifier], with: before, redo: [HighlightValues(row)],
      actionName: String(kit: "Highlight", locale: .interface), edit: edit)
    return row.identifier
  }

  /// A highlight's color.
  public static func setColor(_ color: HighlightColor, of identifier: UUID, edit: Edit) throws {
    let context = edit.context
    guard let row = try highlight(identifier, in: context), row.colorName != color.rawValue
    else { return }
    let before = HighlightValues(row)
    row.colorName = color.rawValue
    row.modifiedAt = .now
    try context.save()
    registerUndo(
      replacing: [identifier], with: [before], redo: [HighlightValues(row)],
      actionName: String(kit: "Change Highlight Color", locale: .interface),
      edit: edit)
  }

  /// Deletes a highlight.
  public static func delete(_ identifier: UUID, edit: Edit) throws {
    let context = edit.context
    guard let row = try highlight(identifier, in: context) else { return }
    let before = HighlightValues(row)
    context.delete(row)
    try context.save()
    registerUndo(
      replacing: [], with: [before], redo: [],
      actionName: String(kit: "Delete Highlight", locale: .interface), edit: edit)
  }

  /// Puts a highlight where the reader chose among the places its quote is (an
  /// ambiguous one, `Relocation.ambiguous`): the reader's own edit, so it is where the
  /// highlight is from now on, and it can be undone.
  public static func place(_ identifier: UUID, at target: Target, edit: Edit) throws {
    let context = edit.context
    guard let row = try highlight(identifier, in: context),
      case .range(let start, let end, let quote) = target
    else { return }
    let before = HighlightValues(row)
    row.startAnchor = start.anchor
    row.startOffset = start.offset
    row.endAnchor = end.anchor
    row.endOffset = end.offset
    row.setQuote(quote)
    row.clearRelocation()
    row.modifiedAt = .now
    try context.save()
    registerUndo(
      replacing: [identifier], with: [before], redo: [HighlightValues(row)],
      actionName: String(kit: "Place Highlight", locale: .interface), edit: edit)
  }

  /// Where relocation found a highlight (#522), in its relocated fields: never its
  /// original position, and never `modifiedAt`, since nobody edited it. A target the
  /// same as the original clears them. Nothing to undo: it is not the reader's change.
  public static func recordRelocation(
    of identifier: UUID, at target: Target, context: ModelContext
  ) throws {
    guard let row = try highlight(identifier, in: context),
      case .range(let start, let end, _) = target
    else { return }
    let original =
      Position(anchor: row.startAnchor, offset: row.startOffset) == start
      && Position(anchor: row.endAnchor, offset: row.endOffset) == end
    if original {
      guard row.relocatedStartAnchor != nil else { return }
      row.clearRelocation()
    } else {
      guard
        row.relocatedStartAnchor != start.anchor || row.relocatedStartOffset != start.offset
          || row.relocatedEndAnchor != end.anchor || row.relocatedEndOffset != end.offset
      else { return }
      row.relocatedStartAnchor = start.anchor
      row.relocatedStartOffset = start.offset
      row.relocatedEndAnchor = end.anchor
      row.relocatedEndOffset = end.offset
    }
    try context.save()
  }

  /// Every document with a highlight, for eviction (`CacheEviction.pinned`). Only the
  /// keys are fetched.
  public static func annotatedDocuments(in context: ModelContext) throws -> Set<DocumentID> {
    var descriptor = FetchDescriptor<Highlight>()
    descriptor.propertiesToFetch = [\.documentKey]
    return Set(try context.fetch(descriptor).compactMap(\.document))
  }

  // MARK: - Undo

  /// Undoing puts `before` back in place of the rows named `after`; redoing puts
  /// `redo` back in place of `before`'s. Each runs long after this returns, so what
  /// it throws goes to `onUndoFailure`, as `CollectionStore.remove`'s does.
  private static func registerUndo(
    replacing after: [UUID], with before: [HighlightValues], redo: [HighlightValues],
    actionName: String, edit: Edit
  ) {
    guard let undoManager = edit.undoManager else { return }
    undoManager.registerUndo(withTarget: edit.context) { context in
      // On the main thread, which drives the Edit menu and the shake gesture.
      MainActor.assumeIsolated {
        do {
          try replace(after, with: before, in: context)
          registerUndo(
            replacing: before.map(\.identifier), with: redo, redo: before,
            actionName: actionName, edit: edit)
        } catch {
          edit.onUndoFailure(error)
        }
      }
    }
    undoManager.setActionName(actionName)
  }

  /// Deletes the rows named `identifiers` that `values` does not hold, and makes every
  /// row in `values` as it says, inserting it where it is gone.
  private static func replace(
    _ identifiers: [UUID], with values: [HighlightValues], in context: ModelContext
  ) throws {
    let kept = Set(values.map(\.identifier))
    for identifier in identifiers where !kept.contains(identifier) {
      if let row = try highlight(identifier, in: context) { context.delete(row) }
    }
    for value in values {
      if let row = try highlight(value.identifier, in: context) {
        value.apply(to: row)
      } else {
        let row = Highlight(
          document: .rfc(0), start: value.start, end: value.end, quote: value.quote,
          color: HighlightColor(name: value.colorName))
        // Its key as it was, which may name no document this version knows.
        value.apply(to: row)
        context.insert(row)
      }
    }
    try context.save()
  }

  // MARK: - Fetching

  private static func highlights(of document: DocumentID, in context: ModelContext) throws
    -> [Highlight]
  {
    let key = document.fileStem
    return try context.fetch(
      FetchDescriptor<Highlight>(predicate: #Predicate { $0.documentKey == key }))
  }

  private static func highlight(_ identifier: UUID, in context: ModelContext) throws -> Highlight? {
    try context.fetch(
      FetchDescriptor<Highlight>(predicate: #Predicate { $0.identifier == identifier })
    ).first
  }
}

/// A highlight row's every field, kept for an undo to put back.
private struct HighlightValues {
  let identifier: UUID
  let documentKey: String
  let start: Position
  let end: Position
  let relocatedStart: Position?
  let relocatedEnd: Position?
  let quote: Quote
  let colorName: String
  let createdAt: Date
  let modifiedAt: Date

  @MainActor
  init(_ row: Highlight) {
    identifier = row.identifier
    documentKey = row.documentKey
    start = Position(anchor: row.startAnchor, offset: row.startOffset)
    end = Position(anchor: row.endAnchor, offset: row.endOffset)
    relocatedStart = row.relocatedStartAnchor.flatMap { anchor in
      row.relocatedStartOffset.map { Position(anchor: anchor, offset: $0) }
    }
    relocatedEnd = row.relocatedEndAnchor.flatMap { anchor in
      row.relocatedEndOffset.map { Position(anchor: anchor, offset: $0) }
    }
    quote = Quote(
      exact: row.quoteExact, prefix: row.quotePrefix, suffix: row.quoteSuffix,
      length: row.quoteLength, digest: row.quoteDigest)
    colorName = row.colorName
    createdAt = row.createdAt
    modifiedAt = row.modifiedAt
  }

  @MainActor
  func apply(to row: Highlight) {
    row.identifier = identifier
    row.documentKey = documentKey
    row.startAnchor = start.anchor
    row.startOffset = start.offset
    row.endAnchor = end.anchor
    row.endOffset = end.offset
    row.relocatedStartAnchor = relocatedStart?.anchor
    row.relocatedStartOffset = relocatedStart?.offset
    row.relocatedEndAnchor = relocatedEnd?.anchor
    row.relocatedEndOffset = relocatedEnd?.offset
    row.setQuote(quote)
    row.colorName = colorName
    row.createdAt = createdAt
    row.modifiedAt = modifiedAt
  }
}

extension Highlight {
  func setQuote(_ quote: Quote) {
    quoteExact = quote.exact
    quotePrefix = quote.prefix
    quoteSuffix = quote.suffix
    quoteLength = quote.length
    quoteDigest = quote.digest
  }

  func clearRelocation() {
    relocatedStartAnchor = nil
    relocatedStartOffset = nil
    relocatedEndAnchor = nil
    relocatedEndOffset = nil
  }
}
