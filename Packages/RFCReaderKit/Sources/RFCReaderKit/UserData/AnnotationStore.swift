import Foundation
import RFCKit
import SwiftData

/// Every change to highlights (#522) and notes (#523), on a context, on
/// `CollectionStore`'s terms:
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
    // Where each is now, as the reader draws it: one drawn nowhere, ambiguous or
    // detached, is not merged with what overlaps its stale position, and one that
    // moved is merged where it went.
    let relocator = Relocator(model)
    let existing = rows.compactMap { row -> HighlightMerge.Existing? in
      guard let entry = AnnotationSnapshot.HighlightEntry(row: row),
        let range = relocator.relocate(entry).target?.range(in: model)
      else { return nil }
      return HighlightMerge.Existing(
        identifier: row.identifier, range: range, createdAt: row.createdAt)
    }
    let plan = HighlightMerge.plan(adding: range, to: existing)
    guard case .range(let start, let end, let quote)? = Target(covering: plan.range, in: model)
    else { throw Failure.nothingToHighlight }
    let touched = Set([plan.survivor].compactMap { $0 } + plan.absorbed)
    // The notes of every highlight absorbed go to the one that survives, as several
    // notes may share a highlight: they are not joined.
    let absorbedNotes = try notes(onHighlights: Set(plan.absorbed), of: document, in: context)
    let before = Rows(
      highlights: rows.filter { touched.contains($0.identifier) }.map(HighlightValues.init),
      notes: absorbedNotes.map(NoteValues.init))
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
    for note in absorbedNotes { note.highlightIdentifier = row.identifier }
    try context.save()
    registerUndo(
      replacing: Identifiers(highlights: [row.identifier], notes: absorbedNotes.map(\.identifier)),
      with: before,
      redo: Rows(highlights: [HighlightValues(row)], notes: absorbedNotes.map(NoteValues.init)),
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
      replacing: Identifiers(highlights: [identifier]), with: Rows(highlights: [before]),
      redo: Rows(highlights: [HighlightValues(row)]),
      actionName: String(kit: "Change Highlight Color", locale: .interface),
      edit: edit)
  }

  /// Deletes a highlight, and the notes on it, which the reader was asked about.
  public static func delete(_ identifier: UUID, edit: Edit) throws {
    let context = edit.context
    guard let row = try highlight(identifier, in: context) else { return }
    let notes = try notes(
      onHighlights: [identifier], ofKey: row.documentKey, in: context)
    let before = Rows(highlights: [HighlightValues(row)], notes: notes.map(NoteValues.init))
    context.delete(row)
    for note in notes { context.delete(note) }
    try context.save()
    registerUndo(
      replacing: Identifiers(), with: before, redo: Rows(),
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
      replacing: Identifiers(highlights: [identifier]), with: Rows(highlights: [before]),
      redo: Rows(highlights: [HighlightValues(row)]),
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

  /// Every document with a highlight or a note, for eviction (`CacheEviction.pinned`).
  /// Only the keys are fetched.
  public static func annotatedDocuments(in context: ModelContext) throws -> Set<DocumentID> {
    var highlights = FetchDescriptor<Highlight>()
    highlights.propertiesToFetch = [\.documentKey]
    var notes = FetchDescriptor<Note>()
    notes.propertiesToFetch = [\.documentKey]
    return Set(try context.fetch(highlights).compactMap(\.document))
      .union(try context.fetch(notes).compactMap(\.document))
  }

  // MARK: - Notes

  /// Saves a note's body (#523): the note `identifier`, made on `owner` the first time
  /// it has text, and deleted when its text is gone, so a note left empty is never
  /// kept. The editor's own undo covers its text; nothing is registered here.
  public static func saveNote(
    _ identifier: UUID, on owner: NoteOwner, of document: DocumentID, body: String,
    context: ModelContext
  ) throws {
    let existing = try note(identifier, in: context)
    guard !NoteBody(markdown: body).isEmpty else {
      if let existing {
        context.delete(existing)
        try context.save()
      }
      return
    }
    if let existing {
      guard existing.body != body else { return }
      existing.body = body
      existing.modifiedAt = .now
    } else {
      let row = Note(identifier: identifier, document: document, body: body)
      switch owner {
      case .highlight(let highlight):
        row.highlightIdentifier = highlight
        // Where the highlight is now, kept for finding it again should it go.
        if let made = try self.highlight(highlight, in: context),
          let entry = AnnotationSnapshot.HighlightEntry(row: made)
        {
          row.setTarget(entry.current)
        }
      case .target(let target):
        row.setTarget(target)
      }
      context.insert(row)
    }
    try context.save()
  }

  /// Deletes a note.
  public static func deleteNote(_ identifier: UUID, edit: Edit) throws {
    let context = edit.context
    guard let row = try note(identifier, in: context) else { return }
    let before = NoteValues(row)
    context.delete(row)
    try context.save()
    registerUndo(
      replacing: Identifiers(), with: Rows(notes: [before]), redo: Rows(),
      actionName: String(kit: "Delete Note", locale: .interface), edit: edit)
  }

  /// Puts a note whose highlight is gone on the highlight that covers it now
  /// (`NotePlacement`). Not the reader's change: no undo, and `modifiedAt` stands.
  public static func repointNote(_ identifier: UUID, to highlight: UUID, context: ModelContext)
    throws
  {
    guard let row = try note(identifier, in: context), row.highlightIdentifier != highlight
    else { return }
    row.highlightIdentifier = highlight
    try context.save()
  }

  /// Where relocation found a note's own range, as `recordRelocation(of:at:context:)`
  /// records a highlight's.
  public static func recordNoteRelocation(
    of identifier: UUID, at target: Target, context: ModelContext
  ) throws {
    guard let row = try note(identifier, in: context), row.highlightIdentifier == nil,
      case .range(let start, let end, _) = target
    else { return }
    let original =
      row.startAnchor == start.anchor && row.startOffset == start.offset
      && row.endAnchor == end.anchor && row.endOffset == end.offset
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

  // MARK: - Undo

  /// Undoing puts `before` back in place of the rows named `after`; redoing puts
  /// `redo` back in place of `before`'s. Each runs long after this returns, so what
  /// it throws goes to `onUndoFailure`, as `CollectionStore.remove`'s does.
  private static func registerUndo(
    replacing after: Identifiers, with before: Rows, redo: Rows, actionName: String, edit: Edit
  ) {
    guard let undoManager = edit.undoManager else { return }
    let onUndoFailure = edit.onUndoFailure
    // The manager is held weakly, as `BookmarkStore`'s is: it holds this.
    undoManager.registerUndo(withTarget: edit.context) { [weak undoManager] context in
      // On the main thread, which drives the Edit menu and the shake gesture.
      MainActor.assumeIsolated {
        do {
          // A highlight taken away takes its notes, made since, with it; the redo
          // brings them back with it.
          let removed = try replace(after, with: before, in: context)
          registerUndo(
            replacing: before.identifiers,
            with: Rows(highlights: redo.highlights, notes: redo.notes + removed), redo: before,
            actionName: actionName,
            edit: Edit(context, undoManager: undoManager, onUndoFailure: onUndoFailure))
        } catch {
          onUndoFailure(error)
        }
      }
    }
    undoManager.setActionName(actionName)
  }

  /// Deletes the rows named `identifiers` that `rows` does not hold, and makes every
  /// row in `rows` as it says, inserting it where it is gone. A highlight deleted
  /// takes the notes on it that `rows` does not hold; answers them, as they were.
  @discardableResult
  private static func replace(
    _ identifiers: Identifiers, with rows: Rows, in context: ModelContext
  ) throws -> [NoteValues] {
    let keptHighlights = Set(rows.highlights.map(\.identifier))
    let keptNotes = Set(rows.notes.map(\.identifier))
    var removed: [NoteValues] = []
    for identifier in identifiers.highlights where !keptHighlights.contains(identifier) {
      guard let row = try highlight(identifier, in: context) else { continue }
      for note in try notes(onHighlights: [identifier], ofKey: row.documentKey, in: context)
      where !keptNotes.contains(note.identifier) && !identifiers.notes.contains(note.identifier) {
        removed.append(NoteValues(note))
        context.delete(note)
      }
      context.delete(row)
    }
    for identifier in identifiers.notes where !keptNotes.contains(identifier) {
      if let row = try note(identifier, in: context) { context.delete(row) }
    }
    for value in rows.highlights {
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
    for value in rows.notes {
      if let row = try note(value.identifier, in: context) {
        // Where it is, and nothing of its text: no change undone here edits a note,
        // and what it was edited to since is the editor's.
        value.applyPlace(to: row)
      } else {
        let row = Note(identifier: value.identifier, document: .rfc(0), body: value.body)
        value.apply(to: row)
        context.insert(row)
      }
    }
    try context.save()
    return removed
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

  private static func note(_ identifier: UUID, in context: ModelContext) throws -> Note? {
    try context.fetch(
      FetchDescriptor<Note>(predicate: #Predicate { $0.identifier == identifier })
    ).first
  }

  private static func notes(
    onHighlights highlights: Set<UUID>, of document: DocumentID, in context: ModelContext
  ) throws -> [Note] {
    try notes(onHighlights: highlights, ofKey: document.fileStem, in: context)
  }

  /// The notes of one document on these highlights: fetched by the document, the
  /// highlights then picked out, a predicate over an optional identifier being none
  /// SwiftData can make.
  private static func notes(
    onHighlights highlights: Set<UUID>, ofKey key: String, in context: ModelContext
  ) throws -> [Note] {
    guard !highlights.isEmpty else { return [] }
    return try context.fetch(
      FetchDescriptor<Note>(predicate: #Predicate { $0.documentKey == key })
    ).filter { note in
      note.highlightIdentifier.map(highlights.contains) ?? false
    }
  }
}

/// The rows an undo puts back.
private struct Rows {
  var highlights: [HighlightValues] = []
  var notes: [NoteValues] = []

  var identifiers: Identifiers {
    Identifiers(highlights: highlights.map(\.identifier), notes: notes.map(\.identifier))
  }
}

/// The rows an undo replaces.
private struct Identifiers {
  var highlights: [UUID] = []
  var notes: [UUID] = []
}

/// A note row's every field, kept for an undo to put back.
private struct NoteValues {
  let identifier: UUID
  let documentKey: String
  let highlightIdentifier: UUID?
  let target: Target?
  let relocated: Target?
  let body: String
  let createdAt: Date
  let modifiedAt: Date

  @MainActor
  init(_ row: Note) {
    identifier = row.identifier
    documentKey = row.documentKey
    highlightIdentifier = row.highlightIdentifier
    target = row.target
    relocated = row.relocatedTarget
    body = row.body
    createdAt = row.createdAt
    modifiedAt = row.modifiedAt
  }

  @MainActor
  func apply(to row: Note) {
    row.identifier = identifier
    row.documentKey = documentKey
    applyPlace(to: row)
    row.body = body
    row.createdAt = createdAt
    row.modifiedAt = modifiedAt
  }

  /// What it is on and where it was found, which a merge, a deletion and their undo
  /// change, and not its text or when that was written.
  @MainActor
  func applyPlace(to row: Note) {
    row.highlightIdentifier = highlightIdentifier
    row.setTarget(target)
    if case .range(let start, let end, _)? = relocated {
      row.relocatedStartAnchor = start.anchor
      row.relocatedStartOffset = start.offset
      row.relocatedEndAnchor = end.anchor
      row.relocatedEndOffset = end.offset
    }
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
