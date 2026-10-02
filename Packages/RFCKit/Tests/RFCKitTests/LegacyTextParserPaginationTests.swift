import Foundation
import Testing

@testable import RFCKit

/// Depagination: page headers and footers, running headers, tabs and control bytes.
@Suite("Legacy text parser: page furniture")
struct LegacyTextParserPaginationTests {
  @Test func `strips page furniture`() throws {
    let text = try Fixtures.string("rfc2119.txt")
    let stripped = LegacyTextParser.stripPagination(text)
    #expect(!stripped.contains("[Page 1]"))
    #expect(!stripped.contains("RFC 2119                     RFC Key Words"))
    #expect(!stripped.contains("\u{0C}"))
    #expect(
      stripped.contains("Request for Comments: 2119"),
      "the first-page header block is content, not furniture")
    #expect(stripped.contains("6. Guidance in the use of these Imperatives"))
  }

  /// A tab is eight columns, but `leadingSpaceCount` counted spaces only, so a line
  /// indented with one read as indent 0 (#40). RFC 717 indents a list with tabs
  /// under prose indented six spaces: the block's indent came out as 0, the four
  /// columns its figure shares were never stripped, and the tabs themselves reached
  /// the reader, whose verbatim style sets no tab stops.
  @Test func `tabs are columns before any indent is read`() throws {
    let document = try Fixtures.document("rfc717.txt")
    let artwork = document.artworkText
    #expect(!artwork.contains { $0.contains("\t") }, "a tab survived into artwork")
    #expect(
      !document.allSections.contains { $0.titleText.contains("\t") },
      "a tab survived into a heading")

    let header = try #require(artwork.first { $0.contains("Destination net") })
    let lines = header.split(separator: "\n", omittingEmptySubsequences: false)
    // The block's indent is four, from `    0`, and every line loses exactly that.
    #expect(lines.first == "0           Destination net          (8)")
    #expect(lines.contains { $0.hasPrefix("  This field") })
    #expect(lines.contains { $0.hasPrefix("    0 -- Escape") })
  }

  /// RFC 793 repeats a three-line page header on 62 pages, justified left and right on
  /// facing pages, and it names no RFC, so the running-header pattern never matched it
  /// (#52). Each page then opened with `Transmission Control Protocol` at column 0,
  /// which is a heading: ~33 sections called `Functional Specification`, and every
  /// paragraph that crossed a page break cut in two by one of them.
  @Test func `recurring page headers are furniture not sections`() throws {
    let document = try Fixtures.document("rfc793.txt")
    let furniture = ["Transmission Control Protocol", "Functional Specification", "September 1981"]
    let spurious = document.allSections.filter { furniture.contains($0.titleText) }
    #expect(spurious.isEmpty, "\(spurious.count) sections are page headers")
    // The third line names the section the page is in -- `Introduction` on four
    // pages, `Philosophy` on six -- and each of those sections is already headed
    // `1.  INTRODUCTION`, `2.  PHILOSOPHY`, so none of it is a heading either.
    let unnumbered = document.allSections.filter { $0.number == nil }.map(\.titleText)
    let repeated = Dictionary(grouping: unnumbered, by: \.self).filter { $0.value.count > 1 }.keys
    #expect(repeated.isEmpty, "unnumbered headings that repeat: \(repeated.sorted())")
    #expect(!unnumbered.contains("Philosophy"))
    // Nor is its first copy in the as-published view, which drops what `parse` drops.
    let published = LegacyTextParser.stripPagination(try Fixtures.string("rfc793.txt"))
      .split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
    #expect(!published.contains("Philosophy"))

    // With the header gone the page break is only a page break, and the sentence
    // across it is one paragraph again.
    let paragraphs = document.paragraphs.map(\.plainText)
    #expect(
      paragraphs.contains { $0.contains("(RCV.NXT)") && $0.contains("\"normal mode\"") },
      "the terms on either side of the page break are in one paragraph")
  }

  /// A section running header is furniture on every page but the first, where it is
  /// the only thing that says a section starts. RFC 770 heads its bibliography with
  /// a centered `REFERENCES` that is no heading, and a running `References` on each of
  /// its pages; dropping every one of those lost all 58 entries.
  @Test func `a section running header still opens its section`() throws {
    let document = try Fixtures.document("rfc770.txt")
    let lists = document.referenceLists
    #expect(lists.flatMap(\.entries).count == 58)
    #expect(document.allSections.filter { $0.titleText == "References" }.count == 1)
  }

  /// A header that alternates between facing pages is on every other page, so it is
  /// on half of them at most, and just under half where the last pages carry none.
  /// RFC 810 sets `RFC 810 ... 1 March 1982` on its even pages, which the running-header
  /// pattern knows, and `1 March 1982 ... RFC 810` on its odd ones, which it does not:
  /// on three of eight, that header was read as a section's, and its first copy
  /// stayed in the body.
  @Test func `a header on alternate pages names the document`() throws {
    let text = try Fixtures.string("rfc810.txt")
    #expect(
      LegacyTextParser.recurringFurniture(in: text).filter { $0.hasPrefix("1 March 1982") }.count
        == 3)
    let body = LegacyTextParser.stripPagination(text).split(separator: "\n")
    #expect(!body.contains { $0.hasPrefix("1 March 1982") && $0.hasSuffix("RFC 810") })
  }

  /// Only a whole number varies from page to page, so only a whole number is masked
  /// when furniture is compared. RFC 2049 sets one-line anchors in its bibliography
  /// and four of them land at a page edge; masking every digit made `[RFC-1522]` and
  /// `[RFC-1524]` the same line recurring across pages, and both were dropped.
  @Test func `numbers inside a word do not make two lines the same`() throws {
    let document = try Fixtures.document("rfc2049.txt")
    let anchors = document.referenceLists.flatMap { $0.entries.map(\.anchor) }
    #expect(anchors.contains("RFC-1522"))
    #expect(anchors.contains("RFC-1524"))
    #expect(anchors.count == 42)
  }

  /// A line that recurs at page edges is furniture only if it is not also the body's.
  /// RFC 2013 is a MIB module, where every object ends in `STATUS current` and a
  /// `DESCRIPTION`, and those fall within four lines of the foot of three pages; read
  /// as a section running header, every copy after the first was dropped from the
  /// module. A running header sits at the head of its pages, on every page of its
  /// section, set off by a blank line -- and is rarer anywhere else than at the edge.
  @Test func `a line the body repeats is not furniture`() throws {
    let text = try Fixtures.string("rfc2013.txt")
    let document = try Fixtures.document("rfc2013.txt")
    func count(_ line: String, in text: String) -> Int {
      text.split(separator: "\n").filter {
        $0.split(whereSeparator: \.isWhitespace).joined(separator: " ") == line
      }.count
    }
    let artwork = document.artworkText.joined(separator: "\n")
    for line in ["STATUS current", "DESCRIPTION"] {
      #expect(count(line, in: artwork) == count(line, in: text), "\(line)")
    }
  }

  /// A section running header belongs to the block that opens its page, directly under
  /// the document's own header. RFC 6208 registers five media types, and each
  /// registration's `Additional information:` falls at the head of a page -- but below
  /// the blank lines the removed `RFC 6208 ... April 2011` leaves, and every copy but
  /// the first was dropped as the running header of a section.
  @Test func `a line below the page header is not a section running header`() throws {
    let text = try Fixtures.string("rfc6208.txt")
    let body = LegacyTextParser.stripPagination(text)
    func count(_ text: String) -> Int {
      text.split(separator: "\n").filter {
        $0.trimmingCharacters(in: .whitespaces) == "Additional information:"
      }.count
    }
    #expect(count(body) == count(text))
    #expect(
      LegacyTextParser.recurringFurniture(in: text).allSatisfy {
        !$0.contains("Additional information:")
      })
  }

  /// Furniture recurs in the same place, so a line at the foot of one page and a line
  /// at the head of the next are not two sightings of it. RFC 1556 cites ISO 8859
  /// parts 6 and 8 as one anchor each, word for word the same up to the part number
  /// on the entry's third line, and the pair straddles a page break.
  @Test func `the same line at opposite edges is not a running header`() throws {
    let document = try Fixtures.document("rfc1556.txt")
    let labels = document.referenceLists.flatMap { $0.entries.map(\.displayAnchor) }
    #expect(labels.filter { $0 == "ISO-8859" }.count == 2)
    #expect(labels.count == 7)
  }

  @Test func `overstrikes and control bytes are removed`() {
    let bold = "T\u{08}Ta\u{08}ab\u{08}bl\u{08}le\u{08}e"
    let underlined = "_\u{08}R_\u{08}F_\u{08}C"
    #expect(LegacyTextParser.removingControlCharacters(bold) == "Table")
    #expect(LegacyTextParser.removingControlCharacters(underlined) == "RFC")
    #expect(LegacyTextParser.removingControlCharacters("a\u{00}\u{1B}b\tc\u{0C}") == "ab\tc\u{0C}")
    #expect(LegacyTextParser.removingControlCharacters("plain") == "plain")
  }
}

/// A section running header's first sighting opens its section only where the
/// document does not head that section itself nearby: on the header's page or the
/// two before it (#291, #57). Hand-written lines in the shape of an RFC's pages.
@Suite("Section running headers")
struct SectionHeaderTests {
  private typealias Line = LegacyTextParser.Line

  /// A page: its header block, a blank line, then its body.
  private func page(header: String? = nil, _ body: [String]) -> [Line] {
    var lines: [Line] = []
    if let header { lines += [.sectionHeader(header, sighting: 0), .text("")] }
    return lines + body.map(Line.text) + [.text(""), .pageBreak]
  }

  private func headsNearby(_ lines: [Line]) -> Bool {
    let index = lines.firstIndex(where: \.isSectionHeader)!
    return LegacyTextParser.headsNearby(
      at: index, in: lines, from: 0, bodyIsIndented: true, colonNumbered: false)
  }

  /// The section starts at the head of one page, whose header still names the last
  /// one, and its own name first runs on the next.
  @Test func `a heading on the page before heads the section`() {
    let lines =
      page(["4.  Retry Handling", "", "   A sender waits before it sends again."])
      + page(header: "Retry Handling", ["   The wait doubles each time."])
    #expect(headsNearby(lines))
  }

  /// Centered, as some documents set their chapter headings: still the document's own.
  @Test func `a centered numbered heading heads the section`() {
    let lines =
      page(["                     4.  RETRY HANDLING", "", "   A sender waits."])
      + page(header: "Retry Handling", ["   The wait doubles each time."])
    #expect(headsNearby(lines))
  }

  @Test func `a heading on the same page heads the section`() {
    let lines = page(header: "Retry Handling", ["4.  Retry Handling", "", "   A sender waits."])
    #expect(headsNearby(lines))
  }

  /// A number in the header is part of what it says, not a page number to mask:
  /// compared as the heading reads, the two agree (#57).
  @Test func `a header with a number in it matches its heading`() {
    let lines =
      page(["4.  Phase 2 Exchange", "", "   Its round follows the first."])
      + page(header: "Phase 2 Exchange", ["   It carries the keys."])
    #expect(headsNearby(lines))
  }

  /// The same words headed pages away speak for nothing here: this header is the
  /// only thing saying where its section starts.
  @Test func `a heading further away does not head the section`() {
    let lines =
      page(["2.  Retry Handling", "", "   Named here in passing."])
      + page(["   Other matters."])
      + page(["   More of them."])
      + page(header: "Retry Handling", ["   The list of entries."])
    #expect(!headsNearby(lines))
  }

  /// A heading of other words on the page is another section's.
  @Test func `a heading of other words does not head the section`() {
    let lines =
      page(["4.  Timers", "", "   A sender keeps two."])
      + page(header: "Retry Handling", ["   The wait doubles each time."])
    #expect(!headsNearby(lines))
  }

  /// A header that carries its section's number is read as the heading it copies.
  @Test func `a numbered header matches its numbered heading`() {
    let lines =
      page(["4.  Retry Handling", "", "   A sender waits."])
      + page(header: "4.  Retry Handling", ["   The wait doubles each time."])
    #expect(headsNearby(lines))
  }

  /// A header numbered otherwise names another section, whatever its words.
  @Test func `a header with another number does not match the heading`() {
    let lines =
      page(["4.  Retry Handling", "", "   A sender waits."])
      + page(header: "5.  Retry Handling", ["   The wait doubles each time."])
    #expect(!headsNearby(lines))
  }

  /// An appendix header with no title is told from another by its letter alone.
  @Test func `a titleless appendix header matches only its own letter`() {
    let other =
      page(["APPENDIX A", "", "   The first list."])
      + page(header: "Appendix B", ["   The second list."])
    #expect(!headsNearby(other))
    let own =
      page(["APPENDIX B", "", "   The second list."])
      + page(header: "Appendix B", ["   Its entries go on."])
    #expect(headsNearby(own))
  }

  /// Where the headers alternate between facing pages, a section's name first runs
  /// two pages after the page it starts on.
  @Test func `a heading two pages before heads the section`() {
    let lines =
      page(["4.  Retry Handling", "", "   A sender waits."])
      + page(["   The wait doubles each time."])
      + page(header: "Retry Handling", ["   It gives up after the fifth."])
    #expect(headsNearby(lines))
  }

  /// The front matter's contents list the headings; none of its entries heads a
  /// section of the body.
  @Test func `a contents entry in the front matter does not head the section`() {
    let contents = page(["   4.  Retry Handling"])
    let lines = contents + page(header: "Retry Handling", ["   The wait doubles each time."])
    let index = lines.firstIndex(where: \.isSectionHeader)!
    #expect(
      !LegacyTextParser.headsNearby(
        at: index, in: lines, from: contents.count, bodyIsIndented: true,
        colonNumbered: false))
  }
}
