import Foundation
import RFCKit
import Testing

@testable import RFCReaderKit

/// The iOS list's year sections (#347).
@Suite("Year sections")
struct YearSectionsTests {
  private func rfc(_ number: Int, year: Int) -> LibraryRow {
    .rfc(Fixtures.metadata(number, year: year))
  }

  @Test func `consecutive rows of one year make one section`() {
    let rows = [rfc(10050, year: 2026), rfc(10042, year: 2026), rfc(9700, year: 2025)]

    let sections = YearSections.sections(of: rows)

    #expect(sections.map(\.year) == [2026, 2025])
    #expect(sections.map { $0.rows.map(\.id.number) } == [[10050, 10042], [9700]])
  }

  /// Numbers are assigned before publication, so a list in number order can put a
  /// year out of place. A second header for it would read as a bug.
  @Test func `a row out of its year's run joins its year`() {
    let rows = [rfc(10050, year: 2026), rfc(10049, year: 2025), rfc(10048, year: 2026)]

    let sections = YearSections.sections(of: rows)

    #expect(sections.map(\.year) == [2026, 2025])
    #expect(sections.map { $0.rows.map(\.id.number) } == [[10050, 10048], [10049]])
  }

  @Test func `nothing makes no sections`() {
    #expect(YearSections.sections(of: []).isEmpty)
  }

  @Test func `the lists the index orders are sectioned`() {
    #expect(YearSections.apply(to: .all, query: ""))
    #expect(YearSections.apply(to: .standards, query: ""))
    #expect(YearSections.apply(to: .stream(.ietf), query: ""))
    #expect(YearSections.apply(to: .workingGroup("httpbis"), query: ""))
  }

  /// Recently Read is in reading order and a search in order of relevance; the
  /// reader's own lists stay unsectioned for now.
  @Test func `other orders are not sectioned`() {
    #expect(!YearSections.apply(to: .recent, query: ""))
    #expect(!YearSections.apply(to: .bookmarks, query: ""))
    #expect(!YearSections.apply(to: .downloaded, query: ""))
    #expect(!YearSections.apply(to: .series(DocumentID(series: .bcp, number: 14)), query: ""))
    #expect(!YearSections.apply(to: .all, query: "http"))
  }

  @Test func `a query of only spaces is no search`() {
    #expect(YearSections.apply(to: .all, query: "  "))
  }
}
