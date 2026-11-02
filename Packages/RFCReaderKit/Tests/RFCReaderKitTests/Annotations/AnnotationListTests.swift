import Foundation
import RFCKit
import Testing

@testable import RFCReaderKit

@Suite("Annotations: the Annotations tab's list")
struct AnnotationListTests {
  private func entry(_ quote: String, age: TimeInterval) -> AnnotationSnapshot.HighlightEntry {
    AnnotationSnapshot.HighlightEntry(
      id: UUID(), document: .rfc(9110),
      target: .range(
        start: Position(anchor: "p-\(quote)", offset: 0),
        end: Position(anchor: "p-\(quote)", offset: 1),
        quote: Quote(exact: quote, prefix: "", suffix: "")),
      color: .yellow, createdAt: Date(timeIntervalSince1970: age), modifiedAt: .now)
  }

  @Test func `placed highlights come in document order, the rest after, marked`() {
    let late = entry("late", age: 1)
    let early = entry("early", age: 2)
    let lost = entry("lost", age: 0)
    let twice = entry("twice", age: 3)
    let statuses: [UUID: HighlightPlacement.Status] = [
      late.id: .placed(90..<95, late.target, section: "section-2"),
      early.id: .placed(10..<15, early.target, section: "section-1"),
      lost.id: .detached,
      twice.id: .ambiguous([]),
    ]
    let rows = AnnotationList.rows([late, early, lost, twice], statuses: statuses)
    #expect(rows.map(\.quote) == ["early", "late", "twice", "lost"])
    #expect(rows[0].placement == .placed(anchor: "p-early", section: "section-1"))
    #expect(rows[3].placement == .detached)
  }

  @Test func `one made since the build placed the others is listed last, not as gone`() {
    let placed = entry("placed", age: 1)
    let made = entry("made", age: 2)
    let rows = AnnotationList.rows(
      [placed, made], statuses: [placed.id: .placed(0..<6, placed.target, section: nil)])
    #expect(rows.map(\.quote) == ["placed", "made"])
    #expect(rows[1].placement == .unplaced)
  }

  @Test func `without a build the stored quotes are listed, oldest first`() {
    let rows = AnnotationList.rows([entry("b", age: 2), entry("a", age: 1)], statuses: nil)
    #expect(rows.map(\.quote) == ["a", "b"])
    #expect(rows.allSatisfy { $0.placement == .unplaced })
  }

  private func note(
    _ body: String, on highlight: UUID? = nil, target: Target? = nil, age: TimeInterval
  ) -> AnnotationSnapshot.NoteEntry {
    AnnotationSnapshot.NoteEntry(
      id: UUID(), document: .rfc(9110), highlight: highlight, target: target, body: body,
      createdAt: Date(timeIntervalSince1970: age), modifiedAt: .now)
  }

  @Test func `a highlight's notes are listed under it, by their first lines`() {
    let highlight = entry("quoted", age: 0)
    let second = note("**Second** note", on: highlight.id, age: 2)
    let first = note("First line\n\nmore", on: highlight.id, age: 1)
    let rows = AnnotationList.rows(
      [highlight], notes: [second, first],
      statuses: [highlight.id: .placed(0..<6, highlight.target, section: nil)])
    #expect(rows.count == 1)
    #expect(rows[0].notes.map(\.firstLine) == ["First line", "Second note"])
    #expect(rows[0].notes.map(\.id) == [first.id, second.id])
  }

  @Test func `a note on a section or a block is a row of its own, in document order`() {
    let highlight = entry("middle", age: 0)
    let section = note("On the section", target: .section("section-1"), age: 1)
    let block = note(
      "On the block",
      target: .range(
        start: Position(anchor: "p-9", offset: 0), end: Position(anchor: "p-9", offset: 4),
        quote: Quote(exact: "late", prefix: "", suffix: "")),
      age: 2)
    let lost = note("Lost", target: .section("section-9"), age: 3)
    let notes = NotePlacement(
      statuses: [
        section.id: .placed(0..<50, section: "section-1"),
        block.id: .placed(80..<84, section: "section-1"), lost.id: .detached,
      ], markers: [], relocations: [:], repoints: [:])
    let rows = AnnotationList.rows(
      [highlight], notes: [block, lost, section],
      statuses: [highlight.id: .placed(20..<26, highlight.target, section: "section-1")],
      noteStatuses: notes)
    #expect(rows.map(\.id) == [section.id, highlight.id, block.id, lost.id])
    #expect(rows[0].placement == .placed(anchor: "section-1", section: "section-1"))
    #expect(rows[0].isNote)
    #expect(rows[2].quote == "late")
    #expect(rows[3].placement == .detached)
  }

  @Test func `a relocated note's row goes to where relocation found it`() {
    let quote = Quote(exact: "moved", prefix: "", suffix: "")
    let made = note(
      "Moved",
      target: .range(
        start: Position(anchor: "p-1", offset: 0), end: Position(anchor: "p-1", offset: 5),
        quote: quote),
      age: 1)
    let found = Target.range(
      start: Position(anchor: "p-7", offset: 2), end: Position(anchor: "p-7", offset: 7),
      quote: quote)
    let notes = NotePlacement(
      statuses: [made.id: .placed(40..<45, section: "section-2")], markers: [],
      relocations: [made.id: found], repoints: [:])
    let rows = AnnotationList.rows([], notes: [made], statuses: [:], noteStatuses: notes)
    #expect(rows.map(\.placement) == [.placed(anchor: "p-7", section: "section-2")])
  }

  @Test func `the rotor says a highlight's color`() {
    let marks = HighlightMarks([
      HighlightMark(range: NSRange(location: 4, length: 3), color: .green, highlight: UUID())
    ])
    #expect(marks.rotorItems(locale: .english).map(\.label) == ["Highlighted, green"])
  }
}
