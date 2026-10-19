import Foundation
import RFCKit
import Testing

@testable import RFCReaderKit

/// A document's highlights and notes as one Markdown file (#524): what it says of each,
/// in what order, and what it cites. Over RFC 8999, whose passages are found at run
/// time by a short locator, so no expected output holds its text.
@Suite("Export: highlights and notes as Markdown")
struct AnnotationExportTests {
  private let document: RFCDocument
  private let model: ModelText
  private let id = DocumentID.rfc(8999)
  private let day = Date(timeIntervalSince1970: 1_792_368_000)  // 2026-10-19, UTC

  init() throws {
    document = try Fixtures.rfc8999()
    model = ModelText(document)
  }

  // MARK: Making annotations

  /// The range of the first `locator` inside `anchor`'s text.
  private func range(of locator: String, in anchor: String) throws -> Range<Int> {
    let span = try #require(model.span(of: anchor))
    let text = model.text(in: span.range) as NSString
    let found = text.range(of: locator)
    try #require(found.location != NSNotFound)
    return span.range.lowerBound + found.location..<span.range.lowerBound + NSMaxRange(found)
  }

  private func highlight(
    _ locator: String, in anchor: String, minute: Double = 0
  ) throws -> AnnotationSnapshot.HighlightEntry {
    let target = try #require(Target(covering: try range(of: locator, in: anchor), in: model))
    return highlight(target, minute: minute)
  }

  private func highlight(_ target: Target, minute: Double = 0)
    -> AnnotationSnapshot.HighlightEntry
  {
    let date = day.addingTimeInterval(minute * 60)
    return AnnotationSnapshot.HighlightEntry(
      id: UUID(), document: id, target: target, color: .yellow, createdAt: date,
      modifiedAt: date)
  }

  private func note(
    _ body: String, on highlight: AnnotationSnapshot.HighlightEntry? = nil,
    target: Target? = nil, minute: Double = 0
  ) -> AnnotationSnapshot.NoteEntry {
    let date = day.addingTimeInterval(minute * 60)
    return AnnotationSnapshot.NoteEntry(
      id: UUID(), document: id, highlight: highlight?.id, target: target ?? highlight?.target,
      body: body, createdAt: date, modifiedAt: date)
  }

  /// A target whose anchor the document does not have, with `quote`'s text and no
  /// context: found wherever the text is.
  private func lost(_ quote: String) -> Target {
    .range(
      start: Position(anchor: "gone", offset: 0), end: Position(anchor: "gone", offset: 1),
      quote: Quote(exact: quote, prefix: "", suffix: ""))
  }

  private func export(
    _ highlights: [AnnotationSnapshot.HighlightEntry],
    notes: [AnnotationSnapshot.NoteEntry] = []
  ) -> String {
    AnnotationExport.markdown(
      of: document, id: id, annotations: AnnotationSnapshot(highlights: highlights, notes: notes),
      exported: day, timeZone: .gmt)
  }

  private func heading(_ anchor: String) throws -> String {
    "## " + (try #require(document.section(anchor: anchor)).displayTitle)
  }

  /// Where `line` is among the export's lines; fails when it is not one of them.
  private func line(_ line: String, in markdown: String) throws -> Int {
    try #require(markdown.components(separatedBy: "\n").firstIndex(of: line), "no line \(line)")
  }

  private let longHeader = "long-header"
  private let longHeaderCitation =
    "— [RFC 8999, Section 5.1](https://www.rfc-editor.org/rfc/rfc8999#section-5.1)"

  // MARK: The file

  @Test func `the front matter names the RFC, its title and the day exported`() {
    let lines = export([]).components(separatedBy: "\n")
    #expect(
      Array(lines.prefix(5)) == [
        "---",
        "rfc: 8999",
        "title: \"\(document.header.title)\"",
        "exported: 2026-10-19",
        "---",
      ])
  }

  @Test func `a title's quotes and backslashes are escaped in the front matter`() {
    #expect(AnnotationExport.quoted(#"The "QUIC" \ Protocol"#) == #""The \"QUIC\" \\ Protocol""#)
  }

  @Test func `a document with nothing annotated says so`() throws {
    let markdown = export([])
    #expect(try line("No highlights or notes.", in: markdown) == 6)
    #expect(!markdown.contains("##"))
  }

  @Test func `another document's annotations are left out`() throws {
    let other = AnnotationSnapshot.HighlightEntry(
      id: UUID(), document: .rfc(9110),
      target: try #require(
        Target(covering: try range(of: "Version", in: longHeader), in: model)),
      color: .yellow, createdAt: day, modifiedAt: day)
    let markdown = AnnotationExport.markdown(
      of: document, id: id, annotations: AnnotationSnapshot(highlights: [other]), exported: day,
      timeZone: .gmt)
    #expect(markdown.contains("No highlights or notes."))
  }

  // MARK: Highlights

  @Test func `a highlight is a quote under its section's heading, cited from its section`()
    throws
  {
    let passage = try range(of: "Version", in: longHeader)
    let markdown = export([try highlight("Version", in: longHeader)])
    let heading = try line(try heading(longHeader), in: markdown)
    let quote = try line("> " + model.text(in: passage), in: markdown)
    let citation = try line(longHeaderCitation, in: markdown)
    #expect(heading < quote)
    #expect(quote < citation)
  }

  @Test func `a highlight in the abstract is cited from the document alone`() throws {
    let abstract = ModelText.abstractAnchor
    let locator = String(model.text(in: try #require(model.span(of: abstract)).range).prefix(4))
    let markdown = export([try highlight(locator, in: abstract)])
    let heading = try line("## Abstract", in: markdown)
    let citation = try line("— [RFC 8999](https://www.rfc-editor.org/info/rfc8999)", in: markdown)
    #expect(heading < citation)
  }

  @Test func `a highlight's notes follow its citation, oldest first`() throws {
    let highlight = try highlight("Version", in: longHeader)
    let markdown = export(
      [highlight],
      notes: [
        note("The second thought.", on: highlight, minute: 2),
        note("The first thought.", on: highlight, minute: 1),
      ])
    let citation = try line(longHeaderCitation, in: markdown)
    let first = try line("The first thought.", in: markdown)
    let second = try line("The second thought.", in: markdown)
    #expect(citation < first)
    #expect(first < second)
  }

  @Test func `sections follow the document, whatever order they were annotated in`() throws {
    let later = try highlight("Version", in: "version", minute: 0)
    let earlier = try highlight("Version", in: longHeader, minute: 1)
    let markdown = export([later, earlier])
    #expect(
      try line(try heading(longHeader), in: markdown) < line(try heading("version"), in: markdown))
  }

  @Test func `two highlights in one section share its heading`() throws {
    let markdown = export([
      try highlight("Version", in: longHeader), try highlight("Header Form", in: longHeader),
    ])
    let heading = try heading(longHeader)
    #expect(markdown.components(separatedBy: "\n").filter { $0 == heading }.count == 1)
  }

  // MARK: Notes of their own

  @Test func `a section note sits under its heading, ahead of the section's highlights`() throws {
    let markdown = export(
      [try highlight("Version", in: longHeader, minute: 0)],
      notes: [note("About the whole section.", target: .section(longHeader), minute: 1)])
    let heading = try line(try heading(longHeader), in: markdown)
    let note = try line("About the whole section.", in: markdown)
    let citation = try line(longHeaderCitation, in: markdown)
    #expect(heading < note)
    #expect(note < citation)
  }

  @Test func `a block note sits under the heading of its block's section`() throws {
    let section = try #require(model.span(of: longHeader))
    let block = try #require(
      model.spans.first { !$0.isSection && $0.range.lowerBound >= section.range.lowerBound })
    let target = try #require(Target(covering: block.range, in: model))
    let markdown = export([], notes: [note("About this block.", target: target)])
    #expect(
      try line(try heading(longHeader), in: markdown) < line("About this block.", in: markdown))
  }

  // MARK: What is placed nowhere

  @Test func `a detached highlight comes last, with its quote and notes, and no citation`()
    throws
  {
    let placed = try highlight("Version", in: longHeader, minute: 0)
    let detached = highlight(lost("A sentence this document never had."), minute: 1)
    let markdown = export(
      [placed, detached], notes: [note("Where did it go?", on: detached, minute: 2)])
    let notPlaced = try line("## Not placed", in: markdown)
    let quote = try line("> A sentence this document never had.", in: markdown)
    let note = try line("Where did it go?", in: markdown)
    #expect(try line(longHeaderCitation, in: markdown) < notPlaced)
    #expect(notPlaced < quote)
    #expect(quote < note)
    #expect(markdown.components(separatedBy: "\n").filter { $0.hasPrefix("— ") }.count == 1)
  }

  @Test func `an ambiguous highlight is left out, and its notes come last with its quote`()
    throws
  {
    let ambiguous = highlight(lost("Connection ID"), minute: 0)
    #expect(export([ambiguous]).contains("No highlights or notes."))

    let markdown = export([ambiguous], notes: [note("Which one?", on: ambiguous, minute: 1)])
    let notPlaced = try line("## Not placed", in: markdown)
    let quote = try line("> Connection ID", in: markdown)
    let note = try line("Which one?", in: markdown)
    #expect(notPlaced < quote)
    #expect(quote < note)
    #expect(!markdown.contains("— ["))
  }

  @Test func `a section note whose section is gone comes last`() throws {
    let markdown = export([], notes: [note("On a section that went.", target: .section("gone"))])
    #expect(try line("## Not placed", in: markdown) < line("On a section that went.", in: markdown))
  }

  // MARK: Note bodies

  @Test func `a note's rfc links become rfc-editor.org links, and others stay`() throws {
    let highlight = try highlight("Version", in: longHeader)
    let markdown = export(
      [highlight],
      notes: [
        note(
          "See [semantics](rfc://9110#section-4.2) and [the site](https://example.com/page).",
          on: highlight)
      ])
    #expect(
      markdown.contains(
        "See [semantics](https://www.rfc-editor.org/rfc/rfc9110#section-4.2) and"
          + " [the site](https://example.com/page)."))
    #expect(!markdown.contains("rfc://"))
  }

  @Test func `a note keeps its formatting and lists`() throws {
    let body = "Some *emphasis* and `code`.\n\n- one\n- two"
    let markdown = export([], notes: [note(body, target: .section(longHeader))])
    #expect(markdown.contains(body))
  }
}
