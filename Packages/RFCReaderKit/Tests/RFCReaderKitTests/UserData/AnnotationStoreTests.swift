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
      try range(of: needle), of: .rfc(9110), in: model, color: color, undoManager: undoManager,
      onUndoFailure: { Issue.record($0) }, context: context)
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
      .purple, of: identifier, undoManager: undoManager, onUndoFailure: { Issue.record($0) },
      context: context)
    undoManager.endUndoGrouping()
    #expect(try snapshot().first?.color == .purple)
    undoManager.beginUndoGrouping()
    try AnnotationStore.delete(
      identifier, undoManager: undoManager, onUndoFailure: { Issue.record($0) }, context: context)
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
