import RFCKit
import Testing

@testable import RFCReaderKit

/// The Go to RFC palette's list: what was typed, resolved exactly, and then what the
/// search found for it.
@Suite("Quick open results")
struct QuickOpenResultsTests {
  @Test func `nothing typed lists nothing and selects nothing`() {
    let results = QuickOpenResults()
    #expect(results.rows.isEmpty)
    #expect(results.selected == nil)
    #expect(!results.isSearching)
  }

  @Test func `the exact resolution comes first and is selected`() {
    var results = QuickOpenResults()
    results.show(query: "9110", exact: RFCLink(id: .rfc(9110)))
    results.show(hits: [.rfc(9111), .rfc(9112)], for: "9110")
    #expect(results.rows.map(\.id) == [.rfc(9110), .rfc(9111), .rfc(9112)])
    #expect(results.selected == RFCLink(id: .rfc(9110)))
  }

  /// `9110` resolves to RFC 9110 and also matches it by number; one row, and the
  /// one that keeps the section the link asked for.
  @Test func `a hit the exact resolution already names is dropped`() {
    var results = QuickOpenResults()
    results.show(query: "9110#4.2", exact: RFCLink(id: .rfc(9110), section: "4.2"))
    results.show(hits: [.rfc(9110), .rfc(9111)], for: "9110#4.2")
    #expect(results.rows == [RFCLink(id: .rfc(9110), section: "4.2"), RFCLink(id: .rfc(9111))])
  }

  @Test func `without an exact resolution the first hit is selected`() {
    var results = QuickOpenResults()
    results.show(query: "http", exact: nil)
    results.show(hits: [.rfc(9111), .rfc(7234)], for: "http")
    #expect(results.selected == RFCLink(id: .rfc(9111)))
  }

  @Test func `the list is capped`() {
    var results = QuickOpenResults()
    results.show(query: "1", exact: RFCLink(id: .rfc(1)))
    results.show(hits: (2...20).map(DocumentID.rfc), for: "1")
    #expect(results.rows.count == QuickOpenResults.limit)
    #expect(results.rows.first?.id == .rfc(1))
  }

  @Test func `the selection moves and stops at either end`() {
    var results = QuickOpenResults()
    results.show(query: "a", exact: nil)
    results.show(hits: [.rfc(1), .rfc(2), .rfc(3)], for: "a")
    results.moveSelection(by: -1)
    #expect(results.selected?.id == .rfc(1))
    results.moveSelection(by: 1)
    results.moveSelection(by: 1)
    results.moveSelection(by: 1)
    #expect(results.selected?.id == .rfc(3))
  }

  /// Hits arrive after the keystroke that asked for them. The row the reader moved
  /// to must stay selected when the list changes around it, rather than the
  /// highlight jumping back to the top under their fingers.
  @Test func `the selected row stays selected when the hits change around it`() {
    var results = QuickOpenResults()
    results.show(query: "a", exact: nil)
    results.show(hits: [.rfc(1), .rfc(2), .rfc(3)], for: "a")
    results.moveSelection(by: 2)
    results.show(query: "ab", exact: nil)
    results.show(hits: [.rfc(4), .rfc(3), .rfc(5)], for: "ab")
    #expect(results.selected?.id == .rfc(3))
  }

  @Test func `a selected row that disappears hands the selection to the top`() {
    var results = QuickOpenResults()
    results.show(query: "a", exact: nil)
    results.show(hits: [.rfc(1), .rfc(2)], for: "a")
    results.moveSelection(by: 1)
    results.show(query: "ab", exact: nil)
    results.show(hits: [.rfc(4), .rfc(5)], for: "ab")
    #expect(results.selected?.id == .rfc(4))
  }

  /// A new exact resolution is what the reader just typed, so it takes the
  /// selection even from a row they had moved to.
  @Test func `a new exact resolution takes the selection`() {
    var results = QuickOpenResults()
    results.show(query: "a", exact: nil)
    results.show(hits: [.rfc(1), .rfc(2)], for: "a")
    results.moveSelection(by: 1)
    results.show(query: "2", exact: RFCLink(id: .rfc(2)))
    #expect(results.selected == RFCLink(id: .rfc(2)))
    #expect(results.rows.map(\.id) == [.rfc(2), .rfc(1)])
  }

  /// A trailing space resolves to the same document; the row the reader arrowed to
  /// is still the one they want.
  @Test func `an unchanged exact resolution leaves the selection alone`() {
    var results = QuickOpenResults()
    results.show(query: "bcp 14", exact: RFCLink(id: .rfc(2119)))
    results.show(hits: [.rfc(8174)], for: "bcp 14")
    results.moveSelection(by: 1)
    results.show(query: "bcp 14 ", exact: RFCLink(id: .rfc(2119)))
    #expect(results.selected?.id == .rfc(8174))
  }

  @Test func `hits for a query that has since changed are ignored`() {
    var results = QuickOpenResults()
    results.show(query: "http", exact: nil)
    results.show(query: "http caching", exact: nil)
    results.show(hits: [.rfc(1)], for: "http")
    #expect(results.rows.isEmpty)
    #expect(results.isSearching)
  }

  /// Return must not open a hit found for what was typed a keystroke ago.
  @Test func `nothing is openable from hits of an earlier query`() {
    var results = QuickOpenResults()
    results.show(query: "http", exact: nil)
    results.show(hits: [.rfc(9110)], for: "http")
    #expect(results.openable?.id == .rfc(9110))
    results.show(query: "http caching", exact: nil)
    #expect(results.selected?.id == .rfc(9110))
    #expect(results.openable == nil)
    results.show(hits: [.rfc(9111)], for: "http caching")
    #expect(results.openable?.id == .rfc(9111))
  }

  /// The exact resolution belongs to what is typed now, so it never waits.
  @Test func `the exact resolution is openable before the search returns`() {
    var results = QuickOpenResults()
    results.show(query: "9110", exact: RFCLink(id: .rfc(9110)))
    #expect(results.isSearching)
    #expect(results.openable == RFCLink(id: .rfc(9110)))
  }

  @Test func `clearing the field clears the list`() {
    var results = QuickOpenResults()
    results.show(query: "a", exact: nil)
    results.show(hits: [.rfc(1)], for: "a")
    results.show(query: "", exact: nil)
    #expect(results.rows.isEmpty)
    #expect(results.selected == nil)
    #expect(!results.isSearching)
  }

  // MARK: - A series

  private static let bcp14 = DocumentID(series: .bcp, number: 14)

  /// `BCP 14` stands for two RFCs, and a row that named both could only open one.
  @Test func `a series is listed as one row per member`() {
    var results = QuickOpenResults()
    results.show(
      query: "BCP 14", exact: RFCLink(id: Self.bcp14), members: [.rfc(2119), .rfc(8174)])
    #expect(results.rows == [RFCLink(id: .rfc(2119)), RFCLink(id: .rfc(8174))])
    #expect(results.selected == RFCLink(id: .rfc(2119)))
  }

  /// Every member row is the exact resolution, so none of them waits for the search.
  @Test func `each member row opens the member it names`() {
    var results = QuickOpenResults()
    results.show(
      query: "BCP 14", exact: RFCLink(id: Self.bcp14), members: [.rfc(2119), .rfc(8174)])
    #expect(results.openable == RFCLink(id: .rfc(2119)))
    results.moveSelection(by: 1)
    #expect(results.isSearching)
    #expect(results.openable == RFCLink(id: .rfc(8174)))
  }

  @Test func `a hit a member row already names is dropped`() {
    var results = QuickOpenResults()
    results.show(
      query: "BCP 14", exact: RFCLink(id: Self.bcp14), members: [.rfc(2119), .rfc(8174)])
    results.show(hits: [.rfc(8174), .rfc(7322)], for: "BCP 14")
    #expect(results.rows.map(\.id) == [.rfc(2119), .rfc(8174), .rfc(7322)])
  }

  /// Before the index has loaded there are no members to list.
  @Test func `a series with no known members is listed as itself`() {
    var results = QuickOpenResults()
    results.show(query: "BCP 14", exact: RFCLink(id: Self.bcp14), members: [])
    #expect(results.rows == [RFCLink(id: Self.bcp14)])
  }

  // MARK: - Return

  @Test func `return opens an openable selection at once`() {
    var results = QuickOpenResults()
    results.show(query: "9110", exact: RFCLink(id: .rfc(9110)))
    let opening = results.activate(.newTab(inBackground: true))
    #expect(
      opening == .init(link: RFCLink(id: .rfc(9110)), activation: .newTab(inBackground: true)))
  }

  /// The key press's modifiers are long released by the time the hits land, so the
  /// activation it asked for is kept with it.
  @Test func `return during a search opens what that search selects, as asked`() {
    var results = QuickOpenResults()
    results.show(query: "h", exact: nil)
    results.show(hits: [.rfc(1)], for: "h")
    results.show(query: "ht", exact: nil)
    #expect(results.activate(.newTab(inBackground: true)) == nil)
    let opening = results.show(hits: [.rfc(2), .rfc(3)], for: "ht")
    #expect(opening == .init(link: RFCLink(id: .rfc(2)), activation: .newTab(inBackground: true)))
  }

  @Test func `hits for an earlier query do not fire a pending return`() {
    var results = QuickOpenResults()
    results.show(query: "h", exact: nil)
    results.show(query: "ht", exact: nil)
    _ = results.activate(.here)
    #expect(results.show(hits: [.rfc(1)], for: "h") == nil)
    #expect(results.show(hits: [.rfc(2)], for: "ht")?.link == RFCLink(id: .rfc(2)))
  }

  @Test func `typing on after return is a change of mind`() {
    var results = QuickOpenResults()
    results.show(query: "ht", exact: nil)
    _ = results.activate(.here)
    results.show(query: "htt", exact: nil)
    #expect(results.show(hits: [.rfc(2)], for: "htt") == nil)
  }

  @Test func `a pending return fires once`() {
    var results = QuickOpenResults()
    results.show(query: "ht", exact: nil)
    _ = results.activate(.here)
    #expect(results.show(hits: [.rfc(2)], for: "ht") != nil)
    #expect(results.show(hits: [.rfc(2)], for: "ht") == nil)
  }

  @Test func `return with nothing to open and no search running is not kept`() {
    var results = QuickOpenResults()
    results.show(query: "zzz", exact: nil)
    results.show(hits: [], for: "zzz")
    #expect(results.activate(.here) == nil)
    #expect(results.show(hits: [.rfc(1)], for: "zzz") == nil)
  }

  @Test func `a search that finds nothing opens nothing, and forgets the return`() {
    var results = QuickOpenResults()
    results.show(query: "zzz", exact: nil)
    _ = results.activate(.here)
    #expect(results.show(hits: [], for: "zzz") == nil)
    #expect(results.show(hits: [.rfc(1)], for: "zzz") == nil)
  }
}
