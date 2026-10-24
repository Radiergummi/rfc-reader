import Foundation
import RFCKit
import Testing

@testable import RFCReaderKit

/// Where a build places a document's notes (#523), and the orphan rules: a note whose
/// highlight is gone is put on the highlight that covers where it was, and kept,
/// detached, when none does.
@Suite("Annotations: placing notes")
struct NotePlacementTests {
  private let built = DocumentTextBuilder.build(
    Fixtures.document(
      .paragraph(Paragraph(text: "The client MUST send a request.", anchor: "p-1")),
      .paragraph(Paragraph(text: "The server SHOULD answer it.", anchor: "p-2"))),
    style: ReadingStyle())

  private var model: ModelText { built.positions.model }

  private func target(_ needle: String) throws -> Target {
    let found = (model.text(in: 0..<model.length) as NSString).range(of: needle)
    return try #require(Target(covering: found.location..<NSMaxRange(found), in: model))
  }

  private func highlight(_ needle: String, createdAt: Date = .now) throws
    -> AnnotationSnapshot.HighlightEntry
  {
    AnnotationSnapshot.HighlightEntry(
      id: UUID(), document: .rfc(9110), target: try target(needle), color: .yellow,
      createdAt: createdAt, modifiedAt: createdAt)
  }

  private func note(on highlight: UUID?, target: Target?, createdAt: Date = .now)
    -> AnnotationSnapshot.NoteEntry
  {
    AnnotationSnapshot.NoteEntry(
      id: UUID(), document: .rfc(9110), highlight: highlight, target: target, body: "x",
      createdAt: createdAt, modifiedAt: createdAt)
  }

  private func storage(at location: Int, length: Int) -> String {
    (built.text.string as NSString).substring(with: NSRange(location: location, length: length))
  }

  @Test func `a note's text alone places it nowhere else`() throws {
    let made = note(on: nil, target: try target("MUST send"))
    func copy(
      body: String = "x", highlight: UUID? = nil, target: Target? = nil,
      relocated: Target? = nil
    ) -> AnnotationSnapshot.NoteEntry {
      AnnotationSnapshot.NoteEntry(
        id: made.id, document: made.document, highlight: highlight ?? made.highlight,
        target: target ?? made.target, relocated: relocated, body: body,
        createdAt: made.createdAt, modifiedAt: .now)
    }
    #expect(NotePlacement.placesAlike([made], [copy(body: "*typed* since")]))
    #expect(!NotePlacement.placesAlike([made], [copy(highlight: UUID())]))
    #expect(!NotePlacement.placesAlike([made], [copy(target: try target("SHOULD"))]))
    #expect(!NotePlacement.placesAlike([made], [copy(relocated: try target("SHOULD"))]))
    #expect(!NotePlacement.placesAlike([made], [made, copy()]))
  }

  @Test func `a note on a highlight stands at the highlight's start`() throws {
    let highlight = try highlight("MUST send")
    let note = note(on: highlight.id, target: highlight.target)
    let placement = NotePlacement(
      [note], highlights: HighlightPlacement([highlight], in: built), in: built)
    #expect(placement.statuses[note.id] == .onHighlight(highlight.id))
    let marker = try #require(placement.markers.first)
    #expect(storage(at: marker.location, length: 4) == "MUST")
  }

  @Test func `a note on a block or a section stands at its start`() throws {
    let block = note(on: nil, target: try target("The server SHOULD answer it."))
    let section = note(on: nil, target: .section("p-1"))
    let placement = NotePlacement(
      [block, section], highlights: HighlightPlacement([], in: built), in: built)
    let locations = Dictionary(
      uniqueKeysWithValues: placement.markers.map { ($0.note, $0.location) })
    #expect(storage(at: try #require(locations[block.id]), length: 10) == "The server")
    #expect(storage(at: try #require(locations[section.id]), length: 10) == "The client")
    #expect(placement.markers.map(\.note) == [section.id, block.id])
  }

  @Test func `a note whose highlight is gone is put on the one that covers it`() throws {
    let survivor = try highlight("client MUST send a")
    let orphan = note(on: UUID(), target: try target("MUST send"))
    let placement = NotePlacement(
      [orphan], highlights: HighlightPlacement([survivor], in: built), in: built)
    #expect(placement.repoints == [orphan.id: survivor.id])
    #expect(placement.statuses[orphan.id] == .onHighlight(survivor.id))
    #expect(placement.highlight(of: orphan) == survivor.id)
    #expect(placement.markers.map(\.note) == [orphan.id])
  }

  @Test func `a note whose highlight is gone and that none covers is kept, detached`() throws {
    let elsewhere = try highlight("SHOULD answer")
    let orphan = note(on: UUID(), target: try target("MUST send"))
    let placement = NotePlacement(
      [orphan], highlights: HighlightPlacement([elsewhere], in: built), in: built)
    #expect(placement.repoints.isEmpty)
    #expect(placement.statuses[orphan.id] == .detached)
    #expect(placement.markers.isEmpty)
  }

  @Test func `a note on a section that is gone is detached`() {
    let note = note(on: nil, target: .section("section-99"))
    let placement = NotePlacement(
      [note], highlights: HighlightPlacement([], in: built), in: built)
    #expect(placement.statuses[note.id] == .detached)
  }

  @Test func `a note's own range that moved is placed where it went, and reported`() throws {
    let before = ModelText(
      Fixtures.document(.paragraph(Paragraph(text: "The server SHOULD answer it."))))
    let found = (before.text(in: 0..<before.length) as NSString).range(of: "SHOULD answer it")
    let moved = note(
      on: nil, target: Target(covering: found.location..<NSMaxRange(found), in: before))
    let placement = NotePlacement(
      [moved], highlights: HighlightPlacement([], in: built), in: built)
    #expect(placement.relocations[moved.id] != nil)
    #expect(placement.markers.count == 1)
  }
}
