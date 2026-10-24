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

  @Test func `without a build the stored quotes are listed, oldest first`() {
    let rows = AnnotationList.rows([entry("b", age: 2), entry("a", age: 1)], statuses: nil)
    #expect(rows.map(\.quote) == ["a", "b"])
    #expect(rows.allSatisfy { $0.placement == .unplaced })
  }

  @Test func `the rotor says a highlight's color`() {
    let marks = HighlightMarks([
      HighlightMark(range: NSRange(location: 4, length: 3), color: .green, highlight: UUID())
    ])
    #expect(marks.rotorItems(locale: .english).map(\.label) == ["Highlighted, green"])
  }
}
