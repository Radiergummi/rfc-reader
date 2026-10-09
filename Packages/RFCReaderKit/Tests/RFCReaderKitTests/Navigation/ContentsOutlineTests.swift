import RFCKit
import Testing

@testable import RFCReaderKit

/// The Contents tab: a document's sections in its own order or A–Z, narrowed by
/// words in a title or the start of a number.
@Suite("Contents outline")
struct ContentsOutlineTests {
  /// Flat, in document order, as `DocumentView` hands the tab its sections.
  static let sections = [
    Section(anchor: "section-1", number: "1", title: "Introduction"),
    Section(anchor: "section-1.1", number: "1.1", title: "Requirements Language"),
    Section(anchor: "section-4", number: "4", title: "Résumé Handling"),
    Section(anchor: "section-4.2", number: "4.2", title: "Caching"),
    Section(anchor: "section-4.2.1", number: "4.2.1", title: "Freshness"),
    Section(anchor: "section-14", number: "14", title: "Security Considerations"),
    Section(anchor: "section-14.2", number: "14.2", title: "Cache Poisoning"),
    Section(anchor: "appendix-A", number: "A", title: "Collected ABNF", isAppendix: true),
    Section(anchor: "acknowledgments", title: "Acknowledgments"),
  ]

  static func rows(_ filter: String) -> [ContentsOutline.Row] {
    ContentsOutline.rows(of: sections, filter: filter)
  }

  /// An annex is listed as one, and its qualifier is set apart from its title (#428).
  @Test func `an annex row names it and carries its qualifier`() throws {
    let annex = Section(
      anchor: "appendix-B", number: "B", title: "Background", isAppendix: true,
      appendixWord: .annex, qualifier: .informative)
    let row = try #require(ContentsOutline.rows(of: [annex], filter: "").first)
    #expect(row.title == "Annex B. Background")
    #expect(row.qualifier == "Informative")
    #expect(Self.rows("").allSatisfy { $0.qualifier == nil })
  }

  @Test func `with no filter, document order lists every section at its depth`() {
    let rows = Self.rows("")
    #expect(rows.map(\.anchor) == Self.sections.map(\.anchor))
    #expect(rows.map(\.depth) == [1, 2, 1, 2, 3, 1, 2, 1, 1])
    #expect(rows.map(\.title)[3] == "4.2. Caching")
    #expect(rows.allSatisfy { !$0.isContext })
  }

  @Test func `a filter keeps a match's ancestors, as context`() {
    let rows = Self.rows("fresh")
    #expect(rows.map(\.anchor) == ["section-4", "section-4.2", "section-4.2.1"])
    #expect(rows.map(\.isContext) == [true, true, false])
  }

  @Test func `matches in two branches each bring their own ancestors`() {
    let rows = Self.rows("cach")
    #expect(rows.map(\.anchor) == ["section-4", "section-4.2", "section-14", "section-14.2"])
    #expect(rows.map(\.isContext) == [true, false, true, false])
  }

  @Test func `an ancestor that matches is a match, not context`() {
    let rows = Self.rows("4")
    #expect(rows.map(\.anchor) == ["section-4", "section-4.2", "section-4.2.1"])
    #expect(rows.allSatisfy { !$0.isContext })
  }

  @Test func `a title matches without regard to case or diacritics`() {
    #expect(Self.rows("RESUME").map(\.anchor) == ["section-4"])
  }

  @Test func `a number matches from its start`() {
    #expect(Self.rows("4.2").map(\.anchor) == ["section-4", "section-4.2", "section-4.2.1"])
  }

  @Test func `a number matches as the list shows it, with its period or as an appendix`() {
    #expect(Self.rows("4.2.").map(\.anchor) == ["section-4", "section-4.2", "section-4.2.1"])
    #expect(Self.rows("appendix a").map(\.anchor) == ["appendix-A"])
    #expect(Self.rows("Appendix A.").map(\.anchor) == ["appendix-A"])
    #expect(Self.rows("4.2. cach").map(\.anchor) == ["section-4", "section-4.2"])
  }

  @Test func `an appendix matches by its number alone, as a section does`() {
    #expect(Self.rows("A.").map(\.anchor) == ["appendix-A"])
    #expect(
      ContentsOutline.groups(of: Self.sections, filter: "A.").flatMap(\.entries).map(\.anchor) == [
        "appendix-A"
      ])
  }

  @Test func `whitespace around the filter is ignored`() {
    #expect(Self.rows("  fresh ").map(\.anchor).last == "section-4.2.1")
    #expect(Self.rows("   ").count == Self.sections.count)
  }

  @Test func `a filter that matches nothing lists nothing`() {
    #expect(Self.rows("zzz").isEmpty)
  }

  static func alphabetical(
    _ sections: [Section] = sections, _ filter: String = ""
  ) -> [ContentsOutline.Group] {
    ContentsOutline.groups(of: sections, filter: filter)
  }

  @Test func `alphabetical order sorts by title and sets the number aside as a caption`() {
    let entries = Self.alphabetical().flatMap(\.entries)
    #expect(
      entries.map(\.title) == [
        "Acknowledgments", "Cache Poisoning", "Caching", "Collected ABNF", "Freshness",
        "Introduction", "Requirements Language", "Résumé Handling", "Security Considerations",
      ])
    #expect(
      entries.map(\.caption) == [nil, "14.2", "4.2", "Appendix A", "4.2.1", "1", "1.1", "4", "14"])
  }

  @Test func `alphabetical order groups by first letter, folding diacritics`() {
    let groups = Self.alphabetical([
      Section(anchor: "a", number: "1", title: "Élan"),
      Section(anchor: "b", number: "2", title: "Echo"),
      Section(anchor: "c", number: "3", title: "alpha"),
    ])
    #expect(groups.map(\.label) == ["A", "E"])
    #expect(groups[1].entries.map(\.title) == ["Echo", "Élan"])
  }

  @Test func `titles that do not start with a Latin letter gather under # at the end`() {
    let groups = Self.alphabetical([
      Section(anchor: "a", number: "1", title: "Ωmega Handling"),
      Section(anchor: "b", number: "2", title: "Zebra"),
      Section(anchor: "c", number: "3", title: "3GPP Interworking"),
      Section(anchor: "d", number: "4", title: "Alpha"),
    ])
    #expect(groups.map(\.label) == ["A", "Z", "#"])
    #expect(groups[2].entries.map(\.anchor) == ["c", "a"])
  }

  @Test func `leading punctuation is set aside for sorting, not for showing`() {
    let groups = Self.alphabetical([
      Section(anchor: "a", number: "1", title: "Zone Files"),
      Section(anchor: "b", number: "2", title: "\"Quoted\" Strings"),
    ])
    #expect(groups.map(\.label) == ["Q", "Z"])
    #expect(groups[0].entries[0].title == "\"Quoted\" Strings")
  }

  @Test func `numbers in titles sort by value`() {
    let entries = Self.alphabetical([
      Section(anchor: "a", number: "1", title: "Step 10"),
      Section(anchor: "b", number: "2", title: "Step 2"),
    ]).flatMap(\.entries)
    #expect(entries.map(\.anchor) == ["b", "a"])
  }

  @Test func `equal titles keep the document's order, told apart by their numbers`() {
    let entries = Self.alphabetical([
      Section(anchor: "a", number: "3.1", title: "Overview"),
      Section(anchor: "b", number: "2.1", title: "Overview"),
    ]).flatMap(\.entries)
    #expect(entries.map(\.anchor) == ["a", "b"])
    #expect(entries.map(\.caption) == ["3.1", "2.1"])
  }

  @Test func `a section without words in its title shows by its number, under #`() {
    let groups = Self.alphabetical([
      Section(anchor: "a", number: "1", title: "Alpha"),
      Section(anchor: "b", number: "5", title: ""),
    ])
    #expect(groups.map(\.label) == ["A", "#"])
    #expect(groups[1].entries[0].title == "5.")
    #expect(groups[1].entries[0].caption == nil)
  }

  @Test func `an appendix without words in its title shows by its number, under # too`() {
    let groups = Self.alphabetical([
      Section(anchor: "a", number: "1", title: "Alpha"),
      Section(anchor: "b", number: "B", title: "", isAppendix: true),
    ])
    #expect(groups.map(\.label) == ["A", "#"])
    #expect(groups[1].entries[0].title == "Appendix B")
  }

  @Test func `the filter applies in A–Z too, with no context rows`() {
    let entries = Self.alphabetical(Self.sections, "cach").flatMap(\.entries)
    #expect(entries.map(\.anchor) == ["section-14.2", "section-4.2"])
    #expect(Self.alphabetical(Self.sections, "zzz").isEmpty)
  }
}
