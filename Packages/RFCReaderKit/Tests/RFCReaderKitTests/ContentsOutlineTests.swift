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
    ContentsOutline.groups(of: sections, filter: filter, order: .document).flatMap(\.rows)
  }

  @Test func `with no filter, document order lists every section at its depth`() {
    let groups = ContentsOutline.groups(of: Self.sections, filter: "", order: .document)
    #expect(groups.count == 1)
    #expect(groups[0].label == nil)
    #expect(groups[0].rows.map(\.anchor) == Self.sections.map(\.anchor))
    #expect(groups[0].rows.map(\.depth) == [1, 2, 1, 2, 3, 1, 2, 1, 1])
    #expect(groups[0].rows.map(\.title)[3] == "4.2. Caching")
    #expect(groups[0].rows.allSatisfy { !$0.isContext && $0.caption == nil })
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

  @Test func `whitespace around the filter is ignored`() {
    #expect(Self.rows("  fresh ").map(\.anchor).last == "section-4.2.1")
    #expect(Self.rows("   ").count == Self.sections.count)
  }

  @Test func `a filter that matches nothing leaves no group`() {
    #expect(ContentsOutline.groups(of: Self.sections, filter: "zzz", order: .document).isEmpty)
  }

  static func alphabetical(
    _ sections: [Section] = sections, _ filter: String = ""
  ) -> [ContentsOutline.Group] {
    ContentsOutline.groups(of: sections, filter: filter, order: .alphabetical)
  }

  @Test func `alphabetical order sorts by title and sets the number aside as a caption`() {
    let rows = Self.alphabetical().flatMap(\.rows)
    #expect(
      rows.map(\.title) == [
        "Acknowledgments", "Cache Poisoning", "Caching", "Collected ABNF", "Freshness",
        "Introduction", "Requirements Language", "Résumé Handling", "Security Considerations",
      ])
    #expect(
      rows.map(\.caption) == [nil, "14.2", "4.2", "Appendix A", "4.2.1", "1", "1.1", "4", "14"])
    #expect(rows.allSatisfy { $0.depth == 1 && !$0.isContext })
  }

  @Test func `alphabetical order groups by first letter, folding diacritics`() {
    let groups = Self.alphabetical([
      Section(anchor: "a", number: "1", title: "Élan"),
      Section(anchor: "b", number: "2", title: "Echo"),
      Section(anchor: "c", number: "3", title: "alpha"),
    ])
    #expect(groups.map(\.label) == ["A", "E"])
    #expect(groups[1].rows.map(\.title) == ["Echo", "Élan"])
  }

  @Test func `titles that do not start with a Latin letter gather under # at the end`() {
    let groups = Self.alphabetical([
      Section(anchor: "a", number: "1", title: "Ωmega Handling"),
      Section(anchor: "b", number: "2", title: "Zebra"),
      Section(anchor: "c", number: "3", title: "3GPP Interworking"),
      Section(anchor: "d", number: "4", title: "Alpha"),
    ])
    #expect(groups.map(\.label) == ["A", "Z", "#"])
    #expect(groups[2].rows.map(\.anchor) == ["c", "a"])
  }

  @Test func `leading punctuation is set aside for sorting, not for showing`() {
    let groups = Self.alphabetical([
      Section(anchor: "a", number: "1", title: "Zone Files"),
      Section(anchor: "b", number: "2", title: "\"Quoted\" Strings"),
    ])
    #expect(groups.map(\.label) == ["Q", "Z"])
    #expect(groups[0].rows[0].title == "\"Quoted\" Strings")
  }

  @Test func `numbers in titles sort by value`() {
    let rows = Self.alphabetical([
      Section(anchor: "a", number: "1", title: "Step 10"),
      Section(anchor: "b", number: "2", title: "Step 2"),
    ]).flatMap(\.rows)
    #expect(rows.map(\.anchor) == ["b", "a"])
  }

  @Test func `equal titles keep the document's order, told apart by their numbers`() {
    let rows = Self.alphabetical([
      Section(anchor: "a", number: "3.1", title: "Overview"),
      Section(anchor: "b", number: "2.1", title: "Overview"),
    ]).flatMap(\.rows)
    #expect(rows.map(\.anchor) == ["a", "b"])
    #expect(rows.map(\.caption) == ["3.1", "2.1"])
  }

  @Test func `a section without words in its title shows by its number, under #`() {
    let groups = Self.alphabetical([
      Section(anchor: "a", number: "1", title: "Alpha"),
      Section(anchor: "b", number: "5", title: ""),
    ])
    #expect(groups.map(\.label) == ["A", "#"])
    #expect(groups[1].rows[0].title == "5.")
    #expect(groups[1].rows[0].caption == nil)
  }

  @Test func `the filter applies in A–Z too, with no context rows`() {
    let rows = Self.alphabetical(Self.sections, "cach").flatMap(\.rows)
    #expect(rows.map(\.anchor) == ["section-14.2", "section-4.2"])
    #expect(Self.alphabetical(Self.sections, "zzz").isEmpty)
  }
}
