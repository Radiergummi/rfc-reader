import Foundation
import Testing

@testable import RFCKit

/// Anchors: unique, reserved, and reached by every citation.
@Suite("Legacy text parser: anchors")
struct LegacyTextParserAnchorsTests {
  /// An anchor is what a deep link, the table of contents and a reading position key off,
  /// and the XML declares each one as an ID. Headings that repeat gave two sections one
  /// anchor -- RFC 1 has two `Introduction`s, RFC 19 two sections numbered 1 -- and a
  /// bibliography that lists a label twice gave two entries one: 526 documents in all
  /// (#65). A repeat takes the next free `-2`, `-3`, the way xml2rfc numbers them, and
  /// the first keeps its anchor, so every link that landed on it still does.
  @Test func `no two elements share an anchor`() throws {
    let fixtures = try Fixtures.legacyTexts()
    #expect(fixtures.count > 20)
    for fixture in fixtures {
      let document = try Fixtures.document(fixture)
      let repeated = Dictionary(grouping: document.declaredAnchors, by: { $0 }).filter {
        $0.value.count > 1
      }.keys.sorted()
      #expect(repeated.isEmpty, "\(fixture): \(repeated)")
    }

    let first = try Fixtures.document("rfc1.txt").allSections.map(\.anchor)
    let original = try #require(first.firstIndex(of: "name-introduction"))
    let second = try #require(first.firstIndex(of: "name-introduction-2"))
    #expect(original < second)
    #expect(
      try Fixtures.document("rfc19.txt").allSections.map(\.anchor).contains(
        "section-1-2"))

    let entries = try Fixtures.document("rfc1556.txt").referenceLists.flatMap(
      \.entries)
    let relabeled = try #require(entries.first { $0.anchor == "ISO-8859-2" })
    #expect(
      relabeled.displayAnchor == "ISO-8859",
      "a renamed entry still reads as the label its citations use")
  }

  /// The XML declares each anchor as an ID, which has to be a name: `[1]`, `[RFC 2119]`
  /// and `[Cheswick and Bellovin, 1994]` are not, in 2,361 documents (#65). And a
  /// citation of an entry that names no RFC pointed at `ref-<label>`, which no entry was
  /// declared under: RFC 2005 cited `<xref target="ref-MIP-OPTIM">` beside `<reference
  /// anchor="MIP-OPTIM">`, and 30,368 citations in 3,708 documents linked nowhere (#81).
  @Test func `every anchor is a name and every citation reaches one`() throws {
    var cited = 0
    for fixture in try Fixtures.legacyTexts() {
      let document = try Fixtures.document(fixture)
      // An NCName, closely enough: a letter or underscore, then letters, digits, `.`, `-`, `_`.
      let unnamed = document.declaredAnchors.filter {
        $0.wholeMatch(of: #/[\p{L}_][\p{L}0-9._-]*/#) == nil
      }
      #expect(unnamed.isEmpty, "\(fixture): \(unnamed)")
      let targets = document.everyCrossReference.compactMap {
        if case .anchor(let anchor) = $0.target { anchor } else { nil }
      }
      cited += targets.count
      let dangling = Set(targets).subtracting(document.declaredAnchors).sorted()
      #expect(dangling.isEmpty, "\(fixture): \(dangling)")
    }
    #expect(cited > 0, "the fixtures cite something by anchor, so the check checks something")

    // A label that is a name is the anchor, as the published series has it.
    let rfc5234 = try Fixtures.document("rfc5234.txt").referenceLists.flatMap(
      \.entries)
    #expect(rfc5234.contains { $0.anchor == "US-ASCII" && $0.displayAnchor == "US-ASCII" })
    // One that is not takes the document it cites, and still reads as its label: RFC 2023
    // lists RFCs 1883 and 1884 both as `[2]`, and they are two anchors, not one and a `-2`.
    let rfc2023 = try Fixtures.document("rfc2023.txt").referenceLists.flatMap(
      \.entries)
    #expect(rfc2023.filter { $0.displayAnchor == "2" }.map(\.anchor) == ["RFC1883", "RFC1884"])
    let rfc2347 = try Fixtures.document("rfc2347.txt")
    #expect(
      rfc2347.crossReferences.contains {
        $0.target == .document(.rfc(2348), section: nil, entry: "RFC2348") && $0.text == "[2]"
      })
    // And one that cites no document is `ref-` and the label spelled as a name.
    let rfc1556 = try Fixtures.document("rfc1556.txt").referenceLists.flatMap(
      \.entries)
    #expect(rfc1556.contains { $0.anchor == "ref-ECMA-TR-53" && $0.displayAnchor == "ECMA TR/53" })
    let rfc2606 = try Fixtures.document("rfc2606.txt").referenceLists.flatMap(
      \.entries)
    #expect(rfc2606.contains { $0.anchor == "RFC1034" && $0.displayAnchor == "RFC 1034" })
  }

  /// Entry anchors are settled before the prose is linked, so a citation points at the
  /// anchor its entry ends with rather than one a later rename moves. None of these
  /// shapes is in the corpus, so they are pinned at the guard, on entries by hand.
  @Test func `an entry is renamed only onto an anchor nothing else holds`() {
    func settled(_ labels: [String], reserved: Set<String> = []) -> [String] {
      let entries = labels.map {
        Reference(
          anchor: LegacyTextParser.entryAnchor(label: $0, documentID: nil), displayAnchor: $0,
          title: $0)
      }
      return LegacyTextParser.settlingEntryAnchors([0: entries], reserved: reserved)[0]?.map(
        \.anchor) ?? []
    }
    // `[X-2]` keeps its own anchor, so the repeat of `[X]` does not take it from under it.
    #expect(settled(["X", "X", "X-2"]) == ["X", "X-3", "X-2"])
    // Two labels that spell one name are two anchors.
    #expect(settled(["ECMA TR 53", "ECMA TR/53"]) == ["ref-ECMA-TR-53", "ref-ECMA-TR-53-2"])
    // And an entry never takes an anchor a section can have.
    #expect(settled(["section-1"], reserved: ["section-1"]) == ["section-1-2"])
    // A label with nothing of a name in it is a note: RFC 2130's `[*]`, RFC 906's `[**]`.
    #expect(settled(["*", "**"]) == ["ref-note", "ref-note-2"])
  }

  /// A heading that repeats is renamed after the prose is linked, so what an entry must
  /// not take is every anchor a section can be renamed to, not only the ones it starts
  /// with: an entry settled onto `section-1-2` beside two sections numbered 1 lost it to
  /// the second, and its citations to a rename. Every suffix a repeat can reach is held,
  /// past the ones another heading already spells (`name-foo-2`, for `Foo 2`).
  @Test func `a repeated heading holds every anchor it can be renamed to`() {
    #expect(
      LegacyTextParser.reservedAnchors(["section-1", "section-1"]) == ["section-1", "section-1-2"])
    #expect(
      LegacyTextParser.reservedAnchors(["name-foo", "name-foo", "name-foo-2"]) == [
        "name-foo", "name-foo-2", "name-foo-3",
      ])
    #expect(
      LegacyTextParser.reservedAnchors(["section-1", "section-2"]) == ["section-1", "section-2"])
  }

  /// What `parse` reserves is every anchor its sections end with, and no entry holds one:
  /// RFC 19 numbers two sections 1, and the second is `section-1-2`.
  @Test func `every section anchor is reserved and no entry holds one`() throws {
    #expect(
      try LegacyTextParser.reservedAnchors(in: Fixtures.string("rfc19.txt")).contains("section-1-2")
    )
    for fixture in try Fixtures.legacyTexts() {
      let text = try Fixtures.string(fixture)
      let reserved = LegacyTextParser.reservedAnchors(in: text)
      let document = try Fixtures.document(fixture)
      let unreserved = Set(document.allSections.map(\.anchor)).subtracting(reserved).sorted()
      #expect(unreserved.isEmpty, "\(fixture): \(unreserved)")
      let held = Set(document.referenceLists.flatMap(\.entries).map(\.anchor)).intersection(
        reserved
      ).sorted()
      #expect(held.isEmpty, "\(fixture): \(held)")
    }
  }
}
