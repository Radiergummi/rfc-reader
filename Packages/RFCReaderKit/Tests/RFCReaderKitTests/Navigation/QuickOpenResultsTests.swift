import RFCKit
import Testing

@testable import RFCReaderKit

/// The Go to RFC palette's list: what was typed, resolved exactly, and then what the
/// search found for it.
@Suite("Quick open results")
struct QuickOpenResultsTests {
  /// Typing `9` then `99`: until the search for `99` lands, the hits for `9` are
  /// all there is. RFC 9 is not a number `99` begins, and showing it for that moment
  /// pushed every row below it down and back up again. A number's hits are known
  /// without searching, so the earlier ones that no longer match go on the keystroke,
  /// and those that stay keep their order.
  @Test func `an earlier number's hits that the new number does not begin go at once`() {
    var results = QuickOpenResults()
    results.show(query: "9", exact: RFCLink(id: .rfc(9)))
    results.show(hits: [.rfc(9), .rfc(9999), .rfc(9998), .rfc(991), .rfc(99)], for: "9")
    results.show(query: "99", exact: RFCLink(id: .rfc(99)))
    #expect(results.rows.map(\.link.id) == [.rfc(99), .rfc(9999), .rfc(9998), .rfc(991)])
  }

  /// Words are not numbers: what `http` found may still match `http c`, and only
  /// the search knows, so those hits stay until it answers.
  @Test func `an earlier query's hits stay while words are searched`() {
    var results = QuickOpenResults()
    results.show(query: "http", exact: nil)
    results.show(hits: [.rfc(9110), .rfc(9111)], for: "http")
    results.show(query: "http c", exact: nil)
    #expect(results.rows.map(\.link.id) == [.rfc(9110), .rfc(9111)])
  }

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
    #expect(results.rows.map(\.link.id) == [.rfc(9110), .rfc(9111), .rfc(9112)])
    #expect(results.selected?.link == RFCLink(id: .rfc(9110)))
  }

  /// `9110` resolves to RFC 9110 and also matches it by number; one row, and the
  /// one that keeps the section the link asked for.
  @Test func `a hit the exact resolution already names is dropped`() {
    var results = QuickOpenResults()
    results.show(query: "9110#4.2", exact: RFCLink(id: .rfc(9110), section: "4.2"))
    results.show(hits: [.rfc(9110), .rfc(9111)], for: "9110#4.2")
    #expect(
      results.rows.map(\.link) == [
        RFCLink(id: .rfc(9110), section: "4.2"), RFCLink(id: .rfc(9111)),
      ])
  }

  @Test func `without an exact resolution the first hit is selected`() {
    var results = QuickOpenResults()
    results.show(query: "http", exact: nil)
    results.show(hits: [.rfc(9111), .rfc(7234)], for: "http")
    #expect(results.selected?.link == RFCLink(id: .rfc(9111)))
  }

  @Test func `the list is capped`() {
    var results = QuickOpenResults()
    results.show(query: "1", exact: RFCLink(id: .rfc(1)))
    results.show(hits: (2...20).map(DocumentID.rfc), for: "1")
    #expect(results.rows.count == QuickOpenResults.limit)
    #expect(results.rows.first?.link.id == .rfc(1))
  }

  @Test func `the selection moves and stops at either end`() {
    var results = QuickOpenResults()
    results.show(query: "a", exact: nil)
    results.show(hits: [.rfc(1), .rfc(2), .rfc(3)], for: "a")
    results.moveSelection(by: -1)
    #expect(results.selected?.link.id == .rfc(1))
    results.moveSelection(by: 1)
    results.moveSelection(by: 1)
    results.moveSelection(by: 1)
    #expect(results.selected?.link.id == .rfc(3))
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
    #expect(results.selected?.link.id == .rfc(3))
  }

  @Test func `a selected row that disappears hands the selection to the top`() {
    var results = QuickOpenResults()
    results.show(query: "a", exact: nil)
    results.show(hits: [.rfc(1), .rfc(2)], for: "a")
    results.moveSelection(by: 1)
    results.show(query: "ab", exact: nil)
    results.show(hits: [.rfc(4), .rfc(5)], for: "ab")
    #expect(results.selected?.link.id == .rfc(4))
  }

  /// A new exact resolution is what the reader just typed, so it takes the
  /// selection even from a row they had moved to.
  @Test func `a new exact resolution takes the selection`() {
    var results = QuickOpenResults()
    results.show(query: "a", exact: nil)
    results.show(hits: [.rfc(1), .rfc(2)], for: "a")
    results.moveSelection(by: 1)
    results.show(query: "2", exact: RFCLink(id: .rfc(2)))
    #expect(results.selected?.link == RFCLink(id: .rfc(2)))
    // RFC 1, found for `a`, is not a number `2` begins, so it is gone already.
    #expect(results.rows.map(\.link.id) == [.rfc(2)])
  }

  /// A trailing space resolves to the same document; the row the reader arrowed to
  /// is still the one they want.
  @Test func `an unchanged exact resolution leaves the selection alone`() {
    var results = QuickOpenResults()
    results.show(query: "bcp 14", exact: RFCLink(id: .rfc(2119)))
    results.show(hits: [.rfc(8174)], for: "bcp 14")
    results.moveSelection(by: 1)
    results.show(query: "bcp 14 ", exact: RFCLink(id: .rfc(2119)))
    #expect(results.selected?.link.id == .rfc(8174))
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
    #expect(results.selected?.link.id == .rfc(9110))
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
    #expect(results.rows.map(\.link) == [RFCLink(id: .rfc(2119)), RFCLink(id: .rfc(8174))])
    #expect(results.selected?.link == RFCLink(id: .rfc(2119)))
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
    #expect(results.rows.map(\.link.id) == [.rfc(2119), .rfc(8174), .rfc(7322)])
  }

  /// A fragment that names no section is the place each member row opens at, as a
  /// section is (#276).
  @Test func `a member row keeps the links anchor`() {
    var results = QuickOpenResults()
    results.show(
      query: "rfc://bcp14#sample", exact: RFCLink(id: Self.bcp14, anchor: "sample"),
      members: [.rfc(2119)])
    #expect(results.rows.map(\.link) == [RFCLink(id: .rfc(2119), anchor: "sample")])
  }

  /// Before the index has loaded there are no members to list.
  @Test func `a series with no known members is listed as itself`() {
    var results = QuickOpenResults()
    results.show(query: "BCP 14", exact: RFCLink(id: Self.bcp14), members: [])
    #expect(results.rows.map(\.link) == [RFCLink(id: Self.bcp14)])
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

  // MARK: - Registries

  private static let tooEarly = RegistryEntry(
    registry: .httpStatusCodes, value: "425", name: "Too Early",
    references: [RFCLink(id: .rfc(8470))])
  private static let flowControl = RegistryEntry(
    registry: .quicTransportErrors, value: "0x03", name: "FLOW_CONTROL_ERROR",
    references: [RFCLink(id: .rfc(9000), section: "20")])
  private static let streamLimit = RegistryEntry(
    registry: .quicTransportErrors, value: "0x04", name: "STREAM_LIMIT_ERROR",
    references: [RFCLink(id: .rfc(9000), section: "20")])

  /// A registry match is known on the keystroke, like the exact resolution, so it
  /// is listed before the search's hits and does not wait for them (#175).
  @Test func `a registry match comes after the exact row and before the hits`() {
    var results = QuickOpenResults()
    results.show(query: "425", exact: RFCLink(id: .rfc(425)), registry: [Self.tooEarly])
    results.show(hits: [.rfc(8470), .rfc(9110)], for: "425")
    #expect(
      results.rows.map(\.link) == [
        RFCLink(id: .rfc(425)), RFCLink(id: .rfc(8470)), RFCLink(id: .rfc(8470)),
        RFCLink(id: .rfc(9110)),
      ])
    #expect(results.rows.map(\.entry) == [nil, Self.tooEarly, nil, nil])
  }

  @Test func `without an exact resolution a registry match is selected and openable`() {
    var results = QuickOpenResults()
    results.show(query: "too early", exact: nil, registry: [Self.tooEarly])
    #expect(results.selected?.entry == Self.tooEarly)
    #expect(results.openable == RFCLink(id: .rfc(8470)))
  }

  /// Every QUIC error is defined in RFC 9000, section 20: two matches opening the
  /// same place are still two rows, and the selection tells them apart.
  @Test func `two registry matches opening one place are two rows`() {
    var results = QuickOpenResults()
    results.show(query: "quic", exact: nil, registry: [Self.flowControl, Self.streamLimit])
    #expect(results.rows.count == 2)
    results.moveSelection(by: 1)
    #expect(results.selected?.entry == Self.streamLimit)
  }

  /// A value defined outside the RFCs has nowhere to open.
  @Test func `a registry match that cites no RFC is not listed`() {
    var results = QuickOpenResults()
    let provisional = RegistryEntry(
      registry: .httpStatusCodes, value: "104", name: "Provisional", references: [])
    results.show(query: "104", exact: nil, registry: [provisional])
    #expect(results.rows.isEmpty)
  }

  /// `HTTP2-Settings` cites RFC 7540, then RFC 9113, which obsoletes it: the row
  /// opens the one the index says is current.
  @Test func `a registry match opens the reference that is not obsoleted`() {
    var results = QuickOpenResults()
    let settings = RegistryEntry(
      registry: .httpFieldNames, value: "HTTP2-Settings", name: nil,
      references: [RFCLink(id: .rfc(7540)), RFCLink(id: .rfc(9113))])
    results.show(
      query: "HTTP2-Settings", exact: nil, registry: [settings],
      isObsolete: { $0 == .rfc(7540) })
    #expect(results.rows.map(\.link) == [RFCLink(id: .rfc(9113))])
  }
}
