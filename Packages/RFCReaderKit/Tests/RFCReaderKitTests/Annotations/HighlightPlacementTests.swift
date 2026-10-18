import Foundation
import RFCKit
import Testing

@testable import RFCReaderKit

/// Where a build draws a document's highlights (#522), and what it says of each.
@Suite("Annotations: placing highlights")
struct HighlightPlacementTests {
  private let document = Fixtures.document(
    .paragraph(Paragraph(text: "The client MUST send a request.", anchor: "p-1")),
    .paragraph(Paragraph(text: "Repeat. Repeat.", anchor: "p-2")))

  private func entry(
    _ needle: String, in model: ModelText, color: HighlightColor = .yellow,
    occurrence: Int = 0
  ) throws -> AnnotationSnapshot.HighlightEntry {
    let text = model.text(in: 0..<model.length) as NSString
    var found = text.range(of: needle)
    for _ in 0..<occurrence {
      found = text.range(
        of: needle,
        range: NSRange(location: NSMaxRange(found), length: text.length - NSMaxRange(found)))
    }
    let target = try #require(Target(covering: found.location..<NSMaxRange(found), in: model))
    return AnnotationSnapshot.HighlightEntry(
      id: UUID(), document: .rfc(9110), target: target, color: color, createdAt: .now,
      modifiedAt: .now)
  }

  @Test func `a highlight is drawn over its own words`() throws {
    let built = DocumentTextBuilder.build(document, style: ReadingStyle())
    let highlight = try entry("MUST send", in: built.positions.model, color: .green)
    let placement = HighlightPlacement([highlight], in: built)
    let mark = try #require(placement.marks.marks.first)
    #expect((built.text.string as NSString).substring(with: mark.range) == "MUST send")
    #expect(mark.color == .green)
    #expect(placement.relocations.isEmpty)
    guard case .placed? = placement.statuses[highlight.id] else {
      Issue.record("not placed")
      return
    }
  }

  @Test func `one whose quote is in several places is drawn nowhere`() throws {
    let built = DocumentTextBuilder.build(document, style: ReadingStyle())
    // Made where the text read otherwise: the stored position no longer matches.
    let other = ModelText(
      Fixtures.document(
        .paragraph(Paragraph(text: "Opening.")),
        .paragraph(Paragraph(text: "Repeat. Repeat.", anchor: "p-2"))))
    var highlight = try entry("Repeat", in: other)
    guard case .range(let start, let end, var quote) = highlight.target else { return }
    quote.prefix = ""
    quote.suffix = ""
    highlight = AnnotationSnapshot.HighlightEntry(
      id: highlight.id, document: .rfc(9110),
      target: .range(
        start: Position(anchor: "p-1", offset: start.offset),
        end: Position(anchor: "p-1", offset: end.offset), quote: quote),
      color: .yellow, createdAt: .now, modifiedAt: .now)
    let placement = HighlightPlacement([highlight], in: built)
    #expect(placement.marks.marks.isEmpty)
    guard case .ambiguous(let places)? = placement.statuses[highlight.id] else {
      Issue.record("not ambiguous")
      return
    }
    #expect(places.count == 2)
  }

  @Test func `one that moved is drawn where it went, and its relocation reported`() throws {
    let before = ModelText(
      Fixtures.document(.paragraph(Paragraph(text: "The client MUST send a request."))))
    let highlight = try entry("MUST send", in: before)
    let built = DocumentTextBuilder.build(document, style: ReadingStyle())
    let placement = HighlightPlacement([highlight], in: built)
    #expect(placement.marks.marks.count == 1)
    #expect(placement.relocations[highlight.id] != nil)
  }

  @Test func `a translation draws none`() throws {
    let built = DocumentTextBuilder.build(
      TranslatedDocument(document, [:]),
      style: ReadingStyle())
    let highlight = try entry("MUST send", in: built.positions.model)
    #expect(HighlightPlacement([highlight], in: built) == .none)
  }

  /// Highlighting is drawn from the placement, never written into the build, which is
  /// handed over and may be installed into more than one text view
  /// (`BuilderHandoverTests`).
  @Test func `placing highlights leaves the build untouched`() throws {
    let built = DocumentTextBuilder.build(try Fixtures.rfc8999(), style: ReadingStyle())
    let string = built.text.string
    var runs: [String] = []
    built.text.enumerateAttributes(in: NSRange(location: 0, length: built.text.length)) {
      attributes, range, _ in
      runs.append("\(range) \(attributes.keys.map(\.rawValue).sorted())")
    }
    let model = built.positions.model
    let highlights = try stride(from: 100, to: model.length - 200, by: 900).map { start in
      let target = try #require(Target(covering: start..<start + 80, in: model))
      return AnnotationSnapshot.HighlightEntry(
        id: UUID(), document: .rfc(8999), target: target, color: .blue, createdAt: .now,
        modifiedAt: .now)
    }
    let placement = HighlightPlacement(highlights, in: built)
    #expect(!placement.marks.marks.isEmpty)
    var after: [String] = []
    built.text.enumerateAttributes(in: NSRange(location: 0, length: built.text.length)) {
      attributes, range, _ in
      after.append("\(range) \(attributes.keys.map(\.rawValue).sorted())")
    }
    #expect(built.text.string == string)
    #expect(after == runs)
  }

  @Test func `a highlight across a heading and its paragraph is one shape`() throws {
    let built = DocumentTextBuilder.build(document, style: ReadingStyle())
    let model = built.positions.model
    // From the heading's word through the first paragraph's first word.
    let target = try #require(Target(covering: 0..<5, in: model))
    let drawn = built.positions.drawnRanges(forModel: try #require(target.range(in: model)))
    #expect(drawn.count == 1)
  }

  @Test func `marks are found by the range they meet`() {
    let first = HighlightMark(
      range: NSRange(location: 10, length: 5), color: .yellow, highlight: UUID())
    let second = HighlightMark(
      range: NSRange(location: 30, length: 5), color: .blue, highlight: UUID())
    let marks = HighlightMarks([second, first])
    #expect(marks.marks(meeting: NSRange(location: 12, length: 20)) == [first, second])
    #expect(marks.marks(meeting: NSRange(location: 15, length: 15)).isEmpty)
    #expect(marks.highlight(at: 31) == second)
  }
}
