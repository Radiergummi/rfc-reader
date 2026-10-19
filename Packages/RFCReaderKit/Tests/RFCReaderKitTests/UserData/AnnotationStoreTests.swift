import Foundation
import RFCKit
import SwiftData
import Testing

@testable import RFCReaderKit

/// Making, merging, recoloring and deleting highlights, and undoing each (#522).
@Suite("Annotation store")
@MainActor
struct AnnotationStoreTests {
  private let container: ModelContainer
  private var context: ModelContext { container.mainContext }
  private let model: ModelText
  private let text: String

  init() throws {
    container = try UserData.container(
      configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    model = ModelText(
      Fixtures.document(
        .paragraph(Paragraph(text: "The quick brown fox jumps over the lazy dog.", anchor: "p-1"))
      ))
    text = model.text(in: 0..<model.length)
  }

  private func range(of needle: String) throws -> Range<Int> {
    let found = (text as NSString).range(of: needle)
    try #require(found.location != NSNotFound)
    return found.location..<NSMaxRange(found)
  }

  private func highlight(
    _ needle: String, color: HighlightColor = .yellow, undoManager: UndoManager? = nil
  ) throws -> UUID {
    try AnnotationStore.highlight(
      try range(of: needle), of: .rfc(9110), in: model, color: color,
      edit: edit(undoManager))
  }

  private func edit(_ undoManager: UndoManager?) -> AnnotationStore.Edit {
    AnnotationStore.Edit(context, undoManager: undoManager, onUndoFailure: { Issue.record($0) })
  }

  private func snapshot() throws -> [AnnotationSnapshot.HighlightEntry] {
    try AnnotationSnapshot.fetch(in: context).highlights(of: .rfc(9110))
  }

  private func covered(_ entry: AnnotationSnapshot.HighlightEntry) -> String? {
    entry.current.range(in: model).map { model.text(in: $0) }
  }

  @Test func `a highlight keeps its positions, quote and color`() throws {
    let identifier = try highlight("brown fox", color: .green)
    let entries = try snapshot()
    #expect(entries.map(\.id) == [identifier])
    #expect(entries.first.map(covered) == "brown fox")
    #expect(entries.first?.color == .green)
    #expect(entries.first?.quote.exact == "brown fox")
  }

  @Test func `an overlapping highlight merges, the oldest surviving in the new color`() throws {
    let first = try highlight("quick brown")
    _ = try highlight("lazy dog")
    let bridging = try highlight("brown fox jumps over the lazy", color: .blue)
    #expect(bridging == first)
    let entries = try snapshot()
    #expect(entries.count == 1)
    #expect(entries.first.map(covered) == "quick brown fox jumps over the lazy dog")
    #expect(entries.first?.color == .blue)
  }

  @Test func `a highlight drawn nowhere is not merged into a new one`() throws {
    let lost = try highlight("brown fox")
    // Its quote is gone from where it was: detached, drawn nowhere.
    let row = try #require(try context.fetch(FetchDescriptor<Highlight>()).first)
    row.quoteExact = "nowhere in the text"
    try context.save()
    _ = try highlight("quick brown")
    #expect(try snapshot().count == 2)
    #expect(try snapshot().contains { $0.id == lost })
  }

  @Test func `a highlight whose relocation no longer holds merges where it was made`() throws {
    // Two paragraphs alike, so the quote searched for is in both, with its context.
    let filler = "Each paragraph says the same thing here."
    let sentence = "\(filler) The quick brown fox jumps over the lazy dog. \(filler)"
    let model = ModelText(
      Fixtures.document(
        .paragraph(Paragraph(text: sentence, anchor: "p-1")),
        .paragraph(Paragraph(text: sentence, anchor: "p-2"))))
    let text = model.text(in: 0..<model.length) as NSString
    func range(_ needle: String) -> Range<Int> {
      let found = text.range(of: needle)
      return found.location..<NSMaxRange(found)
    }
    let first = try AnnotationStore.highlight(
      range("brown fox"), of: .rfc(9110), in: model, color: .yellow, edit: edit(nil))
    // Relocated under an anchor this text no longer has: placement draws it where it
    // was made, so a highlight over it merges with it there.
    let row = try #require(try context.fetch(FetchDescriptor<Highlight>()).first)
    row.relocatedStartAnchor = "gone"
    row.relocatedStartOffset = row.startOffset
    row.relocatedEndAnchor = "gone"
    row.relocatedEndOffset = row.endOffset
    try context.save()
    let merged = try AnnotationStore.highlight(
      range("quick brown"), of: .rfc(9110), in: model, color: .yellow, edit: edit(nil))
    #expect(merged == first)
    #expect(try snapshot().count == 1)
  }

  @Test func `a highlight that only touches another is not merged`() throws {
    _ = try highlight("quick")
    _ = try highlight(" brown")
    #expect(try snapshot().count == 2)
  }

  @Test func `undoing a merge puts every highlight back, and redoing merges again`() throws {
    let undoManager = UndoManager()
    undoManager.groupsByEvent = false
    for needle in ["quick brown", "lazy dog"] {
      undoManager.beginUndoGrouping()
      _ = try highlight(needle, undoManager: undoManager)
      undoManager.endUndoGrouping()
    }
    undoManager.beginUndoGrouping()
    _ = try highlight("brown fox jumps over the lazy", color: .pink, undoManager: undoManager)
    undoManager.endUndoGrouping()
    #expect(try snapshot().count == 1)
    undoManager.undo()
    #expect(try snapshot().compactMap(covered).sorted() == ["lazy dog", "quick brown"])
    #expect(try snapshot().allSatisfy { $0.color == .yellow })
    undoManager.redo()
    #expect(try snapshot().compactMap(covered) == ["quick brown fox jumps over the lazy dog"])
  }

  @Test func `a color change and a deletion are undone`() throws {
    let undoManager = UndoManager()
    undoManager.groupsByEvent = false
    let identifier = try highlight("brown fox")
    undoManager.beginUndoGrouping()
    try AnnotationStore.setColor(
      .purple, of: identifier, edit: edit(undoManager))
    undoManager.endUndoGrouping()
    #expect(try snapshot().first?.color == .purple)
    undoManager.beginUndoGrouping()
    try AnnotationStore.delete(
      identifier, edit: edit(undoManager))
    undoManager.endUndoGrouping()
    #expect(try snapshot().isEmpty)
    undoManager.undo()
    #expect(try snapshot().map(\.id) == [identifier])
    undoManager.undo()
    #expect(try snapshot().first?.color == .yellow)
  }

  @Test func `a relocation is kept apart from the original, and is no edit`() throws {
    let identifier = try highlight("brown fox")
    let before = try #require(try snapshot().first)
    let moved = try #require(Target(covering: try range(of: "lazy dog"), in: model))
    try AnnotationStore.recordRelocation(of: identifier, at: moved, context: context)
    let after = try #require(try snapshot().first)
    #expect(after.target == before.target)
    #expect(after.relocated != nil)
    #expect(covered(after) == "lazy dog")
    #expect(after.modifiedAt == before.modifiedAt)
    // Back where it was made: the relocated fields go.
    try AnnotationStore.recordRelocation(of: identifier, at: before.target, context: context)
    #expect(try snapshot().first?.relocated == nil)
  }

  @Test func `a document with a highlight is annotated`() throws {
    _ = try highlight("fox")
    #expect(try AnnotationStore.annotatedDocuments(in: context) == [.rfc(9110)])
  }

  @Test func `duplicate highlight rows are merged, the latest edit kept`() throws {
    let identifier = try highlight("fox")
    let row = try #require(try context.fetch(FetchDescriptor<Highlight>()).first)
    let copy = Highlight(
      document: .rfc(9110), start: Position(anchor: row.startAnchor, offset: row.startOffset),
      end: Position(anchor: row.endAnchor, offset: row.endOffset),
      quote: Quote(exact: "fox", prefix: "", suffix: ""), color: .blue)
    copy.identifier = identifier
    copy.modifiedAt = row.modifiedAt.addingTimeInterval(10)
    context.insert(copy)
    try context.save()
    try UserData.deduplicate(context)
    #expect(try snapshot().map(\.color) == [.blue])
  }
}

extension AnnotationStoreTests {
  @Test func `an ambiguous highlight is placed where the reader chooses, undoably`() throws {
    let undoManager = UndoManager()
    undoManager.groupsByEvent = false
    let identifier = try highlight("brown fox")
    let chosen = try #require(Target(covering: try range(of: "lazy dog"), in: model))
    undoManager.beginUndoGrouping()
    try AnnotationStore.place(
      identifier, at: chosen, edit: edit(undoManager))
    undoManager.endUndoGrouping()
    #expect(try snapshot().first.map(covered) == "lazy dog")
    undoManager.undo()
    #expect(try snapshot().first.map(covered) == "brown fox")
  }
}

// MARK: - Notes (#523)

extension AnnotationStoreTests {
  private func notes() throws -> [AnnotationSnapshot.NoteEntry] {
    try AnnotationSnapshot.fetch(in: context).notes(of: .rfc(9110))
  }

  private func note(_ body: String, on owner: NoteOwner) throws -> UUID {
    let identifier = UUID()
    try AnnotationStore.saveNote(
      identifier, on: owner, of: .rfc(9110), body: body, context: context)
    return identifier
  }

  @Test func `a note is made on its highlight with its text, and keeps where it was`() throws {
    let highlight = try highlight("brown fox")
    let identifier = try note("*Look* here.", on: .highlight(highlight))
    let entry = try #require(try notes().first)
    #expect(entry.id == identifier)
    #expect(entry.highlight == highlight)
    #expect(entry.body == "*Look* here.")
    #expect(entry.target.flatMap { $0.range(in: model) }.map { model.text(in: $0) } == "brown fox")
  }

  @Test func `a note is made only once it has text, and goes when its text does`() throws {
    let identifier = UUID()
    try AnnotationStore.saveNote(
      identifier, on: .target(.section("p-1")), of: .rfc(9110), body: "  ", context: context)
    #expect(try notes().isEmpty)
    try AnnotationStore.saveNote(
      identifier, on: .target(.section("p-1")), of: .rfc(9110), body: "Text", context: context)
    #expect(try notes().map(\.target) == [.section("p-1")])
    try AnnotationStore.saveNote(
      identifier, on: .target(.section("p-1")), of: .rfc(9110), body: "", context: context)
    #expect(try notes().isEmpty)
  }

  @Test func `editing a note changes its text and when it was changed`() throws {
    let identifier = try note("First", on: .target(.section("p-1")))
    let made = try #require(try notes().first)
    try AnnotationStore.saveNote(
      identifier, on: .target(.section("p-1")), of: .rfc(9110), body: "Second", context: context)
    let edited = try #require(try notes().first)
    #expect(edited.body == "Second")
    #expect(edited.createdAt == made.createdAt)
    #expect(edited.modifiedAt >= made.modifiedAt)
  }

  @Test func `a merge puts the notes of every highlight absorbed on the survivor, undoably`()
    throws
  {
    let undoManager = UndoManager()
    undoManager.groupsByEvent = false
    let first = try highlight("quick brown")
    let second = try highlight("lazy dog")
    _ = try note("on the first", on: .highlight(first))
    let moved = try note("on the second", on: .highlight(second))
    undoManager.beginUndoGrouping()
    let merged = try highlight("brown fox jumps over the lazy", undoManager: undoManager)
    undoManager.endUndoGrouping()
    #expect(merged == first)
    #expect(Set(try notes().map(\.highlight)) == [first])
    #expect(try notes().count == 2)
    undoManager.undo()
    #expect(try notes().first { $0.id == moved }?.highlight == second)
    undoManager.redo()
    #expect(try notes().first { $0.id == moved }?.highlight == first)
  }

  @Test func `deleting a highlight deletes its notes, and undoing brings both back`() throws {
    let undoManager = UndoManager()
    undoManager.groupsByEvent = false
    let highlight = try highlight("brown fox")
    let identifier = try note("A thought.", on: .highlight(highlight))
    let other = try note("Elsewhere.", on: .target(.section("p-1")))
    undoManager.beginUndoGrouping()
    try AnnotationStore.delete(highlight, edit: edit(undoManager))
    undoManager.endUndoGrouping()
    #expect(try snapshot().isEmpty)
    #expect(try notes().map(\.id) == [other])
    undoManager.undo()
    #expect(try snapshot().map(\.id) == [highlight])
    #expect(Set(try notes().map(\.id)) == [identifier, other])
    #expect(try notes().first { $0.id == identifier }?.body == "A thought.")
  }

  @Test func `undoing a highlight takes the note made on it since, and redoing brings both`()
    throws
  {
    let undoManager = UndoManager()
    undoManager.groupsByEvent = false
    undoManager.beginUndoGrouping()
    let highlight = try highlight("brown fox", undoManager: undoManager)
    undoManager.endUndoGrouping()
    let identifier = try note("Added with it.", on: .highlight(highlight))
    undoManager.undo()
    #expect(try snapshot().isEmpty)
    #expect(try notes().isEmpty)
    undoManager.redo()
    #expect(try snapshot().map(\.id) == [highlight])
    #expect(try notes().map(\.id) == [identifier])
    #expect(try notes().first?.highlight == highlight)
  }

  @Test func `a deleted note is undone`() throws {
    let undoManager = UndoManager()
    undoManager.groupsByEvent = false
    let block = try #require(Target(covering: try range(of: "lazy dog"), in: model))
    let identifier = try note("On the dog.", on: .target(block))
    undoManager.beginUndoGrouping()
    try AnnotationStore.deleteNote(identifier, edit: edit(undoManager))
    undoManager.endUndoGrouping()
    #expect(try notes().isEmpty)
    undoManager.undo()
    #expect(try notes().first?.target == block)
  }

  @Test func `a note is put on another highlight without being edited`() throws {
    let gone = UUID()
    let identifier = try note("Orphaned.", on: .highlight(gone))
    let before = try #require(try notes().first)
    let survivor = try highlight("fox")
    try AnnotationStore.repointNote(identifier, to: survivor, context: context)
    let after = try #require(try notes().first)
    #expect(after.highlight == survivor)
    #expect(after.modifiedAt == before.modifiedAt)
  }

  @Test func `a document with only a note is annotated`() throws {
    _ = try note("Here.", on: .target(.section("p-1")))
    #expect(try AnnotationStore.annotatedDocuments(in: context) == [.rfc(9110)])
    #expect(try AnnotationSnapshot.fetch(in: context).annotatedDocuments == [.rfc(9110)])
  }

  @Test func `duplicate note rows are merged, the latest edit kept`() throws {
    let identifier = try note("Old", on: .target(.section("p-1")))
    let copy = Note(identifier: identifier, document: .rfc(9110), body: "New")
    copy.sectionAnchor = "p-1"
    copy.modifiedAt = .now.addingTimeInterval(10)
    context.insert(copy)
    try context.save()
    try UserData.deduplicate(context)
    #expect(try notes().map(\.body) == ["New"])
  }
}
