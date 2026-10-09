import Foundation
import RFCKit
import Testing

@testable import RFCReaderKit

/// What the Info pane lists of a document's errata (#387): the verified and held
/// ones, those naming no section first, each with the section it names; the others
/// only counted.
@Suite("Errata summary")
struct ErrataSummaryTests {
  private static func erratum(
    _ id: Int, _ status: Erratum.Status, section: String = "4.1", type: Erratum.Kind = .technical
  ) -> Erratum {
    Erratum(
      id: id, document: .rfc(9999), status: status, type: type, section: section,
      original: "old", corrected: "new", notes: "", submitted: "2024-01-0\(id % 10)")
  }

  /// The document's sections, numbered as a parse numbers them, with anchors of
  /// their own that no `section-N` spelling would guess.
  private static let sections = [
    Section(
      anchor: "intro", number: "1", title: [.text("Introduction")],
      subsections: [Section(anchor: "scope", number: "1.2", title: [.text("Scope")])]),
    Section(
      anchor: "details", number: "4", title: [.text("Details")],
      subsections: [Section(anchor: "the-detail", number: "4.1", title: [.text("Detail")])]),
    Section(anchor: "extra", number: "A", title: [.text("Extra")], isAppendix: true),
    // An appendix numbered like a section, as some legacy RFCs number theirs (#429).
    Section(anchor: "appendix-1", number: "1", title: [.text("Notes")], isAppendix: true),
  ]

  private func summary(_ errata: [Erratum]) -> ErrataSummary {
    ErrataSummary(errata: errata, sections: Self.sections, locale: .english)
  }

  @Test func `verified and held errata are listed, the others counted`() {
    let summary = summary([
      Self.erratum(1, .verified), Self.erratum(2, .heldForDocumentUpdate),
      Self.erratum(3, .reported), Self.erratum(4, .reported), Self.erratum(5, .rejected),
      Self.erratum(6, .other("Archived")),
    ])
    #expect(summary.items.map(\.id) == [1, 2])
    // A status a later feed adds is neither: the RFC Editor's page lists it.
    #expect(summary.notListed == "2 not yet reviewed and 1 rejected")
  }

  /// Those naming no section are the whole document's, and come first (decision on
  /// #387); the rest keep the order they were submitted in.
  @Test func `errata naming no section come first`() {
    let summary = summary([
      Self.erratum(1, .verified), Self.erratum(2, .verified, section: "GLOBAL"),
      Self.erratum(3, .verified, section: "1.2"),
    ])
    #expect(summary.items.map(\.id) == [2, 1, 3])
  }

  /// A section is found by its number, whatever its anchor is spelled.
  @Test func `a section is found by its number`() {
    let items = summary([
      Self.erratum(1, .verified, section: "4.1"), Self.erratum(2, .verified, section: "A"),
      Self.erratum(3, .verified, section: "In Sections 9 and 1.2"),
    ]).items
    #expect(items.map(\.anchor) == ["the-detail", "extra", "scope"])
  }

  /// "Appendix 1" is the appendix numbered 1, never the body's Section 1.
  @Test func `a numbered appendix is its own place`() throws {
    let item = try #require(
      summary([Self.erratum(1, .verified, section: "Appendix 1")]).items.first)
    #expect(item.place == "Appendix 1")
    #expect(item.anchor == "appendix-1")
  }

  /// A place the reporter named that is no section is shown as written, and only the
  /// feed's `GLOBAL` or nothing reads as the whole document.
  @Test func `a place that is no section is named as written`() {
    let items = summary([
      Self.erratum(1, .verified, section: "Figure 15"),
      Self.erratum(2, .verified, section: "The abstract says:"),
      Self.erratum(3, .verified, section: "GLOBAL"), Self.erratum(4, .verified, section: ""),
    ]).items
    #expect(
      items.map(\.place) == [
        "Figure 15", "The abstract says", "Whole document", "Whole document",
      ])
  }

  /// A section the document doesn't have, or none at all, is never guessed at.
  @Test func `a section the document lacks links nowhere`() {
    let items = summary([
      Self.erratum(1, .verified, section: "9.9"), Self.erratum(2, .verified, section: "Figure 1"),
    ]).items
    #expect(items.map(\.anchor) == [nil, nil])
  }

  @Test func `without a body nothing links`() {
    let summary = ErrataSummary(
      errata: [Self.erratum(1, .verified)], sections: [], locale: .english)
    #expect(summary.items.first?.anchor == nil)
  }

  @Test func `an item names its status, type and place`() throws {
    let items = summary([
      Self.erratum(1, .verified, section: "4.1"),
      Self.erratum(2, .heldForDocumentUpdate, section: "A.2", type: .editorial),
      Self.erratum(3, .verified, section: "In Sections 7.8, 7.9, and 8.4.1"),
      Self.erratum(4, .verified, section: "Figure 1"),
      Self.erratum(5, .verified, section: "Appendix B and Section 2"),
    ]).items
    #expect(
      items.map(\.place) == [
        "Figure 1", "Section 4.1", "Appendix A.2", "Sections 7.8, 7.9, and 8.4.1",
        "Appendix B and Section 2",
      ])
    let held = try #require(items.first { $0.id == 2 })
    #expect(held.status == "Held for Document Update")
    #expect(held.type == "Editorial")
    #expect(items.first { $0.id == 1 }?.type == "Technical")
  }

  @Test func `an item carries the texts and its page`() throws {
    let item = try #require(summary([Self.erratum(7, .verified)]).items.first)
    #expect(item.original == "old")
    #expect(item.corrected == "new")
    #expect(item.page == URL(string: "https://www.rfc-editor.org/errata/eid7"))
    #expect(item.notes == "")
  }

  @Test func `a document without errata has an empty summary`() {
    let summary = summary([])
    #expect(summary.items.isEmpty)
    #expect(summary.notListed == nil)
  }
}
